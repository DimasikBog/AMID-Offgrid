import 'dart:convert';

import 'package:amid_offgrid/services/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const password = 'Довгий пароль AMID 2026';
  final backup = <String, dynamic>{
    'format': 'AMID_OFFGRID_BACKUP',
    'version': 1,
    'packs': [],
    'pins': [],
    'messages': [],
    'draft': 'Приватний текст 🌍',
  };
  test('encrypted backups round trip and do not contain plaintext', () async {
    final encrypted = await BackupCodec.encrypt(backup, password);
    expect(jsonEncode(encrypted), isNot(contains('Приватний текст')));
    expect(await BackupCodec.decrypt(encrypted, password), backup);
    final another = await BackupCodec.encrypt(backup, password);
    expect(another['salt'], isNot(encrypted['salt']));
    expect(another['nonce'], isNot(encrypted['nonce']));
  });
  test(
    'wrong passwords and tampered authenticated fields are rejected',
    () async {
      final encrypted = await BackupCodec.encrypt(backup, password);
      await expectLater(
        BackupCodec.decrypt(encrypted, 'Інший пароль для AMID'),
        throwsFormatException,
      );
      final bytes = base64Decode(encrypted['ciphertext'] as String)..[0] ^= 1;
      await expectLater(
        BackupCodec.decrypt({
          ...encrypted,
          'ciphertext': base64Encode(bytes),
        }, password),
        throwsFormatException,
      );
    },
  );
  test(
    'unsupported and excessive KDF parameters are rejected before work',
    () async {
      for (final rounds in [-1, 0, 999999999]) {
        await expectLater(
          BackupCodec.decrypt({
            'format': BackupCodec.format,
            'version': 1,
            'cipher': 'AES-256-GCM',
            'kdf': 'PBKDF2-HMAC-SHA256',
            'iterations': rounds,
          }, password),
          throwsFormatException,
        );
      }
      await expectLater(
        BackupCodec.encrypt(backup, '123'),
        throwsFormatException,
      );
      await expectLater(
        BackupCodec.unlock({'format': BackupCodec.format}, () async => null),
        throwsA(isA<OperationCancelled>()),
      );
    },
  );
}
