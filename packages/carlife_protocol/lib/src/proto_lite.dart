import 'dart:convert';
import 'dart:typed_data';

/// Lightweight zero-codegen Protocol Buffers wire encoder ported from `ft-app` (`ProtoLite.kt`).
class ProtoWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  ProtoWriter varint(int field, int value) {
    _tag(field, 0);
    _writeVarint(BigInt.from(value) & _mask64);
    return this;
  }

  ProtoWriter int32(int field, int value) =>
      varint(field, value & 0xffffffff);

  ProtoWriter int64(int field, int value) => varint(field, value);

  ProtoWriter uint32(int field, int value) =>
      varint(field, value & 0xffffffff);

  ProtoWriter uint64(int field, int value) => varint(field, value);

  ProtoWriter sint32(int field, int value) =>
      varint(field, ((value << 1) ^ (value >> 31)) & 0xffffffff);

  ProtoWriter boolean(int field, bool value) => varint(field, value ? 1 : 0);

  ProtoWriter enumeration(int field, int value) => varint(field, value);

  ProtoWriter string(int field, String value) =>
      bytes(field, Uint8List.fromList(utf8.encode(value)));

  ProtoWriter bytes(int field, Uint8List value) {
    _tag(field, 2);
    _writeVarint(BigInt.from(value.length));
    _out.add(value);
    return this;
  }

  ProtoWriter message(int field, ProtoWriter value) =>
      bytes(field, value.toBytes());

  ProtoWriter fixed64(int field, int value) {
    _tag(field, 1);
    for (var i = 0; i < 8; i++) {
      _out.addByte((value >>> (8 * i)) & 0xff);
    }
    return this;
  }

  ProtoWriter fixed32(int field, int value) {
    _tag(field, 5);
    for (var i = 0; i < 4; i++) {
      _out.addByte((value >>> (8 * i)) & 0xff);
    }
    return this;
  }

  ProtoWriter packedInts(int field, List<int> values) {
    final tmp = BytesBuilder(copy: false);
    for (final v in values) {
      var x = BigInt.from(v) & _mask32;
      while (x > _sevenBits) {
        tmp.addByte(((x & _sevenBits) | _highBit).toInt());
        x = x >> 7;
      }
      tmp.addByte(x.toInt());
    }
    return bytes(field, tmp.toBytes());
  }

  Uint8List toBytes() => _out.toBytes();

  void _tag(int field, int wire) =>
      _writeVarint(BigInt.from((field << 3) | wire));

  void _writeVarint(BigInt v) {
    var x = v & _mask64;
    while (x > _sevenBits) {
      _out.addByte(((x & _sevenBits) | _highBit).toInt());
      x = x >> 7;
    }
    _out.addByte(x.toInt());
  }

  static final BigInt _sevenBits = BigInt.from(0x7f);
  static final BigInt _highBit = BigInt.from(0x80);
  static final BigInt _mask32 = BigInt.from(0xffffffff);
  static final BigInt _mask64 =
      (BigInt.one << 64) - BigInt.one;
}

/// Lightweight zero-codegen Protocol Buffers wire decoder ported from `ft-app` (`ProtoLite.kt`).
class ProtoReader {
  final Uint8List data;
  late final Map<int, List<Object>> fields;

  ProtoReader(this.data) {
    final m = <int, List<Object>>{};
    var pos = 0;
    try {
      while (pos < data.length) {
        final tagPair = _readVarint(pos);
        final tag = tagPair.$1;
        pos = tagPair.$2;
        final field = (tag >> 3).toInt();
        final wire = (tag & BigInt.from(7)).toInt();
        switch (wire) {
          case 0:
            final valPair = _readVarint(pos);
            pos = valPair.$2;
            m.putIfAbsent(field, () => <Object>[]).add(valPair.$1.toSigned(64).toInt());
          case 1:
            if (pos + 8 > data.length) {
              pos = data.length;
              break;
            }
            var v = 0;
            for (var i = 0; i < 8; i++) {
              v |= (data[pos + i] & 0xff) << (8 * i);
            }
            pos += 8;
            m.putIfAbsent(field, () => <Object>[]).add(v);
          case 2:
            final lenPair = _readVarint(pos);
            pos = lenPair.$2;
            final n = lenPair.$1.toInt();
            if (n < 0 || pos + n > data.length) {
              pos = data.length;
              break;
            }
            m
                .putIfAbsent(field, () => <Object>[])
                .add(Uint8List.sublistView(data, pos, pos + n));
            pos += n;
          case 5:
            if (pos + 4 > data.length) {
              pos = data.length;
              break;
            }
            var v = 0;
            for (var i = 0; i < 4; i++) {
              v |= (data[pos + i] & 0xff) << (8 * i);
            }
            pos += 4;
            m.putIfAbsent(field, () => <Object>[]).add(v);
          default:
            pos = data.length;
        }
      }
    } catch (_) {
      // Gracefully stop parsing on truncated or malformed trailing bytes
    }
    fields = m;
  }

  (BigInt, int) _readVarint(int start) {
    var r = BigInt.zero;
    var shift = 0;
    var pos = start;
    while (pos < data.length && shift < 64) {
      final b = data[pos++] & 0xff;
      r |= BigInt.from(b & 0x7f) << shift;
      if ((b & 0x80) == 0) {
        return (r, pos);
      }
      shift += 7;
    }
    throw const FormatException('Invalid varint');
  }

  bool has(int field) => fields.containsKey(field);

  int int64Val(int field, [int def = 0]) {
    final v = fields[field]?.firstOrNull;
    if (v is int) return v;
    return def;
  }

  int intVal(int field, [int def = 0]) {
    final v = fields[field]?.firstOrNull;
    if (v is int) return v.toSigned(32);
    return def;
  }

  bool boolVal(int field, [bool def = false]) =>
      int64Val(field, def ? 1 : 0) != 0;

  Uint8List? bytesVal(int field) {
    final v = fields[field]?.firstOrNull;
    if (v is Uint8List) return v;
    return null;
  }

  String? stringVal(int field) {
    final b = bytesVal(field);
    if (b == null) return null;
    return utf8.decode(b, allowMalformed: true);
  }

  ProtoReader? message(int field) {
    final b = bytesVal(field);
    return b != null ? ProtoReader(b) : null;
  }

  List<ProtoReader> messages(int field) =>
      fields[field]
          ?.whereType<Uint8List>()
          .map(ProtoReader.new)
          .toList() ??
      const [];

  List<int> ints(int field) =>
      fields[field]?.whereType<int>().map((e) => e.toSigned(32)).toList() ??
      const [];
}
