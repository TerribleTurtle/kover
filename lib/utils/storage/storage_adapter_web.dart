import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'storage_adapter.dart';

StorageAdapter createStorageAdapter({String? baseDir}) => WebStorageAdapter();

@JS('indexedDB')
external _IDBFactory? get _indexedDB;

@JS('IDBKeyRange')
extension type _IDBKeyRange._(JSObject _) implements JSObject {
  external static _IDBKeyRange bound(
    JSAny? lower,
    JSAny? upper, [
    bool lowerOpen,
    bool upperOpen,
  ]);
}

extension type _DOMException._(JSObject _) implements JSObject {
  external String get name;
  external String get message;
}

extension type _DOMStringList._(JSObject _) implements JSObject {
  external bool contains(String name);
}

extension type _IDBFactory._(JSObject _) implements JSObject {
  external _IDBOpenDBRequest open(String name, int version);
}

extension type _IDBRequest<T extends JSAny?>._(JSObject _) implements JSObject {
  external T get result;
  external _DOMException? get error;
  external set onsuccess(JSFunction? value);
  external set onerror(JSFunction? value);
}

extension type _IDBOpenDBRequest._(JSObject _) implements JSObject {
  external _IDBDatabase get result;
  external _DOMException? get error;
  external set onsuccess(JSFunction? value);
  external set onerror(JSFunction? value);
  external set onupgradeneeded(JSFunction? value);
  external set onblocked(JSFunction? value);
}

extension type _IDBDatabase._(JSObject _) implements JSObject {
  external _DOMStringList get objectStoreNames;
  external _IDBObjectStore createObjectStore(String name);
  external _IDBTransaction transaction(JSAny storeNames, String mode);
  external void close();
  external set onversionchange(JSFunction? value);
}

extension type _IDBTransaction._(JSObject _) implements JSObject {
  external _DOMException? get error;
  external _IDBObjectStore objectStore(String name);
  external void abort();
  external set oncomplete(JSFunction? value);
  external set onerror(JSFunction? value);
  external set onabort(JSFunction? value);
}

extension type _IDBObjectStore._(JSObject _) implements JSObject {
  external _IDBRequest<JSAny?> get(JSAny query);
  external _IDBRequest<JSNumber> count(JSAny query);
  external _IDBRequest<JSAny?> put(JSAny value, JSAny key);
  external _IDBRequest<JSAny?> delete(JSAny query);
  external _IDBRequest<JSAny?> clear();
  external _IDBRequest<JSArray<JSString>> getAllKeys([JSAny? query]);
  external _IDBRequest<_IDBCursorWithValue?> openCursor();
}

extension type _IDBCursorWithValue._(JSObject _) implements JSObject {
  external JSString get key;
  external JSAny? get value;

  @JS('continue')
  external void continue_();
}

/// IndexedDB-backed [StorageAdapter] for Web (`dart2js` and `dart2wasm`).
class WebStorageAdapter implements StorageAdapter {
  static const _dbName = 'kover_storage';
  static const _dbVersion = 1;
  static const _storeName = 'files';

  Future<_IDBDatabase>? _dbFuture;

  Future<_IDBDatabase> _ensureDb() async {
    final pending = _dbFuture ??= _openAndInitDb();
    try {
      return await pending;
    } catch (_) {
      if (identical(_dbFuture, pending)) {
        _dbFuture = null;
      }
      rethrow;
    }
  }

  Future<_IDBDatabase> _openAndInitDb() async {
    final factory = _indexedDB;
    if (factory == null) {
      throw StateError('IndexedDB is unavailable in this browser context');
    }

    final openCompleter = Completer<_IDBDatabase>();
    final req = factory.open(_dbName, _dbVersion);
    req.onupgradeneeded = ((JSObject _) {
      try {
        final db = req.result;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }
      } on Object catch (error, stackTrace) {
        if (!openCompleter.isCompleted) {
          openCompleter.completeError(error, stackTrace);
        }
      }
    }).toJS;
    req.onsuccess = ((JSObject _) {
      try {
        final db = req.result;
        db.onversionchange = ((JSObject _) {
          db.close();
          _dbFuture = null;
        }).toJS;
        if (!openCompleter.isCompleted) {
          openCompleter.complete(db);
        }
      } on Object catch (error, stackTrace) {
        if (!openCompleter.isCompleted) {
          openCompleter.completeError(error, stackTrace);
        }
      }
    }).toJS;
    req.onerror = ((JSObject _) {
      if (!openCompleter.isCompleted) {
        openCompleter.completeError(_describeError(req.error, 'open'));
      }
    }).toJS;
    req.onblocked = ((JSObject _) {
      if (!openCompleter.isCompleted) {
        openCompleter.completeError(
          StateError('IndexedDB open blocked by another connection'),
        );
      }
    }).toJS;

