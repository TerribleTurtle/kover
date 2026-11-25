import 'dart:convert';
import 'dart:typed_data';

const _initialState = <int>[
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
];

const _roundConstants = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

/// Computes the 64-character lowercase hex SHA-256 digest of UTF-8 [input].
String sha256Hex(String input) => sha256HexBytes(utf8.encode(input));

/// Computes the 64-character lowercase hex SHA-256 digest of [bytes].
String sha256HexBytes(List<int> bytes) {
  final state = Uint32List.fromList(_initialState);
  final w = Uint32List(64);
  final len = bytes.length;
  final fullEnd = len - (len % 64);

  for (var offset = 0; offset < fullEnd; offset += 64) {
    _compressBlock(state, w, bytes, offset);
  }

  final tailLen = len - fullEnd;
  final tailSize = tailLen < 56 ? 64 : 128;
  final tail = Uint8List(tailSize);
  for (var i = 0; i < tailLen; i++) {
    tail[i] = bytes[fullEnd + i] & 0xff;
  }
  tail[tailLen] = 0x80;

  final high = (len >>> 29) & 0xffffffff;
  final low = ((len & 0x1fffffff) << 3) & 0xffffffff;
  final tailData = ByteData.sublistView(tail);
  tailData.setUint32(tailSize - 8, high);
  tailData.setUint32(tailSize - 4, low);

  _compressBlock(state, w, tail, 0);
  if (tailSize == 128) {
    _compressBlock(state, w, tail, 64);
  }

  final out = StringBuffer();
  for (var i = 0; i < 8; i++) {
    out.write(state[i].toRadixString(16).padLeft(8, '0'));
  }
  return out.toString();
}

int _rotr32(int x, int n) =>
    ((x >>> n) | ((x & ((1 << n) - 1)) << (32 - n))) & 0xffffffff;

void _expandSchedule(Uint32List w, List<int> block, int offset) {
  for (var i = 0; i < 16; i++) {
    final j = offset + (i << 2);
    final b0 = block[j] & 0xff;
    final b1 = block[j + 1] & 0xff;
    final b2 = block[j + 2] & 0xff;
    final b3 = block[j + 3] & 0xff;
    w[i] = ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) & 0xffffffff;
  }

  for (var i = 16; i < 64; i++) {
    final prev15 = w[i - 15];
    final prev2 = w[i - 2];
    final s0 = _rotr32(prev15, 7) ^ _rotr32(prev15, 18) ^ (prev15 >>> 3);
    final s1 = _rotr32(prev2, 17) ^ _rotr32(prev2, 19) ^ (prev2 >>> 10);
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
  }
}

void _compressBlock(
  Uint32List state,
  Uint32List w,
  List<int> block,
  int offset,
) {
  _expandSchedule(w, block, offset);

  var a = state[0];
  var b = state[1];
  var c = state[2];
  var d = state[3];
  var e = state[4];
  var f = state[5];
  var g = state[6];
  var h = state[7];

  for (var i = 0; i < 64; i++) {
    final sum1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
    final ch = (e & f) ^ ((e ^ 0xffffffff) & g);
    final temp1 = (h + sum1 + ch + _roundConstants[i] + w[i]) & 0xffffffff;
    final sum0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final temp2 = (sum0 + maj) & 0xffffffff;

    h = g;
    g = f;
    f = e;
    e = (d + temp1) & 0xffffffff;
    d = c;
    c = b;
    b = a;
    a = (temp1 + temp2) & 0xffffffff;
  }

  state[0] = (state[0] + a) & 0xffffffff;
  state[1] = (state[1] + b) & 0xffffffff;
  state[2] = (state[2] + c) & 0xffffffff;
  state[3] = (state[3] + d) & 0xffffffff;
  state[4] = (state[4] + e) & 0xffffffff;
  state[5] = (state[5] + f) & 0xffffffff;
  state[6] = (state[6] + g) & 0xffffffff;
  state[7] = (state[7] + h) & 0xffffffff;
}
