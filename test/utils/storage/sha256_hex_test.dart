import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kover/utils/storage/sha256_hex.dart';

void main() {
  test('hashes empty input and standard abc vector', () {
    const emptyDigest =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    expect(sha256Hex(''), emptyDigest);
    expect(sha256HexBytes(const <int>[]), emptyDigest);
    expect(
      sha256Hex('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test(
    'hashes 55-byte, 56-byte, 64-byte, and multi-block padding boundaries',
    () {
      expect(
        sha256Hex('a' * 55),
        '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
      );
      expect(
        sha256Hex('a' * 56),
        'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
      );
      expect(
        sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      expect(
        sha256Hex('a' * 64),
        'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
      );
      expect(
        sha256Hex(
          'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno'
          'ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
        ),
        'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
      );
    },
  );

  test('hashes one million repeated a bytes matching NIST vector', () {
    final millionA = Uint8List(1000000)..fillRange(0, 1000000, 0x61);

    expect(
      sha256HexBytes(millionA),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });

  test('hashes multi-byte utf-8 epub paths and offset typed-data views', () {
    const epubPath =
        'OEBPS/\u30c6\u30ad\u30b9\u30c8/\u7b2c1\u7ae0_caf\u00e9.xhtml';
    const expected =
        '8cca129269eaf3c9af47646352ab1b6e7821d8d46179465463d5617f9905109d';
    final encoded = utf8.encode(epubPath);
    final padded = Uint8List(encoded.length + 6)
      ..setRange(3, 3 + encoded.length, encoded);
    final view = Uint8List.sublistView(padded, 3, 3 + encoded.length);

    expect(sha256Hex(epubPath), expected);
    expect(sha256HexBytes(view), expected);
    expect(
      sha256HexBytes(const [0x161, 0x262, 0x363]),
      sha256Hex('abc'),
    );
  });
}
