import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

/// Baidu CarLife RSA-2048 + AES-128-ECB content encryption engine ported from `ft-app` (`CarLifeCrypto.kt`).
class CarLifeCrypto {
  bool started = false;
  Uint8List? _aesKeyBytes;
  String? _aesKeyString;
  bool incoming = false;
  bool outgoing = false;

  bool get active => outgoing;
  String? get sessionKey => _aesKeyString;

  void reset() {
    started = false;
    _aesKeyBytes = null;
    _aesKeyString = null;
    incoming = false;
    outgoing = false;
  }

  /// Parses an X.509 SubjectPublicKeyInfo (SPKI) Base64 RSA public key from the head unit,
  /// generates a 16-character alphanumeric AES-128 key, wraps it using RSA/ECB/PKCS1Padding,
  /// and returns the Base64-encoded ciphertext for `CMD_MD_AES_KEY_SEND_REQUEST`.
  String? aesKeyRequest(String rsaPublicKeyBase64) {
    try {
      final clean = rsaPublicKeyBase64.replaceAll(RegExp(r'\s+'), '');
      final spki = base64Decode(clean);
      final pubKey = _parseSpkiRsaPublicKey(spki);

      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      final rnd = Random.secure();
      final keyStr = String.fromCharCodes(
        List.generate(
          16,
          (_) => alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
        ),
      );
      final keyBytes = Uint8List.fromList(utf8.encode(keyStr));

      final encryptor = PKCS1Encoding(RSAEngine())
        ..init(
          true,
          PublicKeyParameter<RSAPublicKey>(pubKey),
        );
      final wrapped = encryptor.process(keyBytes);

      _aesKeyString = keyStr;
      _aesKeyBytes = keyBytes;
      return base64Encode(wrapped);
    } catch (_) {
      return null;
    }
  }

  /// Directly sets a 16-character AES-128 session key (used on receiver/simulator or tests).
  void setRawSessionKey(String key16) {
    final bytes = Uint8List.fromList(utf8.encode(key16));
    if (bytes.length != 16) {
      throw ArgumentError('AES-128 session key must be 16 bytes');
    }
    _aesKeyString = key16;
    _aesKeyBytes = bytes;
  }

  void armIncoming() {
    incoming = true;
  }

  void enableOutgoing() {
    outgoing = true;
  }

  Uint8List encryptOut(Uint8List payload) {
    final k = _aesKeyBytes;
    if (k == null || !outgoing || payload.isEmpty) return payload;
    return _aesEcbPkcs7Encrypt(k, payload);
  }

  Uint8List decryptIn(Uint8List payload) {
    final k = _aesKeyBytes;
    if (k == null || !incoming || payload.isEmpty) return payload;
    try {
      return _aesEcbPkcs7Decrypt(k, payload);
    } catch (_) {
      return payload;
    }
  }

  static RSAPublicKey _parseSpkiRsaPublicKey(Uint8List spkiBytes) {
    final topParser = ASN1Parser(spkiBytes);
    final topSeq = topParser.nextObject() as ASN1Sequence;
    if (topSeq.elements.length >= 2 && topSeq.elements[1] is ASN1BitString) {
      final bitString = topSeq.elements[1] as ASN1BitString;
      final keyParser = ASN1Parser(Uint8List.fromList(bitString.contentBytes()));
      final keySeq = keyParser.nextObject() as ASN1Sequence;
      final modulus = (keySeq.elements[0] as ASN1Integer).valueAsBigInteger;
      final exponent = (keySeq.elements[1] as ASN1Integer).valueAsBigInteger;
      return RSAPublicKey(modulus, exponent);
    }
    // Fallback if raw RSAPublicKey ASN.1 sequence
    final modulus = (topSeq.elements[0] as ASN1Integer).valueAsBigInteger;
    final exponent = (topSeq.elements[1] as ASN1Integer).valueAsBigInteger;
    return RSAPublicKey(modulus, exponent);
  }

  static Uint8List _aesEcbPkcs7Encrypt(Uint8List key, Uint8List input) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      ECBBlockCipher(AESEngine()),
    )..init(
        true,
        PaddedBlockCipherParameters<KeyParameter, CipherParameters>(
          KeyParameter(key),
          null,
        ),
      );
    return cipher.process(input);
  }

  static Uint8List _aesEcbPkcs7Decrypt(Uint8List key, Uint8List input) {
    if (input.length % 16 != 0) return input;
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      ECBBlockCipher(AESEngine()),
    )..init(
        false,
        PaddedBlockCipherParameters<KeyParameter, CipherParameters>(
          KeyParameter(key),
          null,
        ),
      );
    return cipher.process(input);
  }
}
