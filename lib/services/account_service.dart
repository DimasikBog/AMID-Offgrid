import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import 'account_config.dart';

bool validAccountUsername(String value) =>
    RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(value);
bool validAccountPassword(String value) =>
    value.runes.length >= 16 &&
    value.runes.toSet().length >= 5 &&
    utf8.encode(value).length <= 72;

Future<Map<String, dynamic>> solveAccountWork(
  Map<String, dynamic> challenge,
) async {
  final token = challenge['token'];
  final bits = challenge['bits'];
  if (token is! String || token.length > 700 || bits != 18) {
    throw const FormatException('Невідомий захисний запит сервера.');
  }
  final watch = Stopwatch()..start();
  for (var counter = 0; counter <= 16777216; counter++) {
    final digest = sha256.convert(utf8.encode('$token.$counter')).bytes;
    if (digest[0] == 0 && digest[1] == 0 && digest[2] < 64) {
      return {'token': token, 'counter': counter};
    }
    if (counter % 2048 == 0) {
      if (watch.elapsed > const Duration(seconds: 45)) {
        throw const FormatException(
          'Захисна перевірка триває задовго. Спробуй ще.',
        );
      }
      await Future<void>.delayed(Duration.zero);
    }
  }
  throw const FormatException('Не вдалося завершити захисну перевірку.');
}

class AccountService extends ChangeNotifier {
  SupabaseClient? _client;
  http.Client? _http;
  Timer? _idle;
  int _epoch = 0, _operationEpoch = 0;
  void _checkActive() {
    if (_disposed || _epoch != _operationEpoch) {
      throw StateError('Вхід скасовано. Спробуй ще.');
    }
  }

