import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models/data.dart';

typedef PasswordPrompt = Future<String?> Function();

class OperationCancelled implements Exception {
  const OperationCancelled();
  @override
  String toString() => 'Дію скасовано.';
}

/// Portable, authenticated backups. Passwords are never saved in app state.
class BackupCodec {
  static const format = 'AMID_OFFGRID_ENCRYPTED_BACKUP';
  static const maxPlainBytes = 32 * 1024 * 1024;
  static const iterations = 210000;
  static final _cipher = AesGcm.with256bits();
  static final _aad = utf8.encode('$format/v1');

  static bool isEncrypted(Json value) => value['format'] == format;

  static Future<SecretKey> _key(String password, List<int> salt, int rounds) {
    if (password.length < 10 || password.length > 1024) {
      throw const FormatException(
        'Пароль має містити від 10 до 1024 символів.',
      );
    }
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: rounds,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  static Future<Json> encrypt(Json backup, String password) =>
      compute(_encrypt, (backup, password), debugLabel: 'backup-encrypt');

  static Future<Json> _encrypt((Json, String) input) async {
    final (backup, password) = input;
    final plain = utf8.encode(jsonEncode(backup));
    if (plain.length > maxPlainBytes) {
      throw const FormatException('Ліміт текстової резервної копії — 32 MiB.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _key(password, salt, iterations);
    final box = await _cipher.encrypt(plain, secretKey: key, aad: _aad);
    return {
      'format': format,
      'version': 1,
      'cipher': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
  }

  static Future<Json> decrypt(Json value, String password) =>
      compute(_decrypt, (value, password), debugLabel: 'backup-decrypt');

  static Future<Json> _decrypt((Json, String) input) async {
    final (value, password) = input;
    final rounds = value['iterations'];
    if (!isEncrypted(value) ||
        value['version'] != 1 ||
        value['cipher'] != 'AES-256-GCM' ||
        value['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        rounds is! int ||
        rounds < 100000 ||
        rounds > 1000000) {
      throw const FormatException('Непідтримуваний формат захищеної копії.');
    }
    List<int> bytes(String field, int maximum, {int? exact}) {
      final text = value[field];
      if (text is! String || text.length > ((maximum + 2) ~/ 3) * 4) {
        throw FormatException('Некоректне поле резервної копії: $field');
      }
      final result = base64Decode(text);
      if (result.length > maximum ||
          (exact != null && result.length != exact)) {
        throw FormatException('Некоректне поле резервної копії: $field');
      }
      return result;
    }

    final salt = bytes('salt', 16, exact: 16);
    final nonce = bytes('nonce', 12, exact: 12);
    final mac = bytes('mac', 16, exact: 16);
    final ciphertext = bytes('ciphertext', maxPlainBytes);
    final key = await _key(password, salt, rounds);
    try {
      final plain = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: _aad,
      );
      return decodeObject(utf8.decode(plain));
    } on SecretBoxAuthenticationError {
      throw const FormatException('Неправильний пароль або пошкоджена копія.');
    }
  }

  static Future<Json> unlock(
    Json value,
    PasswordPrompt? requestPassword,
  ) async {
    if (!isEncrypted(value)) return value;
    final password = await requestPassword?.call();
    if (password == null) throw const OperationCancelled();
    return decrypt(value, password);
  }
}
