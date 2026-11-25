import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:kover/utils/storage/storage_adapter.dart';
import 'package:kover/utils/storage/storage_adapter_io.dart';
import 'package:path/path.dart' as p;

void main() {
  final adapterFactories =
      <String, Future<(StorageAdapter, Directory?)> Function()>{
        'IoStorageAdapter': () async {
          final dir = await Directory.systemTemp.createTemp(
            'kover_storage_io_',
          );
          return (IoStorageAdapter(dir.path), dir);
        },
        'IoStorageAdapter.lazy': () async {
          final parent = await Directory.systemTemp.createTemp(
            'kover_storage_lazy_',
          );
          final lazyDir = Directory(p.join(parent.path, 'nested'));
          return (IoStorageAdapter.lazy(() async => lazyDir), parent);
        },
        'MemoryStorageAdapter': () async => (MemoryStorageAdapter(), null),
      };

  for (final entry in adapterFactories.entries) {
    group(entry.key, () {
      late StorageAdapter adapter;
      Directory? tempDir;

      setUp(() async {
        final created = await entry.value();
        adapter = created.$1;
        tempDir = created.$2;
      });

      tearDown(() async {
        final dir = tempDir;
        if (dir != null && await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      test(
        'writes, overwrites, reads bytes, checks existence, and tracks size',
        () async {
          final initial = Uint8List.fromList([1, 2, 3, 4]);
          final updated = Uint8List.fromList([9, 8]);

          await adapter.writeBytes('series/1/cover.jpg', initial);
          expect(await adapter.exists('series/1/cover.jpg'), isTrue);
          expect(await adapter.readBytes(r'\series\1\cover.jpg'), initial);
          expect(await adapter.totalSizeBytes(), 4);

          await adapter.writeBytes('/series/1/cover.jpg', updated);
          expect(await adapter.readBytes('series/1/cover.jpg'), updated);
          expect(await adapter.totalSizeBytes(), 2);
        },
      );

      test(
        'returns null and false for missing keys and ignores missing deletes',
        () async {
          expect(await adapter.exists('missing/page.bin'), isFalse);
          expect(await adapter.readBytes('missing/page.bin'), isNull);

          await adapter.delete('missing/page.bin');

          expect(await adapter.listKeys(), isEmpty);
          expect(await adapter.totalSizeBytes(), 0);
        },
      );

      test(
        'writes streams atomically and preserves prior bytes on stream error',
        () async {
          final original = Uint8List.fromList([10, 20, 30, 40, 50]);
          await adapter.writeStream(
            'chapters/1/0',
            Stream<List<int>>.fromIterable(const [
              [10, 20],
              [30, 40, 50],
            ]),
          );
          expect(await adapter.readBytes('chapters/1/0'), original);

          Stream<List<int>> failingChunks() async* {
            yield const [99, 98];
            throw StateError('interrupted');
          }

          await expectLater(
            adapter.writeStream('chapters/1/0', failingChunks()),
            throwsStateError,
          );
          expect(await adapter.readBytes('chapters/1/0'), original);
          expect(await adapter.listKeys(), ['chapters/1/0']);

          final baseDir = await adapter.resolveBaseDir();
          if (baseDir != null) {
            final leftovers = Directory(baseDir)
                .listSync(recursive: true)
                .where((e) => e.path.contains('.tmp.'))
                .toList();
            expect(leftovers, isEmpty);
          }
        },
      );

      test(
        'enforces trailing slash boundary between chapters/1 and chapters/10',
        () async {
          final one = Uint8List.fromList([1]);
          await adapter.writeBytes('chapters/1/0', one);
          await adapter.writeBytes('chapters/1/1', one);
          await adapter.writeBytes('chapters/10/0', one);
          await adapter.writeBytes('books/2/index.xhtml', one);

          expect(await adapter.listKeys(), [
            'books/2/index.xhtml',
            'chapters/1/0',
            'chapters/1/1',
            'chapters/10/0',
          ]);
          expect(await adapter.listKeys(prefix: 'chapters/1'), [
            'chapters/1/0',
            'chapters/1/1',
          ]);
          expect(await adapter.listKeys(prefix: 'chapters/1/'), [
            'chapters/1/0',
            'chapters/1/1',
          ]);

          await adapter.deletePrefix('chapters/1');
          expect(await adapter.listKeys(), [
            'books/2/index.xhtml',
            'chapters/10/0',
          ]);

          await adapter.writeBytes('chapters/1/2', one);
          await adapter.deletePrefix('chapters/1/');
          expect(await adapter.exists('chapters/1/2'), isFalse);
          expect(await adapter.exists('chapters/10/0'), isTrue);
        },
      );

      test(
        'stamps .storage_epoch on init and preserves bytes across removals',
        () async {
          expect(await adapter.exists(StorageAdapter.epochKey), isTrue);
          final epoch = await adapter.readBytes(StorageAdapter.epochKey);
          expect(epoch, isNotNull);
          expect(epoch, isNotEmpty);
          expect(await adapter.listKeys(), isEmpty);
          expect(await adapter.totalSizeBytes(), 0);

          await adapter.writeBytes(
            'chapters/1/0',
            Uint8List.fromList([7, 8, 9]),
          );
          await adapter.delete(StorageAdapter.epochKey);
          await adapter.deletePrefix('chapters/1');
          await adapter.writeBytes(
            'series/2/cover.png',
            Uint8List.fromList([4, 5]),
          );
          await adapter.clear();

          expect(await adapter.listKeys(), isEmpty);
          expect(await adapter.readBytes(StorageAdapter.epochKey), epoch);
          await expectLater(
            adapter.writeBytes(StorageAdapter.epochKey, Uint8List(1)),
            throwsArgumentError,
          );
          await expectLater(
            adapter.writeStream(
              StorageAdapter.epochKey,
              const Stream<List<int>>.empty(),
            ),
            throwsArgumentError,
          );
        },
      );

      test(
        'rejects invalid keys and empty or traversal prefixes with ArgumentError',
        () async {
          const badKeys = [
            '',
            '/',
            'chapters/1/',
            'chapters//1',
            '.',
            '..',
            '../secret',
            'chapters/../secret',
            'chapters/./0',
            'C:/secret',
            r'C:\secret',
            'chapters/1:ads',
            'bad\x00key',
            'chapters/page.tmp.1',
            '.storage_epoch/nested',
          ];
          for (final badKey in badKeys) {
            await expectLater(
              adapter.writeBytes(badKey, Uint8List(1)),
              throwsArgumentError,
            );
            await expectLater(adapter.readBytes(badKey), throwsArgumentError);
            await expectLater(
              adapter.resolveFilePath(badKey),
              throwsArgumentError,
            );
          }

          const badPrefixes = [
            '',
            '/',
            '//',
            '..',
            '../chapters',
            'C:/secret',
            r'C:\secret',
            'chapters//1',
            '.storage_epoch',
            'chapters/page.tmp.1',
          ];
          for (final badPrefix in badPrefixes) {
            await expectLater(
              adapter.deletePrefix(badPrefix),
              throwsArgumentError,
            );
          }

          await expectLater(adapter.listKeys(prefix: '/'), throwsArgumentError);
          expect(normalizeStoragePrefix(r'\chapters\1\'), 'chapters/1/');
        },
      );
    });
  }

  test(
    'lazy IoStorageAdapter defers directory creation and retries failed init',
    () async {
      final parent = await Directory.systemTemp.createTemp('kover_lazy_defer_');
      addTearDown(() async {
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });
      final targetDir = Directory(p.join(parent.path, 'deferred'));
      var calls = 0;
      var shouldFail = true;
      final adapter = IoStorageAdapter.lazy(() async {
        calls++;
        if (shouldFail) {
          throw const FileSystemException('transient');
        }
        return targetDir;
      });

      expect(calls, 0);
      expect(await targetDir.exists(), isFalse);
      await expectLater(
        adapter.resolveBaseDir(),
        throwsA(isA<FileSystemException>()),
      );

      shouldFail = false;
      expect(await adapter.resolveBaseDir(), targetDir.path);
      expect(calls, 2);
      expect(await targetDir.exists(), isTrue);
      expect(await adapter.exists(StorageAdapter.epochKey), isTrue);
    },
  );

  test(
    'resolveBaseDir and resolveFilePath return native paths only when on disk',
    () async {
      final dir = await Directory.systemTemp.createTemp('kover_resolve_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final io = StorageAdapter(baseDir: dir.path);
      final mem = MemoryStorageAdapter();

      expect(await io.resolveBaseDir(), dir.path);
      expect(await io.resolveFilePath('chapters/1/0'), isNull);
      await io.writeBytes('chapters/1/0', Uint8List.fromList([42]));
      expect(
        await io.resolveFilePath('chapters/1/0'),
        p.join(dir.path, 'chapters', '1', '0'),
      );
      expect(await io.resolveFilePath(StorageAdapter.epochKey), isNull);

      await mem.writeBytes('chapters/1/0', Uint8List.fromList([42]));
      expect(await mem.resolveBaseDir(), isNull);
      expect(await mem.resolveFilePath('chapters/1/0'), isNull);
      expect(await mem.resolveFilePath(StorageAdapter.epochKey), isNull);
    },
  );

  test(
    'ignores leftover .tmp. files and keeps existing .storage_epoch on disk',
    () async {
      final dir = await Directory.systemTemp.createTemp('kover_tmp_epoch_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final preseededEpoch = Uint8List.fromList([1, 3, 3, 7]);
      await File(
        p.join(dir.path, StorageAdapter.epochKey),
      ).writeAsBytes(preseededEpoch);

      final adapter = IoStorageAdapter(dir.path);
      await adapter.writeBytes(
        'chapters/1/0',
        Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      await File(
        p.join(dir.path, 'chapters', '1', '0.tmp.orphan'),
      ).writeAsBytes(const [9, 9, 9, 9]);

      expect(await adapter.readBytes(StorageAdapter.epochKey), preseededEpoch);
      expect(await adapter.listKeys(), ['chapters/1/0']);
      expect(await adapter.listKeys(prefix: 'chapters/1'), ['chapters/1/0']);
      expect(await adapter.totalSizeBytes(), 5);
    },
  );

  test(
    'skips locked Windows files in delete and deletePrefix without throwing',
    () async {
      final dir = await Directory.systemTemp.createTemp('kover_win_lock_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final adapter = IoStorageAdapter(dir.path);
      await adapter.writeBytes('chapters/1/0', Uint8List.fromList([1]));
      await adapter.writeBytes('chapters/1/1', Uint8List.fromList([2]));
      await adapter.writeBytes('chapters/10/0', Uint8List.fromList([3]));

      final lockedPath = (await adapter.resolveFilePath('chapters/1/0'))!;
      final raf = await File(lockedPath).open(mode: FileMode.append);
      await raf.lock();
      try {
        await adapter.delete('chapters/1/0');
        await adapter.deletePrefix('chapters/1');
        expect(await adapter.exists('chapters/1/1'), isFalse);
        expect(await adapter.exists('chapters/10/0'), isTrue);
        expect(await adapter.exists('chapters/1/0'), SafePlatform.isWindows);
      } finally {
        await raf.unlock();
        await raf.close();
      }

      await adapter.delete('chapters/1/0');
      expect(await adapter.exists('chapters/1/0'), isFalse);
    },
  );

  test(
    'flushes MemoryStorageAdapter in fakeAsync microtasks and copies buffers',
    () {
      fakeAsync((async) {
        final adapter = MemoryStorageAdapter();
        final source = Uint8List.fromList([10, 20, 30]);
        Uint8List? firstRead;
        Uint8List? secondRead;
        List<String>? keys;

        unawaited(adapter.writeBytes('books/1/ch.xhtml', source));
        async.flushMicrotasks();
        source[0] = 99;

        unawaited(
          adapter.readBytes('books/1/ch.xhtml').then((v) => firstRead = v),
        );
        async.flushMicrotasks();
        expect(firstRead, [10, 20, 30]);

        firstRead![1] = 88;
        unawaited(
          adapter.readBytes('books/1/ch.xhtml').then((v) => secondRead = v),
        );
        unawaited(adapter.listKeys().then((v) => keys = v));
        async.flushMicrotasks();
        expect(secondRead, [10, 20, 30]);
        expect(keys, ['books/1/ch.xhtml']);
      });
    },
  );
}
