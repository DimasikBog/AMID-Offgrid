import 'dart:convert';

import 'package:amid_offgrid/models/radio_field_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'radio_field_support.dart';

void main() {
  test('ACK timing, pending attempts and broadcasts keep distinct totals', () {
    var ms = 0;
    final test = session(elapsed: () => ms);
    test.attempt(10, broadcast: false);
    ms = 500;
    test.outcome(10, 'queued');
    test.outcome(10, 'acknowledged');
    ms = 9999;
    test.outcome(10, 'failed'); // Terminal results never regress.
    test.attempt(11, broadcast: true);
    test.outcome(11, 'acknowledged'); // Broadcast has no recipient ACK.
    test.attempt(12, broadcast: false);
    test.outcome(12, 'unconfirmed');
    test.signal(rssi: -90, snr: -3.5);
    test.signal(rssi: -70, snr: 1.5);
    test.signal(rssi: -1000, snr: double.nan);
    test.received();
    final report = test.finish('manual'), data = report.toJson();
    expect(report.attempts, 3);
    expect(report.acknowledged, 1);
    expect(data['ackMs'], {
      'count': 1,
      'min': 500.0,
      'max': 500.0,
      'mean': 500.0,
    });
    expect((data['broadcast'] as Map)['interrupted'], 1);
    expect((data['unicast'] as Map)['unconfirmed'], 1);
    expect((data['rssiDbm'] as Map)['mean'], -80);
    expect((data['snrDb'] as Map)['mean'], -1);
    final javascriptJson = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    for (final key in ['ackMs', 'rssiDbm', 'snrDb']) {
      final values = javascriptJson[key] as Map<String, dynamic>;
      for (final name in ['min', 'max', 'mean']) {
        final value = values[name] as num;
        if (value == value.toInt()) values[name] = value.toInt();
      }
    }
    expect(
      jsonEncode(RadioFieldReport.parse(javascriptJson).toJson()),
      jsonEncode(data),
    );
    test.received();
    test.outcome(11, 'failed');
    expect(test.finish('disconnected').toJson(), data);
    expect(jsonEncode(data), isNot(contains('packetId')));
    expect(data['verification'], 'unverified');
  });

  test('report parser rejects private extra fields, malformed and inconsistent data', () {
    final valid = session().finish('manual').toJson();
    for (final edit in <void Function(Map<String, dynamic>)>[
      (v) => v['text'] = 'secret',
      (v) => v['verification'] = 'physically_verified',
      (v) => v['durationMs'] = radioFieldMaxMs + 1,
      (v) => v['receivedTexts'] = -1,
      (v) => (v['ackMs'] as Map)['count'] = 1,
      (v) => (v['rssiDbm'] as Map).addAll(<String, dynamic>{
        'count': 1,
        'min': 0,
        'max': 1,
        'mean': double.nan,
      }),
      (v) => (v['broadcast'] as Map).addAll(<String, dynamic>{
        'attempted': 1,
        'acknowledged': 1,
      }),
      (v) => (v['unicast'] as Map)['attempted'] = 1,
    ]) {
      final value = jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;
      edit(value);
      expect(() => RadioFieldReport.parse(value), throwsFormatException);
    }
    final report = RadioFieldReport.parse(valid);
    (report.toJson()['unicast'] as Map)['attempted'] = 99;
    expect(report.attempts, 0);
    final reordered = {
      for (final key in valid.keys.toList().reversed) key: valid[key],
    };
    expect(
      jsonEncode(RadioFieldReport.parse(reordered).toJson()),
      jsonEncode(report.toJson()),
    );
  });

  test('session memory and elapsed time are bounded', () {
    final test = session(elapsed: () => radioFieldMaxMs + 999);
    for (var i = 0; i < radioFieldLimit; i++) {
      test.attempt(i, broadcast: false);
    }
    expect(test.full, isTrue);
    expect(() => test.attempt(999, broadcast: false), throwsStateError);
    final report = test.finish('timeLimit');
    expect(report.durationMs, radioFieldMaxMs);
    expect((report.toJson()['unicast'] as Map)['interrupted'], radioFieldLimit);
  });
}
