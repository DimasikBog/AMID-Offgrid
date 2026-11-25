import 'dart:convert';

import 'package:amid_offgrid/services/offline_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const phrase = 'local violet mountain shelter';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('authenticated local encryption rejects tampering, subject swaps and KDF abuse', () async {
    final salt = OfflineProfileCodec.randomSalt();
    final key = await OfflineProfileCodec.derive(phrase, salt);
    final envelope = await OfflineProfileCodec.encrypt(
      'subject-a',
      {'sample': 'private'},
      key,
      salt,
    );
    expect(await OfflineProfileCodec.decrypt('subject-a', envelope, key), {
      'sample': 'private',
    });
    final fresh = await OfflineProfileCodec.encrypt(
      'subject-a',
      {'sample': 'private'},
      key,
      salt,
    );
    expect(fresh['nonce'], isNot(envelope['nonce']));
    await expectLater(
      OfflineProfileCodec.decrypt('subject-b', envelope, key),
      throwsA(anything),
    );
    final tampered = {
      ...envelope,
      'ciphertext': base64Encode([1, 2, 3]),
    };
    await expectLater(
      OfflineProfileCodec.decrypt('subject-a', tampered, key),
      throwsA(anything),
    );
    for (final value in [
      {...envelope, 'rounds': 1},
      {...envelope, 'rounds': 1000000000},
      {
        ...envelope,
        'nonce': base64Encode([1]),
      },
      {...envelope, 'unexpected': true},
    ]) {
      expect(() => OfflineProfileCodec.validate(value), throwsFormatException);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
