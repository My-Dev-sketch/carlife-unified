import 'dart:typed_data';

/// Big-endian byte manipulation utilities ported from `ft-app` (`Bytes.kt`).
class CarLifeBytes {
  const CarLifeBytes._();

  static int u16(Uint8List b, int off) =>
      ((b[off] & 0xff) << 8) | (b[off + 1] & 0xff);

  static int u32(Uint8List b, int off) =>
      ((b[off] & 0xff) << 24) |
      ((b[off + 1] & 0xff) << 16) |
      ((b[off + 2] & 0xff) << 8) |
      (b[off + 3] & 0xff);

  static int u64(Uint8List b, int off) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | (b[off + i] & 0xff);
    }
    return v;
  }

  static void putU16(int v, Uint8List b, int off) {
    b[off] = (v >>> 8) & 0xff;
    b[off + 1] = v & 0xff;
  }

  static void putU32(int v, Uint8List b, int off) {
    b[off] = (v >>> 24) & 0xff;
    b[off + 1] = (v >>> 16) & 0xff;
    b[off + 2] = (v >>> 8) & 0xff;
    b[off + 3] = v & 0xff;
  }

  static void putU64(int v, Uint8List b, int off) {
    for (var i = 0; i < 8; i++) {
      b[off + i] = (v >>> (56 - 8 * i)) & 0xff;
    }
  }

  static const String _hexChars = '0123456789ABCDEF';

  static String hex(Uint8List b, {int max = 32}) {
    final n = b.length < max ? b.length : max;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      final v = b[i] & 0xff;
      sb.write(_hexChars[v >>> 4]);
      sb.write(_hexChars[v & 0x0f]);
      if (i < n - 1) sb.write(' ');
    }
    if (b.length > max) {
      sb.write(' …(${b.length})');
    }
    return sb.toString();
  }
}
