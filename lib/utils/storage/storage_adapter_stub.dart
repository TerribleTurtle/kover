import 'dart:async';
import 'dart:typed_data';

import 'storage_adapter.dart';

StorageAdapter createStorageAdapter({String? baseDir}) =>
    MemoryStorageAdapter();

/// Pure microtask-based in-memory [StorageAdapter] for tests and fallback use.
class MemoryStorageAdapter implements StorageAdapter {
  final Map<String, Uint8List> _entries = <String, Uint8List>{};
  bool _initialized = false;

  void _ensureInitialized() {
    if (_initialized) return;
    _entries.putIfAbsent(StorageAdapter.epochKey, createStorageEpochBytes);
    _initialized = true;
  }

  @override
  Future<String?> resolveBaseDir() async {
    _ensureInitialized();
    return null;
  }

  @override
  Future<String?> resolveFilePath(String key) async {
    normalizeStorageKey(key, allowEpoch: true);
    _ensureInitialized();
    return null;
  }

  @override
  Future<bool> exists(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    _ensureInitialized();
    return _entries.containsKey(normalized);
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    _ensureInitialized();
    final stored = _entries[normalized];
    return stored == null ? null : Uint8List.fromList(stored);
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    final normalized = normalizeStorageKey(key);
    _ensureInitialized();
    _entries[normalized] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeStream(String key, Stream<List<int>> chunks) async {
    final normalized = normalizeStorageKey(key);
    _ensureInitialized();
    final builder = BytesBuilder();
    await for (final chunk in chunks) {
      builder.add(chunk);
    }
    _entries[normalized] = builder.takeBytes();
  }

  @override
  Future<void> delete(String key) async {
    final normalized = normalizeStorageKey(key, allowEpoch: true);
    _ensureInitialized();
    if (normalized == StorageAdapter.epochKey) return;
    _entries.remove(normalized);
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    final normalizedPrefix = normalizeStoragePrefix(prefix);
    _ensureInitialized();
    _entries.removeWhere(
      (key, _) =>
          key != StorageAdapter.epochKey && key.startsWith(normalizedPrefix),
    );
  }

  @override
  Future<void> clear() async {
    _ensureInitialized();
    final epoch = _entries[StorageAdapter.epochKey];
    _entries.clear();
    if (epoch != null) {
      _entries[StorageAdapter.epochKey] = epoch;
    }
  }

  @override
  Future<List<String>> listKeys({String prefix = ''}) async {
    final normalizedPrefix = prefix.isEmpty
        ? ''
        : normalizeStoragePrefix(prefix);
    _ensureInitialized();
    final keys = [
      for (final key in _entries.keys)
        if (key != StorageAdapter.epochKey &&
            !hasTempStorageSegment(key) &&
            (normalizedPrefix.isEmpty || key.startsWith(normalizedPrefix)))
          key,
    ]..sort();
    return keys;
  }

  @override
  Future<int> totalSizeBytes() async {
    _ensureInitialized();
    var total = 0;
    for (final entry in _entries.entries) {
      if (entry.key == StorageAdapter.epochKey ||
          hasTempStorageSegment(entry.key)) {
        continue;
      }
      total += entry.value.length;
    }
    return total;
  }
}