    final db = await openCompleter.future;
    try {
      await _stampEpochIfAbsent(db);
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  Future<void> _stampEpochIfAbsent(_IDBDatabase db) =>
      _runDbTransaction(db, 'readwrite', (store, guard) {
        final getReq = store.get(StorageAdapter.epochKey.toJS);
        getReq.onsuccess = guard(() {
          final raw = getReq.result;
          if (raw == null || raw.isUndefinedOrNull) {
            store.put(
              createStorageEpochBytes().toJS,
              StorageAdapter.epochKey.toJS,
            );
          } else {
            _byteLengthFromJs(raw);
          }
        });
      });

  static _IDBKeyRange _prefixKeyRange(String normalizedPrefix) {
    final stem = normalizedPrefix.substring(0, normalizedPrefix.length - 1);
    final upperBound = '${stem}0';
    return _IDBKeyRange.bound(
      normalizedPrefix.toJS,
      upperBound.toJS,
      false,
      true,
    );
  }

  static StateError _describeError(_DOMException? err, String action) =>
      err == null
      ? StateError('IndexedDB $action failed')
      : StateError('IndexedDB $action failed (${err.name}): ${err.message}');

  static Future<T> _awaitRequest<T extends JSAny?>(_IDBRequest<T> req) {
    final completer = Completer<T>();
    req.onsuccess = ((JSObject _) {
      try {
        if (!completer.isCompleted) {
          completer.complete(req.result);
        }
      } on Object catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    }).toJS;
    req.onerror = ((JSObject _) {
      if (!completer.isCompleted) {
        completer.completeError(_describeError(req.error, 'request'));
      }
    }).toJS;
    return completer.future;
  }

  Future<void> _runTransaction(
    String mode,
    void Function(
      _IDBObjectStore store,
      JSFunction Function(void Function() body) guard,
    )
    setup,
  ) async {
    final db = await _ensureDb();
    await _runDbTransaction(db, mode, setup);
  }

  static Future<void> _runDbTransaction(
    _IDBDatabase db,
    String mode,
    void Function(
      _IDBObjectStore store,
      JSFunction Function(void Function() body) guard,
    )
    setup,
  ) {
    final tx = db.transaction(_storeName.toJS, mode);
    final completer = Completer<void>();
    (Object, StackTrace)? callbackFailure;

    void abortWithError(Object error, StackTrace stackTrace) {
      callbackFailure ??= (error, stackTrace);
      try {
        tx.abort();
      } on Object {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    }

    void failFromDom(_DOMException? domError, String action) {
      if (completer.isCompleted) return;
      if (callbackFailure case (final err, final st)) {
        completer.completeError(err, st);
      } else {
        completer.completeError(_describeError(domError, action));
      }
    }

    tx.oncomplete = ((JSObject _) {
      if (completer.isCompleted) return;
      if (callbackFailure case (final err, final st)) {
        completer.completeError(err, st);
      } else {
        completer.complete();
      }
    }).toJS;
    tx.onerror = ((JSObject _) => failFromDom(tx.error, 'transaction')).toJS;
    tx.onabort = ((JSObject _) => failFromDom(
      tx.error,
      'transaction abort',
    )).toJS;

    JSFunction guard(void Function() body) => ((JSObject _) {
      try {
        body();
      } on Object catch (error, stackTrace) {
        abortWithError(error, stackTrace);
      }
    }).toJS;

    try {
      setup(tx.objectStore(_storeName), guard);
    } on Object catch (error, stackTrace) {
      abortWithError(error, stackTrace);
    }

    return completer.future;
  }

  static Uint8List? _copyBytesFromJs(JSAny? raw) {
    if (raw == null || raw.isUndefinedOrNull) return null;
    if (raw.isA<JSUint8Array>()) {
      return Uint8List.fromList((raw as JSUint8Array).toDart);
    }
    if (raw.isA<JSArrayBuffer>()) {
      return Uint8List.fromList((raw as JSArrayBuffer).toDart.asUint8List());
    }
    throw StateError('Unexpected IndexedDB value type for stored bytes');
  }

  static int _byteLengthFromJs(JSAny? raw) {
    if (raw == null || raw.isUndefinedOrNull) return 0;
    if (raw.isA<JSUint8Array>()) {
      return (raw as JSUint8Array).toDart.lengthInBytes;
    }
    if (raw.isA<JSArrayBuffer>()) {
      return (raw as JSArrayBuffer).toDart.lengthInBytes;
    }
    throw StateError('Unexpected IndexedDB value type for stored bytes');
  }

  @override
  Future<String?> resolveBaseDir() async {
    await _ensureDb();
    return null;
  }

  @override
  Future<String?> resolveFilePath(String key) async {
    normalizeStorageKey(key, allowEpoch: true);
    await _ensureDb();
    return null;
  }

  @override
  Future<bool> exists(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    final db = await _ensureDb();
    final tx = db.transaction(_storeName.toJS, 'readonly');
    final count = await _awaitRequest(
      tx.objectStore(_storeName).count(normalized.toJS),
    );
    return count.toDartInt > 0;
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    final db = await _ensureDb();
    final tx = db.transaction(_storeName.toJS, 'readonly');
    final raw = await _awaitRequest(
      tx.objectStore(_storeName).get(normalized.toJS),
    );
    return _copyBytesFromJs(raw);
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    final normalized = normalizeStorageKey(key);
    final payload = Uint8List.fromList(bytes).toJS;
    await _runTransaction('readwrite', (store, _) {
      store.put(payload, normalized.toJS);
    });
  }

  @override
  Future<void> writeStream(String key, Stream<List<int>> chunks) async {
    final normalized = normalizeStorageKey(key);
    final builder = BytesBuilder();
    await for (final chunk in chunks) {
      builder.add(chunk);
    }
    final payload = builder.takeBytes().toJS;
    await _runTransaction('readwrite', (store, _) {
      store.put(payload, normalized.toJS);
    });
  }

  @override
  Future<void> delete(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    await _ensureDb();
    if (normalized == StorageAdapter.epochKey) return;
    await _runTransaction('readwrite', (store, _) {
      store.delete(normalized.toJS);
    });
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    final normalizedPrefix = normalizeStoragePrefix(prefix);
    final range = _prefixKeyRange(normalizedPrefix);
    await _runTransaction('readwrite', (store, _) {
      store.delete(range);
    });
  }

  @override
  Future<void> clear() => _runTransaction('readwrite', (store, guard) {
    final getReq = store.get(StorageAdapter.epochKey.toJS);
    getReq.onsuccess = guard(() {
      final epoch =
          _copyBytesFromJs(getReq.result) ?? createStorageEpochBytes();
      store.clear();
      store.put(epoch.toJS, StorageAdapter.epochKey.toJS);
    });
  });

  @override
  Future<List<String>> listKeys({String prefix = ''}) async {
    final normalizedPrefix = prefix.isEmpty
        ? ''
        : normalizeStoragePrefix(prefix);
    final db = await _ensureDb();
    final tx = db.transaction(_storeName.toJS, 'readonly');
    final store = tx.objectStore(_storeName);
    final req = normalizedPrefix.isEmpty
        ? store.getAllKeys()
        : store.getAllKeys(_prefixKeyRange(normalizedPrefix));
    final jsKeys = await _awaitRequest(req);
    final keys = <String>[];
    for (final item in jsKeys.toDart) {
      final key = item.toDart;
      if (key == StorageAdapter.epochKey || hasTempStorageSegment(key)) {
        continue;
      }
      keys.add(key);
    }
    keys.sort();
    return keys;
  }

  @override
  Future<int> totalSizeBytes() async {
    var total = 0;
    await _runTransaction('readonly', (store, guard) {
      final cursorReq = store.openCursor();
      cursorReq.onsuccess = guard(() {
        final cursor = cursorReq.result;
        if (cursor == null || cursor.isUndefinedOrNull) return;
        final key = cursor.key.toDart;
        if (key != StorageAdapter.epochKey && !hasTempStorageSegment(key)) {
          total += _byteLengthFromJs(cursor.value);
        }
        cursor.continue_();
      });
    });
    return total;
  }
}
