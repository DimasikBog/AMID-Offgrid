import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models/data.dart';
import 'account_config.dart';
import 'store.dart';

/// A local profile is never an Auth session and contains no server credential.
class OfflineProfileCodec {
  static const rounds = 600000;
  static const format = 'AMID_OFFLINE_PROFILE';
  static final _cipher = AesGcm.with256bits();
  static bool validPassphrase(String value) =>
      value.runes.length >= 16 &&
      value.runes.toSet().length >= 5 &&
      utf8.encode(value).length <= 256;
  static String id(String username) =>
      sha256.convert(utf8.encode('$accountProjectUrl/$username')).toString();
  static List<int> randomSalt() =>
      List.generate(16, (_) => Random.secure().nextInt(256));

  static Future<List<int>> derive(String password, List<int> salt) =>
      compute(_derive, (password, salt), debugLabel: 'offline-profile-key');
  static Future<List<int>> _derive((String, List<int>) input) async {
    if (!validPassphrase(input.$1) || input.$2.length != 16) {
      throw const FormatException(
        'Локальна фраза: від 16 символів, до 256 байтів та щонайменше 5 різних символів.',
      );
    }
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: rounds,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(input.$1)), nonce: input.$2);
    return key.extractBytes();
  }

  static List<int> bytes(Json value, String field, int maximum, {int? exact}) {
    final text = value[field];
    if (text is! String || text.length > ((maximum + 2) ~/ 3) * 4) {
      throw const FormatException('Пошкоджена локальна копія профілю.');
    }
    final result = base64Decode(text);
    if (result.length > maximum || (exact != null && result.length != exact)) {
      throw const FormatException('Пошкоджена локальна копія профілю.');
    }
    return result;
  }

  static void validate(Json value) {
    if (value.length != 9 ||
        value['format'] != format ||
        value['version'] != 1 ||
        value['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        value['rounds'] != rounds ||
        value['cipher'] != 'AES-256-GCM') {
      throw const FormatException('Непідтримувана локальна копія профілю.');
    }
    bytes(value, 'salt', 16, exact: 16);
    bytes(value, 'nonce', 12, exact: 12);
    bytes(value, 'mac', 16, exact: 16);
    bytes(value, 'ciphertext', 8192);
  }

  static Future<Json> encrypt(
    String subject,
    Json payload,
    List<int> key,
    List<int> salt,
  ) async {
    final plain = utf8.encode(jsonEncode(payload));
    if (plain.length > 8192) throw const FormatException('Профіль завеликий.');
    final box = await _cipher.encrypt(
      plain,
      secretKey: SecretKey(key),
      aad: utf8.encode('$format/v1/$subject'),
    );
    return {
      'format': format,
      'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'rounds': rounds,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
  }

  static Future<Json> decrypt(String subject, Json value, List<int> key) async {
    validate(value);
    final plain = await _cipher.decrypt(
      SecretBox(
        bytes(value, 'ciphertext', 8192),
        nonce: bytes(value, 'nonce', 12, exact: 12),
        mac: Mac(bytes(value, 'mac', 16, exact: 16)),
      ),
      secretKey: SecretKey(key),
      aad: utf8.encode('$format/v1/$subject'),
    );
    return decodeObject(utf8.decode(plain));
  }
}

class OfflineProfileService {
  OfflineProfileService(this.store, {this.onActivity});
  final AppStore store;
  final VoidCallback? onActivity;
  int _epoch = 0;
  Uint8List? _key;
  List<int>? _salt;
  Json? _profile;
  String _id = '';
  bool get unlocked => _profile != null;
  String get username => _profile?['username'] as String? ?? '';
  String get displayName => _profile?['displayName'] as String? ?? '';
  String get verifiedAt => _profile?['verifiedAt'] as String? ?? '';
  bool hasProfile(String name) =>
      store.offlineProfile(OfflineProfileCodec.id(name)) != null;

  void _check(int epoch) {
    if (_epoch != epoch) throw StateError('Локальний вхід скасовано.');
  }

  Future<void> create({
    required String username,
    required String userId,
    required String passphrase,
  }) async {
    final epoch = _epoch;
    final salt = OfflineProfileCodec.randomSalt();
    final key = Uint8List.fromList(
      await OfflineProfileCodec.derive(passphrase, salt),
    );
    try {
      _check(epoch);
      final payload = <String, dynamic>{
        'username': username,
        'userId': userId,
        'realm': accountProjectUrl,
        'displayName': username,
        'verifiedAt': DateTime.now().toUtc().toIso8601String(),
        'preferences': store.personalization,
      };
      final id = OfflineProfileCodec.id(username);
      final envelope = await OfflineProfileCodec.encrypt(
        id,
        payload,
        key,
        salt,
      );
      _check(epoch);
      await store.saveOfflineProfile(
        id,
        envelope,
        checkActive: () => _check(epoch),
      );
      _check(epoch);
      _activate(id, payload, key, salt);
    } catch (_) {
      key.fillRange(0, key.length, 0);
      rethrow;
    }
  }

  Future<void> unlock(String name, String passphrase) async {
    lock();
    final epoch = _epoch, id = OfflineProfileCodec.id(name);
    final envelope = store.offlineProfile(id);
    Uint8List? key;
    try {
      if (envelope == null) throw const FormatException();
      OfflineProfileCodec.validate(envelope);
      final salt = OfflineProfileCodec.bytes(envelope, 'salt', 16, exact: 16);
      key = Uint8List.fromList(
        await OfflineProfileCodec.derive(passphrase, salt),
      );
      _check(epoch);
      final payload = await OfflineProfileCodec.decrypt(id, envelope, key);
      _check(epoch);
      if (payload['realm'] != accountProjectUrl ||
          payload['username'] != name ||
          payload['userId'] is! String ||
          payload['displayName'] is! String ||
          (payload['displayName'] as String).runes.length > 80 ||
          payload['verifiedAt'] is! String ||
          DateTime.tryParse(payload['verifiedAt'] as String) == null ||
          payload['preferences'] is! Map) {
        throw const FormatException();
      }
      final preferences = Json.from(payload['preferences'] as Map);
      await store.applyPersonalization(
        preferences,
        checkActive: () => _check(epoch),
      );
      _check(epoch);
      _activate(id, payload, key, salt);
    } catch (_) {
      if (key != null) key.fillRange(0, key.length, 0);
      _check(epoch);
      throw const FormatException(
        'Не вдалося відкрити локальний профіль. Перевір логін, локальну фразу та наявність копії на цьому пристрої.',
      );
    }
  }

  void _activate(String id, Json profile, Uint8List key, List<int> salt) {
    _key?.fillRange(0, _key!.length, 0);
    _id = id;
    _key = key;
    _salt = salt;
    _profile = profile;
    final epoch = _epoch;
    store.bindOfflineProfile(id, (preferences) async {
      _check(epoch);
      onActivity?.call();
      final envelope = await OfflineProfileCodec.encrypt(
        id,
        {..._profile!, 'preferences': preferences},
        key,
        salt,
      );
      _check(epoch);
      return envelope;
    });
  }

  Future<void> rename(String name) async {
    if (!unlocked) throw StateError('Спочатку відкрий локальний профіль.');
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.runes.length > 80 ||
        trimmed.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException(
        'Ім’я: від 1 до 80 символів без керівних знаків.',
      );
    }
    final epoch = _epoch,
        previous = _profile!,
        payload = {..._profile!, 'displayName': trimmed};
    try {
      await store.updateOfflineProfile(_id, (preferences) async {
        _check(epoch);
        final envelope = await OfflineProfileCodec.encrypt(
          _id,
          {...payload, 'preferences': preferences},
          _key!,
          _salt!,
        );
        _check(epoch);
        _profile = payload;
        return envelope;
      }, checkActive: () => _check(epoch));
    } catch (_) {
      if (_epoch == epoch) _profile = previous;
      rethrow;
    }
    _check(epoch);
  }

  Future<void> forget(String name) async {
    if (username == name) lock();
    await store.removeOfflineProfile(OfflineProfileCodec.id(name));
  }

  void lock() {
    _epoch++;
    store.unbindOfflineProfile();
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _salt = null;
    _profile = null;
    _id = '';
  }
}
