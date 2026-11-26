import 'dart:async';

import 'package:amid_offgrid/models/emergency.dart';
import 'package:amid_offgrid/screens/emergency_screen.dart';
import 'package:amid_offgrid/services/emergency_actions.dart';
import 'package:amid_offgrid/services/emergency_voice.dart';
import 'package:amid_offgrid/widgets/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Actions extends EmergencyActions {
  final calls = <EmergencyTicket>[];
  bool failLocation = false;
  @override
  bool get smsSupported => true;
  @override
  Future<EmergencyFix> locate({
    bool Function()? stillActive,
    bool requestPermission = true,
  }) async {
    if (failLocation) throw StateError('fixture permission denial');
    return EmergencyFix(50.06, 15.11, 12, DateTime.now());
  }

  @override
  Future<EmergencyHandoff> perform(
    EmergencyTicket ticket, {
    bool Function()? stillActive,
  }) async {
    calls.add(ticket);
    return ticket.action == EmergencyAction.call
        ? EmergencyHandoff.phoneOpened
        : EmergencyHandoff.messageOpened;
  }
}

class _Voice extends EmergencyVoice {
  void Function(String, bool)? words;
  int starts = 0;
  bool available = true;
  Completer<bool>? pending;
  @override
  Future<bool> start(
    ConfirmationLanguage language,
    void Function(String, bool) words,
    VoidCallback failed,
  ) {
    this.words = words;
    starts++;
    return pending?.future ?? Future.value(available);
  }

  @override
  Future<void> cancel() async {}
}

Future<void> tapControl(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'SOS training at 320px text $scale never reaches transport or microphone automatically',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final actions = _Actions(), voice = _Voice();
        await tester.pumpWidget(
          MaterialApp(
            theme: offgridTheme(Brightness.dark, style: 'cyberpunk'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: EmergencyScreen(
              actions: actions,
              voice: voice,
              initialTraining: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapControl(tester, find.byKey(const ValueKey('sos-call')));
        await tester.pumpAndSettle();
        expect(actions.calls, isEmpty);
        expect(voice.starts, 0);
        await tester.pumpAndSettle();
        await tapControl(tester, find.byKey(const ValueKey('sos-confirm')));
        await tester.pumpAndSettle();
        expect(find.textContaining('ТРЕНУВАННЯ завершено'), findsOneWidget);
        expect(actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'partial/late voice, cancellation and backgrounding cannot dispatch; manual call works without GPS',
    (tester) async {
      final actions = _Actions()..failLocation = true, voice = _Voice();
      await tester.pumpWidget(
        MaterialApp(
          home: EmergencyScreen(actions: actions, voice: voice),
        ),
      );
      await tester.pumpAndSettle();
      await tapControl(tester, find.byKey(const ValueKey('sos-call')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tapControl(tester, find.text('Підтвердити голосом'));
      await tester.pumpAndSettle();
      final old = voice.words!;
      old('Підтверджую виклик допомоги', false);
      await tester.pump();
      expect(actions.calls, isEmpty);
      await tapControl(tester, find.text('Скасувати'));
      await tester.pumpAndSettle();
      old('Підтверджую виклик допомоги', true);
      await tester.pump();
      expect(actions.calls, isEmpty);
      await tapControl(tester, find.byKey(const ValueKey('sos-call')));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      old('Підтверджую виклик допомоги', true);
      await tester.pump();
      expect(actions.calls, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tapControl(tester, find.byKey(const ValueKey('sos-call')));
      await tester.pumpAndSettle();
      await tapControl(tester, find.byKey(const ValueKey('sos-confirm')));
      await tester.pumpAndSettle();
      expect(actions.calls, hasLength(1));
      expect(actions.calls.single.number, '112');
      expect(
        find.textContaining('Доставлення координат AMID не підтверджує'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'one exact final voice result triggers one handoff and timeout cannot later trigger another',
    (tester) async {
      final actions = _Actions(), voice = _Voice();
      await tester.pumpWidget(
        MaterialApp(
          home: EmergencyScreen(actions: actions, voice: voice),
        ),
      );
      await tester.pumpAndSettle();
      await tapControl(tester, find.byKey(const ValueKey('sos-call')));
      await tester.pumpAndSettle();
      await tapControl(tester, find.text('Підтвердити голосом'));
      await tester.pumpAndSettle();
      voice.words!('Підтверджую виклик допомоги', true);
      voice.words!('Підтверджую виклик допомоги', true);
      await tester.pumpAndSettle();
      expect(actions.calls, hasLength(1));
      await tester.pump(const Duration(seconds: 70));
      expect(actions.calls, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Czech SMS previews actual coordinates and only hands off after confirmation',
    (tester) async {
      final actions = _Actions(), voice = _Voice();
      await tester.pumpWidget(
        MaterialApp(
          home: EmergencyScreen(actions: actions, voice: voice),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('sos-sms')))
            .onPressed,
        isNull,
      );
      await tapControl(tester, find.byKey(const ValueKey('sos-region')));
      await tapControl(tester, find.text('Чехія').last);
      await tapControl(tester, find.byKey(const ValueKey('sos-sms')));
      expect(actions.calls, isEmpty);
      expect(find.textContaining('50.060000, 15.110000'), findsWidgets);
      await tapControl(tester, find.byKey(const ValueKey('sos-confirm')));
      expect(actions.calls, hasLength(1));
      expect(actions.calls.single.action, EmergencyAction.sms);
      expect(actions.calls.single.number, '112');
      expect(actions.calls.single.message, contains('50.060000, 15.110000'));
      expect(find.textContaining('AMID не знає'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
