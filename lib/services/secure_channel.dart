import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/data.dart';

class PairingTicket {
  const PairingTicket(this.id, this.secret);
  final String id;
  final List<int> secret;
  factory PairingTicket.create() {
    final r = Random.secure();
    return PairingTicket(
      base64UrlEncode(List.generate(12, (_) => r.nextInt(256))),
      List.generate(32, (_) => r.nextInt(256)),
    );
  }
  factory PairingTicket.parse(String text) {
    if (text.length > 500) {
      throw const FormatException('Завеликий код сполучення.');
    }
    final v = decodeObject(text);
    if (v['format'] != 'AMID_PAIR' ||
        v['version'] != 1 ||
        v['id'] is! String ||
        v['secret'] is! String) {
      throw const FormatException('Це не код сполучення AMID.');
    }
    final id = v['id'] as String,
        secret = base64Url.decode(v['secret'] as String);
    if (base64Url.decode(id).length != 12 || secret.length != 32) {
      throw const FormatException('Некоректний код сполучення.');
    }
    return PairingTicket(id, secret);
  }
  String encode() => jsonEncode({
    'format': 'AMID_PAIR',
    'version': 1,
    'id': id,
    'secret': base64UrlEncode(secret),
  });
}

class SecureChannel {
  SecureChannel._(this.ticket, this.host, this._outbound, this._inbound);
  final PairingTicket ticket;
  final bool host;
  final SecretKey _outbound, _inbound;
  final _cipher = AesGcm.with256bits();
  var _sequence = 0, _highest = 0;
  final _received = <int>{};
  static Future<SecureChannel> create(
    PairingTicket ticket, {
    required bool host,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    Future<SecretKey> key(String d) => hkdf.deriveKey(
      secretKey: SecretKey(ticket.secret),
      nonce: utf8.encode(ticket.id),
      info: utf8.encode('AMID_OFFGRID/v1/$d'),
    );
    final a = await key('host-to-join'), b = await key('join-to-host');
    return SecureChannel._(ticket, host, host ? a : b, host ? b : a);
  }

  List<int> _aad(bool outbound) => utf8.encode(
    'AMID_OFFGRID/v1/${ticket.id}/${outbound == host ? 'host-to-join' : 'join-to-host'}',
  );
  Future<Uint8List> seal(Json value) async {
    final bytes = utf8.encode(
      jsonEncode({'sequence': ++_sequence, 'data': value}),
    );
    if (bytes.length > 24000) {
      throw const FormatException('Завелике повідомлення.');
    }
    final box = await _cipher.encrypt(
      bytes,
      secretKey: _outbound,
      nonce: _cipher.newNonce(),
      aad: _aad(true),
    );
    return Uint8List.fromList(box.concatenation());
  }

  Future<Json> open(Uint8List bytes) async {
    if (bytes.length < 29 || bytes.length > 32768) {
      throw const FormatException('Некоректний пакет.');
    }
    final plain = await _cipher.decrypt(
      SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16),
      secretKey: _inbound,
      aad: _aad(false),
    );
    final value = decodeObject(utf8.decode(plain)), seq = value['sequence'];
    if (seq is! int ||
        seq < 1 ||
        seq <= _highest - 256 ||
        _received.contains(seq) ||
        value['data'] is! Map) {
      throw const FormatException('Повторний або некоректний пакет.');
    }
    _highest = max(_highest, seq);
    _received.add(seq);
    _received.removeWhere((n) => n <= _highest - 256);
    return Json.from(value['data'] as Map);
  }
}