  bool busy = false, _disposed = false, verified = false;
  String username = '', factorId = '', totpSecret = '', totpUri = '';
  bool get signedIn => _client?.auth.currentSession != null;
  SupabaseClient get _supabase {
    _checkActive();
    return _client ??= SupabaseClient(
      accountProjectUrl,
      accountPublishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 15), lock);
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_disposed) throw StateError('Сервіс акаунтів уже закритий.');
    if (busy) throw StateError('Попередня дія ще триває.');
    _operationEpoch = _epoch;
    busy = true;
    _changed();
    try {
      return await action();
    } on AuthException {
      throw StateError(
        'Не вдалося підтвердити вхід. Перевір пароль або код 2FA.',
      );
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    _checkActive();
    final client = http.Client();
    _http = client;
    try {
      final headers = {
        'Content-Type': 'application/json',
        'apikey': accountPublishableKey,
      };
      if (authenticated) {
        final token = _client?.auth.currentSession?.accessToken;
        if (token == null) throw StateError('Спочатку увійди в акаунт.');
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await client
          .post(
            Uri.parse('$accountProjectUrl/functions/v1/account'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      _checkActive();
      if (response.bodyBytes.length > 64 << 10) {
        throw StateError('Некоректна відповідь сервера.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 401 && authenticated) {
        lock();
        throw StateError('Сеанс завершено. Увійди повторно.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(switch (data['error']) {
          'rate_limited' => 'Забагато спроб. Зачекай перед повторним входом.',
          'username_unavailable' => 'Цей логін недоступний. Обери інший.',
          'invalid_username' =>
            'Логін: 3–32 латинські літери, цифри або нижня риска.',
          'password_compromised' => 'Цей пароль уже є у відомих витоках. Обери іншу довгу парольну фразу.',
          'invalid_credentials' =>
            'Не вдалося підтвердити логін, пароль або резервний код.',
          'fresh_mfa_required' => 'Для цієї дії ще раз підтвердь код 2FA.',
          'mfa_required' => 'Підтвердь код 2FA, щоб відкрити акаунт.',
          'invalid_proof' ||
          'proof_already_used' => 'Захисна перевірка застаріла. Повтори дію.',
          _ => 'Не вдалося виконати дію. Спробуй пізніше.',
        });
      }
      _touch();
      return data;
    } on TimeoutException {
      throw StateError('Сервер не відповідає. Перевір мережу та повтори.');
    } on http.ClientException {
      throw StateError('З’єднання перерване. Перевір мережу.');
    } finally {
      client.close();
      if (identical(_http, client)) _http = null;
    }
  }

  Future<Map<String, dynamic>> _proof(String name, String purpose) async {
    final challenge = await _call({
      'action': 'challenge',
      'username': name,
      'purpose': purpose,
    });
    return solveAccountWork(challenge);
  }

  Future<void> register(String name, String password) => _run(() async {
    _validate(name, password);
    final proof = await _proof(name, 'register');
    await _call({
      'action': 'register',
      'username': name,
      'password': password,
      'proof': proof,
    });
    await _login(name, password);
  });
  Future<void> login(String name, String password) =>
      _run(() => _login(name, password));
  Future<void> _login(String name, String password) async {
    _validate(name, password);
    final data = await _call({
      'action': 'login',
      'username': name,
      'password': password,
    });
    await _supabase.auth.setSession(data['refresh_token'] as String);
    _checkActive();
    username = name;
    verified = false;
    totpSecret = '';
    totpUri = '';
    final factors = await _supabase.auth.mfa.listFactors();
    _checkActive();
    if (factors.totp.isNotEmpty) {
      factorId = factors.totp.first.id;
    } else {
      // Reuse an existing unverified enrollment after an interrupted setup.
      for (final factor in factors.all.where(
        (f) => f.factorType == FactorType.totp,
      )) {
        if (factor.status == FactorStatus.unverified) {
          await _supabase.auth.mfa.unenroll(factor.id);
        }
      }
      final enrollment = await _supabase.auth.mfa.enroll(
        friendlyName: 'AMID Offgrid',
        issuer: 'AMID Offgrid',
      );
      _checkActive();
      factorId = enrollment.id;
      totpSecret = enrollment.totp!.secret;
      totpUri = enrollment.totp!.uri;
    }
    _touch();
  }

  void _validate(String name, String password) {
    if (!validAccountUsername(name) || !validAccountPassword(password)) {
      throw const FormatException(
        'Логін: 3–32 латинські літери/цифри/_. Пароль: від 16 символів, до 72 байтів UTF-8.',
      );
    }
  }

  Future<void> verify(String code) => _run(() async {
    if (!RegExp(r'^\d{6}$').hasMatch(code) || factorId.isEmpty) {
      throw const FormatException(
        'Введи 6 цифр із застосунку-автентифікатора.',
      );
    }
    await _supabase.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
    _checkActive();
    final current = await _supabase.rpc('offgrid_session_ok');
    _checkActive();
    verified = current == true;
    if (!verified) throw StateError('Сесію не підтверджено. Увійди повторно.');
    totpSecret = '';
    totpUri = '';
    _touch();
  });
  Future<List<String>> recoveryCodes() => _run(() async {
    final data = await _call({'action': 'codes'}, authenticated: true);
    return (data['codes'] as List).cast<String>();
  });
  Future<String> export() => _run(
    () async =>
        const JsonEncoder.withIndent('  ')
            .convert(await _call({'action': 'export'}, authenticated: true)),
  );
  Future<void> recover(String name, String password, String code) =>
      _run(() async {
        _validate(name, password);
        final proof = await _proof(name, 'recover');
        await _call({
          'action': 'recover',
          'username': name,
          'password': password,
          'recoveryCode': code.replaceAll(RegExp(r'[-\s]'), '').toLowerCase(),
          'proof': proof,
        });
        await _login(name, password);
      });
  Future<void> delete() => _run(() async {
    await _call({
      'action': 'delete',
      'confirmUsername': username,
    }, authenticated: true);
    lock();
  });
  Future<void> logoutAll() => _run(() async {
    await _call({'action': 'logout_all'}, authenticated: true);
    lock();
  });
  void lock() {
    _epoch++;
    _http?.close();
    _idle?.cancel();
    final client = _client;
    _client = null;
    verified = false;
    username = '';
    factorId = '';
    totpSecret = '';
    totpUri = '';
    if (client != null) {
      unawaited(
        client.auth
            .signOut(scope: SignOutScope.local)
            .catchError((Object _) {})
            .whenComplete(client.dispose),
      );
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _http?.close();
    lock();
    super.dispose();
  }
}
