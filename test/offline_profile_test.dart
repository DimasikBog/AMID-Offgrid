import 'dart:convert';

import 'package:amid_offgrid/services/account_service.dart';
import 'package:amid_offgrid/services/backend_native.dart';
import 'package:amid_offgrid/services/offline_profile.dart';
import 'package:amid_offgrid/services/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

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

  test('offline personalization survives restart, isolates profiles and never authorizes server actions', () async {
    final f = await openTestStore();
    AppStore? reopened;
    AccountService? account;
    final vault = OfflineProfileService(f.store);
    try {
      await f.store.setThemePreference('dark');
      await vault.create(
        username: 'alice_local',
        userId: 'fixture-alice',
        passphrase: phrase,
      );
      await vault.rename('Alice private nickname');
      await f.store.setReaderScale(1.5);
      await f.store.setPrepared('water', true);
      vault.lock();
      await f.store.setThemePreference('light');
      await f.store.setReaderScale(1);
      await vault.create(
        username: 'bob_local',
        userId: 'fixture-bob',
        passphrase: 'another local forest passphrase',
      );
      vault.lock();
      final serialized = jsonEncode(f.store.snapshot());
      for (final secret in [
        phrase,
        'alice_local',
        'fixture-alice',
        'Alice private nickname',
        'access_token',
        'refresh_token',
        'totpSecret',
      ]) {
        expect(serialized, isNot(contains(secret)));
      }
      expect(f.store.backup().containsKey('offlineProfiles'), isFalse);
      await f.store.close();
      reopened = await AppStore.open(
        backend: await PlatformBackend.open(root: f.root),
      );
      account = AccountService(store: reopened);
      await expectLater(account.enableOffline(phrase), throwsStateError);
      await expectLater(
        account.unlockOffline(
          'alice_local',
          'wrong but sufficiently long phrase',
        ),
        throwsFormatException,
      );
      expect(account.offlineUnlocked, isFalse);
      await account.unlockOffline('alice_local', phrase);
      expect(account.offlineUnlocked, isTrue);
      expect(account.verified, isFalse);
      expect(account.signedIn, isFalse);
      expect(account.offline!.displayName, 'Alice private nickname');
      expect(reopened.themePreference, 'dark');
      expect(reopened.readerScale, 1.5);
      expect(reopened.preparation, {'water'});
      await expectLater(account.recoveryCodes(), throwsStateError);
      await expectLater(account.export(), throwsStateError);
      await expectLater(account.delete(), throwsStateError);
      await expectLater(account.logoutAll(), throwsStateError);
      account.lock();
      expect(account.offlineUnlocked, isFalse);
      await account.unlockOffline(
        'bob_local',
        'another local forest passphrase',
      );
      expect(reopened.themePreference, 'light');
      expect(reopened.readerScale, 1);
      await account.forgetOffline('bob_local');
      expect(account.offlineUnlocked, isFalse);
      expect(account.offline!.hasProfile('alice_local'), isTrue);
      expect(account.offline!.hasProfile('bob_local'), isFalse);
      final pending = account.unlockOffline('alice_local', phrase);
      account.lockOnline();
      await expectLater(pending, throwsStateError);
      expect(account.offlineUnlocked, isFalse);
    } finally {
      vault.lock();
      account?.dispose();
      await f.store.close();
      await reopened?.close();
      await f.root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'locking while key derivation is pending never reopens a profile',
    () async {
      final f = await openTestStore();
      final local = OfflineProfileService(f.store);
      try {
        final pending = local.create(
          username: 'alice_local',
          userId: 'fixture',
          passphrase: phrase,
        );
        local.lock();
        await expectLater(pending, throwsStateError);
        expect(local.unlocked, isFalse);
        expect(local.hasProfile('alice_local'), isFalse);
      } finally {
        local.lock();
        await f.store.close();
        await f.root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
