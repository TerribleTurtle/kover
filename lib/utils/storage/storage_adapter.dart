import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'storage_adapter_stub.dart'
    if (dart.library.js_interop) 'storage_adapter_web.dart'
    if (dart.library.io) 'storage_adapter_io.dart'
    as platform;

export 'storage_adapter_stub.dart' show MemoryStorageAdapter;

/// Cross-platform key-addressed binary storage for downloaded reader assets.
abstract class StorageAdapter {
  static const epochKey = '.storage_epoch';
  static const defaultSubdir = 'storage';

  factory StorageAdapter({String? baseDir}) =>
      platform.createStorageAdapter(baseDir: baseDir);

  /// Initializes storage, stamps [epochKey] if absent, and returns the native
  /// root directory path on IO or `null` on Web and in-memory adapters.
  Future<String?> resolveBaseDir();

  /// Returns the native OS file path when [key] exists on disk, or `null` when
  /// missing, non-content, or backed by Web/in-memory storage.
  Future<String?> resolveFilePath(String key);

  /// Returns whether [key] exists in storage.
  Future<bool> exists(String key);

  /// Reads the bytes stored at [key], or returns `null` when missing.
  Future<Uint8List?> readBytes(String key);

  /// Atomically writes [bytes] to [key], replacing any existing entry.
  Future<void> writeBytes(String key, Uint8List bytes);

  /// Atomically streams [chunks] into [key], leaving prior state untouched if
  /// the stream fails mid-transfer.
  Future<void> writeStream(String key, Stream<List<int>> chunks);

  /// Deletes [key] if present. Missing keys and [epochKey] are no-ops.
  Future<void> delete(String key);

  /// Deletes all entries strictly under the [prefix] directory boundary while
  /// preserving [epochKey].
  Future<void> deletePrefix(String prefix);

  /// Deletes all stored content entries while preserving [epochKey].
  Future<void> clear();

  /// Lists sorted POSIX-style relative content keys matching [prefix],
  /// excluding [epochKey] and temporary staging files.
  Future<List<String>> listKeys({String prefix = ''});

  /// Returns the total byte size of stored content entries, excluding
  /// [epochKey] and temporary staging files.
  Future<int> totalSizeBytes();
}

/// Normalizes and validates a storage file [key] using POSIX `'/'` separators.
String normalizeStorageKey(String key, {bool allowEpoch = false}) {
  if (key.contains('\x00')) {
    throw ArgumentError.value(key, 'key', 'Null byte in storage key');
  }
  var normalized = key.replaceAll(r'\', '/');
  if (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  if (normalized.isEmpty || normalized.endsWith('/')) {
    throw ArgumentError.value(key, 'key', 'Invalid storage key');
  }
  if (normalized == StorageAdapter.epochKey) {
    if (!allowEpoch) {
      throw ArgumentError.value(key, 'key', 'Reserved storage epoch key');
    }
    return StorageAdapter.epochKey;
  }
  for (final segment in normalized.split('/')) {
    if (_isInvalidSegment(segment)) {
      throw ArgumentError.value(key, 'key', 'Invalid storage key segment');
    }
  }
  return normalized;
}

/// Normalizes a non-empty storage directory [prefix] to end with `'/'`.
String normalizeStoragePrefix(String prefix) {
  if (prefix.contains('\x00')) {
    throw ArgumentError.value(prefix, 'prefix', 'Null byte in storage prefix');
  }
  var normalized = prefix.replaceAll(r'\', '/');
  if (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  if (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.isEmpty) {
    throw ArgumentError.value(prefix, 'prefix', 'Empty storage prefix');
  }
  for (final segment in normalized.split('/')) {
    if (_isInvalidSegment(segment)) {
      throw ArgumentError.value(
        prefix,
        'prefix',
        'Invalid storage prefix segment',
      );
    }
  }
  return '$normalized/';
}

/// Returns whether [key] contains a temporary `.tmp.` path segment.
bool hasTempStorageSegment(String key) =>
    key.split('/').any((segment) => segment.contains('.tmp.'));

/// Generates fresh random ASCII hex bytes for stamping [StorageAdapter.epochKey].
Uint8List createStorageEpochBytes() {
  Random rng;
  try {
    rng = Random.secure();
  } on UnsupportedError {
    rng = Random();
  }
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return Uint8List.fromList(ascii.encode(buffer.toString()));
}

bool _isInvalidSegment(String segment) =>
    segment.isEmpty ||
    segment == '.' ||
    segment == '..' ||
    segment == StorageAdapter.epochKey ||
    segment.contains(':') ||
    segment.contains('.tmp.');
