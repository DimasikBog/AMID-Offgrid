import 'package:amid_offgrid/models/emergency.dart';
import 'package:amid_offgrid/services/emergency_actions.dart';
import 'package:amid_offgrid/services/emergency_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 26, 9);
  EmergencyTicket arm(
    EmergencyConfirmation gate, {
    EmergencyAction action = EmergencyAction.call,
    String number = '112',
    bool training = false,
  }) => gate.arm(
    action: action,
    number: number,
    message: 'fixture',
    training: training,
    language: ConfirmationLanguage.ukrainian,
    now: now,
  );
  test('country selection never carries Czech national numbers into other EU countries', () {
    expect(
      emergencyNumber(EmergencyRegion.czechia, EmergencyService.police),
      '158',
    );
    expect(
      emergencyNumber(EmergencyRegion.czechia, EmergencyService.medical),
      '155',
    );
    expect(
      emergencyNumber(EmergencyRegion.czechia, EmergencyService.fire),
      '150',
    );
    for (final service in EmergencyService.values) {
      expect(emergencyNumber(EmergencyRegion.europeanUnion, service), '112');
    }
  });
  test('only an exact final affirmative phrase consumes one armed foreground ticket', () {
    final gate = EmergencyConfirmation();
    final ticket = arm(gate);
    for (final phrase in [
      'так',
      'не підтверджую виклик допомоги',
      'підтверджую виклик допомоги скасувати',
      'confirm emergency call',
    ]) {
      expect(gate.consume(ticket, now, spoken: phrase), isFalse);
    }
    expect(
      gate.consume(ticket, now, spoken: ticket.phrase, finalResult: false),
      isFalse,
    );
    expect(
      gate.consume(ticket, now, spoken: '  ПІДТВЕРДЖУЮ  ВИКЛИК ДОПОМОГИ! '),
      isTrue,
    );
    expect(gate.consume(ticket, now, spoken: ticket.phrase), isFalse);
    final first = arm(gate);
    final next = arm(gate, number: '158');
    expect(gate.consume(first, now), isFalse);
    gate.cancel();
    expect(gate.consume(next, now), isFalse);
    final expired = arm(gate);
    expect(gate.consume(expired, now.add(const Duration(minutes: 2))), isFalse);
    expect(() => arm(gate, number: '112;900'), throwsFormatException);
  });
  test('SMS includes actual WGS84 fix time/accuracy and user details, without invented victim count', () {
    final fix = EmergencyFix(50.06, 15.11, 12.5, now);
    final message = emergencyMessage(
      service: EmergencyService.police,
      fix: fix,
      description: 'Nejsem v bezpeci',
      name: 'Fixture',
      cannotSpeak: true,
    );
    expect(message, contains('50.060000, 15.110000'));
    expect(message, contains(now.toIso8601String()));
    expect(message, contains('+/-13 m'));
    expect(message, contains('policie'));
    expect(message, contains('Nemohu mluvit'));
    expect(message, isNot(contains('Osob:')));
    expect(
      emergencyMessage(service: EmergencyService.all, people: 3),
      contains('Osob: 3'),
    );
    expect(
      emergencyMessage(service: EmergencyService.all),
      contains('GPS nedostupne'),
    );
    expect(
      () => emergencyMessage(service: EmergencyService.all, people: 0),
      throwsFormatException,
    );
    expect(fix.fresh(now), isTrue);
    expect(fix.fresh(now.add(const Duration(minutes: 3))), isFalse);
    expect(fix.fresh(now.subtract(const Duration(minutes: 3))), isFalse);
    for (final coords in [
      [double.nan, 0.0],
      [91.0, 0.0],
      [0.0, 181.0],
    ]) {
      expect(
        () => EmergencyFix(coords[0], coords[1], 10, now),
        throwsFormatException,
      );
    }
  });
  test('training and inactive handoffs cannot reach native SMS; real handoff only composes for 112', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('com.amid.offgrid/emergency');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final actions = EmergencyActions(), gate = EmergencyConfirmation();
    await expectLater(
      actions.perform(arm(gate, action: EmergencyAction.sms, training: true)),
      throwsStateError,
    );
    await expectLater(
      actions.perform(
        arm(gate, action: EmergencyAction.sms),
        stillActive: () => false,
      ),
      throwsStateError,
    );
    expect(calls, isEmpty);
    expect(
      await actions.perform(arm(gate, action: EmergencyAction.sms)),
      EmergencyHandoff.messageOpened,
    );
    expect(calls, hasLength(1));
    expect(calls.single.method, 'composeSms');
    expect(calls.single.arguments, {'number': '112', 'body': 'fixture'});
    await expectLater(
      actions.perform(arm(gate, action: EmergencyAction.sms, number: '158')),
      throwsStateError,
    );
    expect(calls, hasLength(1));
  });
  test('cancelling before asynchronous voice initialization never starts native recording', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('com.amid.offgrid/emergency');
    var nativeStarts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'voiceStart') nativeStarts++;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final voice = EmergencyVoice();
    final start = voice.start(ConfirmationLanguage.ukrainian, (_, _) {}, () {});
    await voice.cancel();
    expect(await start, isFalse);
    expect(nativeStarts, 0);
  });
}
