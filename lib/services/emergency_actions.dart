import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency.dart';

enum EmergencyHandoff { phoneOpened, messageOpened, copiedMessageOpened }

class EmergencyActions {
  static const _channel = MethodChannel('com.amid.offgrid/emergency');
  bool get nativePhone =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  bool get smsSupported =>
      nativePhone ||
      (kIsWeb &&
          {
            TargetPlatform.android,
            TargetPlatform.iOS,
          }.contains(defaultTargetPlatform));

  Future<EmergencyFix> locate({
    bool Function()? stillActive,
    bool requestPermission = true,
  }) async {
    void check() {
      if (stillActive?.call() == false) throw StateError("Запит скасовано.");
    }

    check();
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Геолокацію вимкнено. Можна телефонувати без GPS.');
    }
    check();
    var permission = await Geolocator.checkPermission();
    check();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Доступ до GPS не надано. Виклик залишається доступним.',
      );
    }
    check();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return EmergencyFix(
      position.latitude,
      position.longitude,
      position.accuracy,
      position.timestamp,
    );
  }

  Future<EmergencyHandoff> perform(
    EmergencyTicket ticket, {
    bool Function()? stillActive,
  }) async {
    if (stillActive?.call() == false) throw StateError("Дію скасовано.");
    // A second barrier: training must never reach any system/telephony API.
    if (ticket.training) {
      throw StateError('Тренування не може запускати зв’язок.');
    }
    if (!emergencyNumbers.contains(ticket.number)) {
      throw const FormatException('Непідтримуваний номер.');
    }
    if (ticket.action == EmergencyAction.call) {
      if (!await launchUrl(
        Uri(scheme: 'tel', path: ticket.number),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      )) {
        throw StateError(
          'Не вдалося відкрити телефон. Набери ${ticket.number} вручну.',
        );
      }
      return EmergencyHandoff.phoneOpened;
    }
    if (ticket.number != '112' || !smsSupported) {
      throw StateError(
        'SMS з цього пристрою недоступна. Скопіюй координати й скористайся телефоном.',
      );
    }
    if (nativePhone) {
      final result = await _channel.invokeMethod<bool>('composeSms', {
        'number': '112',
        'body': ticket.message,
      });
      if (result != true) {
        throw StateError(
          'SMS недоступна. Скопіюй координати й скористайся телефоном.',
        );
      }
      return EmergencyHandoff.messageOpened;
    }
    // Mobile web SMS URLs do not reliably preserve body text on every OS.
    await Clipboard.setData(ClipboardData(text: ticket.message));
    if (stillActive?.call() == false) throw StateError('Дію скасовано.');
    if (!await launchUrl(
      Uri(scheme: 'sms', path: '112'),
      webOnlyWindowName: '_self',
    )) {
      throw StateError(
        'Текст скопійовано. Відкрий SMS вручну, встав текст і перевір номер 112.',
      );
    }
    return EmergencyHandoff.copiedMessageOpened;
  }
}
