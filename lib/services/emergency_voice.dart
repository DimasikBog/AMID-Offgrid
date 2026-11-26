import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/emergency.dart';

class EmergencyVoice {
  static const _methods = MethodChannel('com.amid.offgrid/emergency');
  static const _events = EventChannel('com.amid.offgrid/emergency_voice');
  static int _serial = 0;
  int? _session;
  int _generation = 0;
  StreamSubscription<dynamic>? _subscription;
  Future<bool> start(
    ConfirmationLanguage language,
    void Function(String, bool) words,
    VoidCallback failed,
  ) async {
    if (kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      return false;
    }
    final generation = ++_generation;
    await _stopCurrent();
    if (generation != _generation) return false;
    final id = ++_serial;
    _session = id;
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (_session != id || event is! Map || event['session'] != id) return;
        if (event['words'] is String && event['final'] == true) {
          words(event['words'] as String, true);
        }
        if (event['error'] == true) failed();
      },
      onError: (Object error) {
        if (_session == id) failed();
      },
    );
    try {
      final locale = switch (language) {
        ConfirmationLanguage.ukrainian => 'uk-UA',
        ConfirmationLanguage.czech => 'cs-CZ',
        ConfirmationLanguage.english => 'en-US',
      };
      final ready = await _methods.invokeMethod<bool>('voiceStart', {
        'session': id,
        'locale': locale,
      });
      if (_session != id) return false;
      if (ready != true) {
        await cancel();
        return false;
      }
      return true;
    } catch (_) {
      if (_session == id) await cancel();
      return false;
    }
  }

  Future<void> cancel() {
    _generation++;
    return _stopCurrent();
  }

  Future<void> _stopCurrent() async {
    final id = _session;
    _session = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    if (id != null) {
      try {
        await _methods.invokeMethod<void>('voiceCancel', {'session': id});
      } catch (_) {}
    }
  }
}
