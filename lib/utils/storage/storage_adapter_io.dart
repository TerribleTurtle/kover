import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:kover/utils/logging.dart';
import 'package:kover/utils/safe_platform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_adapter.dart';

StorageAdapter createStorageAdapter({String? baseDir}) {
  if (baseDir != null) {
    return IoStorageAdapter(baseDir);
  }
  return IoStorageAdapter.lazy(
    () async => Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        StorageAdapter.defaultSubdir,
      ),
    ),
  );
}

/// Native filesystem-backed [StorageAdapter] with atomic temp-file writes and
/// Windows lock-tolerant deletes.
class IoStorageAdapter implements StorageAdapter {
  static final Random _nonceRandom = Random();
  static int _nonceCounter = 0;

  final Future<Directory> Function() _directoryProvider;
  Future<Directory>? _rootFuture;

  IoStorageAdapter(String baseDir)
    : _directoryProvider = (() async => Directory(baseDir));

  IoStorageAdapter.lazy(this._directoryProvider);

  static File _tempSiblingFor(File target) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final salt = _nonceRandom.nextInt(0x7fffffff);
    _nonceCounter = (_nonceCounter + 1) & 0x7fffffff;
    final path = target.path;
    return File('$path.tmp.$micros.$salt.$_nonceCounter');
  }

  Future<Directory> _ensureRoot() async {
    final pending = _rootFuture ??= _initRoot();
    try {
      return await pending;
    } catch (_) {
      if (identical(_rootFuture, pending)) {
        _rootFuture = null;
      }
      rethrow;
    }
  }

  Future<Directory> _initRoot() async {
    final dir = await _directoryProvider();
    await dir.create(recursive: true);
    final epochFile = File(p.join(dir.path, StorageAdapter.epochKey));
    if (await epochFile.exists()) return dir;

    final tempFile = _tempSiblingFor(epochFile);
    try {
      await tempFile.writeAsBytes(createStorageEpochBytes(), flush: true);
      if (!await epochFile.exists()) {
        try {
          await tempFile.rename(epochFile.path);
        } on FileSystemException {
          if (!await epochFile.exists()) rethrow;
        }
      }
    } finally {
      await _cleanupTempFile(tempFile);
    }
    return dir;
  }

  File _fileForKey(Directory root, String normalizedKey) =>
      File(p.joinAll([root.path, ...normalizedKey.split('/')]));

  String _toPosixRelative(Directory root, String entityPath) =>
      p.split(p.relative(entityPath, from: root.path)).join('/');

  @override
  Future<String?> resolveBaseDir() async => (await _ensureRoot()).path;

  @override
  Future<String?> resolveFilePath(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    final root = await _ensureRoot();
    if (normalized == StorageAdapter.epochKey) return null;
    final file = _fileForKey(root, normalized);
    return await file.exists() ? file.path : null;
  }

  @override
  Future<bool> exists(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    final root = await _ensureRoot();
    return _fileForKey(root, normalized).exists();
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    final root = await _ensureRoot();
    final file = _fileForKey(root, normalized);
    try {
      return await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    } on FileSystemException {
      if (!await file.exists()) return null;
      rethrow;
    }
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    final normalized = normalizeStorageKey(key);
    final root = await _ensureRoot();
    final target = _fileForKey(root, normalized);
    await target.parent.create(recursive: true);
    final temp = _tempSiblingFor(target);
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await _renameTempOverTarget(temp, target);
    } catch (_) {
      await _cleanupTempFile(temp);
      rethrow;
    }
  }

  @override
  Future<void> writeStream(String key, Stream<List<int>> chunks) async {
    final normalized = normalizeStorageKey(key);
    final root = await _ensureRoot();
    final target = _fileForKey(root, normalized);
    await target.parent.create(recursive: true);
    final temp = _tempSiblingFor(target);
    IOSink? sink;
    try {
      sink = temp.openWrite();
      await sink.addStream(chunks);
      await sink.flush();
      await sink.close();
      sink = null;
      await _renameTempOverTarget(temp, target);
    } catch (_) {
      await _abortTempWrite(sink, temp);
      rethrow;
    }
  }

  @override
  Future<void> delete(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    final root = await _ensureRoot();
    if (normalized == StorageAdapter.epochKey) return;
    await _deleteFileBestEffort(_fileForKey(root, normalized));
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    final normalizedPrefix = normalizeStoragePrefix(prefix);
    final root = await _ensureRoot();
    final relSegments = normalizedPrefix
        .substring(0, normalizedPrefix.length - 1)
        .split('/');
    final dir = Directory(p.joinAll([root.path, ...relSegments]));
    if (!await dir.exists()) return;
    await _deleteDirectoryBestEffort(dir);
  }

  @override
  Future<void> clear() async {
    final root = await _ensureRoot();
    await for (final entity in root.list(followLinks: false)) {
      if (p.basename(entity.path) == StorageAdapter.epochKey) continue;
      await _deleteEntityBestEffort(entity);
    }
  }

  @override
  Future<List<String>> listKeys({String prefix = ''}) async {
    final normalizedPrefix = prefix.isEmpty
        ? ''
        : normalizeStoragePrefix(prefix);
    final root = await _ensureRoot();
    final scanDir = normalizedPrefix.isEmpty
        ? root
        : Directory(
            p.joinAll([
              root.path,
              ...normalizedPrefix
                  .substring(0, normalizedPrefix.length - 1)
                  .split('/'),
            ]),
          );
    if (!await scanDir.exists()) return <String>[];

    final keys = <String>[];
    await for (final entity in scanDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final rel = _toPosixRelative(root, entity.path);
      if (rel == StorageAdapter.epochKey || hasTempStorageSegment(rel)) {
        continue;
      }
      if (normalizedPrefix.isNotEmpty && !rel.startsWith(normalizedPrefix)) {
        continue;
      }
      keys.add(rel);
    }
    keys.sort();
    return keys;
  }

  @override
  Future<int> totalSizeBytes() async {
    final root = await _ensureRoot();
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = _toPosixRelative(root, entity.path);
      if (rel == StorageAdapter.epochKey || hasTempStorageSegment(rel)) {
        continue;
      }
      try {
        total += await entity.length();
      } on PathNotFoundException {
        continue;
      }
    }
    return total;
  }

  Future<void> _renameTempOverTarget(File temp, File target) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await temp.rename(target.path);
        return;
      } on FileSystemException {
        if (!SafePlatform.isWindows || attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 10 * attempt));
      }
    }
  }

  Future<void> _abortTempWrite(IOSink? sink, File temp) async {
    if (sink != null) {
      try {
        await sink.close();
      } on FileSystemException catch (e) {
        log.debug(
          'failed to close temporary storage sink after write error',
          attributes: {'path': temp.path, 'error': e},
        );
      }
    }
    await _cleanupTempFile(temp);
  }

  Future<void> _cleanupTempFile(File temp) async {
    try {
      await temp.delete();
    } on PathNotFoundException {
      return;
    } on FileSystemException catch (e) {
      if (!await temp.exists()) return;
      log.debug(
        'failed to remove temporary storage file',
        attributes: {'path': temp.path, 'error': e},
      );
    }
  }

  Future<void> _deleteEntityBestEffort(FileSystemEntity entity) async {
    if (entity is Directory) {
      await _deleteDirectoryBestEffort(entity);
    } else if (entity is File) {
      await _deleteFileBestEffort(entity);
    } else {
      try {
        await entity.delete();
      } on PathNotFoundException {
        return;
      }
    }
  }

  Future<void> _deleteFileBestEffort(File file) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await file.delete();
        return;
      } on PathNotFoundException {
        return;
      } on FileSystemException catch (e) {
        if (!await file.exists()) return;
        if (!SafePlatform.isWindows) rethrow;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 10 * attempt));
          continue;
        }
        log.warning(
          'skipping locked storage file during delete',
          attributes: {'path': file.path, 'error': e},
        );
        return;
      }
    }
  }

  Future<void> _deleteDirectoryBestEffort(Directory dir) async {
    try {
      await dir.delete(recursive: true);
      return;
    } on PathNotFoundException {
      return;
    } on FileSystemException {
      if (!await dir.exists()) return;
      if (!SafePlatform.isWindows) rethrow;
    }

    final children = await dir.list(followLinks: false).toList();
    for (final child in children) {
      await _deleteEntityBestEffort(child);
    }

    try {
      await dir.delete();
    } on FileSystemException {
      return;
    }
  }
}
