import 'data.dart';

const radioFieldLimit = 100;
const radioFieldReportLimit = 20;
const radioFieldMaxMs = 60 * 60 * 1000;
const radioFieldStates = [
  'bluetooth',
  'queued',
  'acknowledged',
  'failed',
  'unconfirmed',
  'interrupted',
];

/// Only aggregate observations are portable: never message content or node IDs.
class RadioFieldReport {
  RadioFieldReport._(this._value);
  final Json _value;
  Json toJson() => {
    for (final key in (_value.keys.toList()..sort()))
      key: _value[key] is Map
          ? <String, dynamic>{
              for (final name
                  in ((_value[key] as Map).keys.cast<String>().toList()
                    ..sort()))
                name: (_value[key] as Map)[name],
            }
          : _value[key],
  };
  String get id => _value['id'] as String;
  String get createdAt => _value['createdAt'] as String;
  int get durationMs => _value['durationMs'] as int;
  int get received => _value['receivedTexts'] as int;
  int get attempts =>
      ((_value['unicast'] as Map)['attempted'] as int) +
      ((_value['broadcast'] as Map)['attempted'] as int);
  int get acknowledged => (_value['unicast'] as Map)['acknowledged'] as int;
  int get unicastAttempts => (_value['unicast'] as Map)['attempted'] as int;

  factory RadioFieldReport.parse(Object? value) {
    final v = checkedObject(value, 'радіозвіт');
    const fields = {
      'format',
      'version',
      'id',
      'createdAt',
      'appVersion',
      'firmware',
      'region',
      'durationMs',
      'reason',
      'verification',
      'unicast',
      'broadcast',
      'ackMs',
      'rssiDbm',
      'snrDb',
      'receivedTexts',
      'processingErrors',
    };
    if (v.keys.toSet().difference(fields).isNotEmpty ||
        v.length != fields.length ||
        v['format'] != 'AMID_RADIO_FIELD_REPORT' ||
        v['version'] != 1 ||
        v['verification'] != 'unverified' ||
        v['id'] is! String ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(v['id'] as String) ||
        v['createdAt'] is! String ||
        (v['createdAt'] as String).length > 30 ||
        DateTime.tryParse(v['createdAt'] as String) == null ||
        !{
          'manual',
          'disconnected',
          'timeLimit',
          'capacity',
          'configurationChanged',
        }.contains(v['reason'])) {
      throw const FormatException('Некоректний радіозвіт.');
    }
    for (final key in ['appVersion', 'firmware']) {
      if (v[key] is! String ||
          !RegExp(r'^[a-zA-Z0-9._+-]{1,80}$').hasMatch(v[key] as String)) {
        throw const FormatException('Некоректна версія радіозвіту.');
      }
    }
    int count(Object? n, int maximum) {
      if (n is! int || n < 0 || n > maximum) {
        throw const FormatException('Некоректний лічильник радіозвіту.');
      }
      return n;
    }

    count(v['region'], 255);
    count(v['durationMs'], radioFieldMaxMs);
    count(v['receivedTexts'], 1000000);
    count(v['processingErrors'], 1000000);
    var total = 0;
    for (final key in ['unicast', 'broadcast']) {
      final values = checkedObject(v[key], key);
      if (values.length != radioFieldStates.length + 1 ||
          values.keys.any(
            (k) => k != 'attempted' && !radioFieldStates.contains(k),
          )) {
        throw const FormatException('Некоректні стани радіозвіту.');
      }
      final attempted = count(values['attempted'], radioFieldLimit);
      final sum = radioFieldStates.fold(
        0,
        (n, k) => n + count(values[k], radioFieldLimit),
      );
      if (sum != attempted ||
          values['bluetooth'] != 0 ||
          values['queued'] != 0 ||
          (key == 'broadcast' && values['acknowledged'] != 0)) {
        throw const FormatException('Неузгоджені підсумки радіозвіту.');
      }
      total += attempted;
      v[key] = values;
    }
    if (total > radioFieldLimit) {
      throw const FormatException('Завеликий радіозвіт.');
    }
    for (final entry in {
      'ackMs': (0.0, radioFieldMaxMs.toDouble()),
      'rssiDbm': (-200.0, 20.0),
      'snrDb': (-100.0, 100.0),
    }.entries) {
      final summary = checkedObject(v[entry.key], entry.key);
      final n = count(summary['count'], 1000000);
      if (summary.length != 4 ||
          !summary.keys.toSet().containsAll({'count', 'min', 'max', 'mean'})) {
        throw const FormatException('Некоректні вимірювання радіозвіту.');
      }
      for (final key in ['min', 'max', 'mean']) {
        final x = summary[key];
        if (n == 0
            ? x != null
            : x is! num ||
                  !x.isFinite ||
                  x < entry.value.$1 ||
                  x > entry.value.$2) {
          throw const FormatException('Некоректне значення радіозвіту.');
        }
      }
      if (n > 0 &&
          ((summary['min'] as num) > (summary['mean'] as num) ||
              (summary['mean'] as num) > (summary['max'] as num))) {
        throw const FormatException('Неузгоджені вимірювання радіозвіту.');
      }
      // JavaScript JSON can encode integral doubles as integers (and -0 as 0).
      // Normalize before identity comparisons when merging portable backups.
      if (n > 0) {
        for (final key in ['min', 'max', 'mean']) {
          final number = (summary[key] as num).toDouble();
          summary[key] = number == 0 ? 0.0 : number;
        }
      }
      v[entry.key] = summary;
    }
    if ((v['ackMs'] as Map)['count'] != (v['unicast'] as Map)['acknowledged']) {
      throw const FormatException('Неузгоджені ACK радіозвіту.');
    }
    return RadioFieldReport._(v);
  }
}

class _Summary {
  int count = 0;
  double? min, max;
  double mean = 0;
  void add(num x) {
    if (count >= 1000000) return;
    final value = x.toDouble();
    min = min == null || value < min! ? value : min;
    max = max == null || value > max! ? value : max;
    count++;
    mean += (value - mean) / count;
  }

  Json toJson() => {
    'count': count,
    'min': min,
    'max': max,
    'mean': count == 0 ? null : mean,
  };
}

class _Attempt {
  _Attempt(this.broadcast, this.atMs);
  final bool broadcast;
  final int atMs;
  String state = 'bluetooth';
}

class RadioFieldSession {
  RadioFieldSession({
    required this.id,
    required this.createdAt,
    required this.appVersion,
    required this.firmware,
    required this.region,
    required this.elapsedMs,
  });
  final String id, createdAt, appVersion, firmware;
  final int region;
  final int Function() elapsedMs;
  final _attempts = <int, _Attempt>{};
  final _ack = _Summary(), _rssi = _Summary(), _snr = _Summary();
  int receivedTexts = 0, processingErrors = 0;
  RadioFieldReport? _finished;
  bool get full => _attempts.length >= radioFieldLimit;
  int get attempts => _attempts.length;
  int get acknowledged => _ack.count;
  int get durationMs => elapsedMs().clamp(0, radioFieldMaxMs);
  void attempt(int packetId, {required bool broadcast}) {
    if (_finished != null || full || _attempts.containsKey(packetId)) {
      throw StateError('Польовий тест завершено або заповнено.');
    }
    _attempts[packetId] = _Attempt(broadcast, durationMs);
  }

  bool outcome(int packetId, String state) {
    if (_finished != null) return false;
    final attempt = _attempts[packetId];
    if (attempt == null ||
        !radioFieldStates.contains(state) ||
        !{'bluetooth', 'queued'}.contains(attempt.state) ||
        (attempt.broadcast && state == 'acknowledged')) {
      return false;
    }
    attempt.state = state;
    if (state == 'acknowledged') {
      _ack.add((durationMs - attempt.atMs).clamp(0, radioFieldMaxMs));
    }
    return true;
  }

  void received() {
    if (_finished == null && receivedTexts < 1000000) {
      receivedTexts++;
    }
  }

  void processingError() {
    if (_finished == null && processingErrors < 1000000) {
      processingErrors++;
    }
  }

  void signal({int? rssi, double? snr}) {
    if (_finished != null) return;
    if (rssi != null && rssi >= -200 && rssi <= 20) _rssi.add(rssi);
    if (snr != null && snr.isFinite && snr >= -100 && snr <= 100) _snr.add(snr);
  }

  RadioFieldReport finish(String reason) {
    if (_finished != null) return _finished!;
    Json counts(bool broadcast) {
      final entries = _attempts.values.where((v) => v.broadcast == broadcast);
      return {
        'attempted': entries.length,
        for (final state in radioFieldStates)
          state: entries
              .where(
                (v) =>
                    ({'bluetooth', 'queued'}.contains(v.state)
                        ? 'interrupted'
                        : v.state) ==
                    state,
              )
              .length,
      };
    }

    return _finished = RadioFieldReport.parse({
      'format': 'AMID_RADIO_FIELD_REPORT',
      'version': 1,
      'id': id,
      'createdAt': createdAt,
      'appVersion': appVersion,
      'firmware': RegExp(r'^[a-zA-Z0-9._+-]{1,80}$').hasMatch(firmware)
          ? firmware
          : 'unrecognized',
      'region': region,
      'durationMs': durationMs,
      'reason': reason,
      'verification': 'unverified',
      'unicast': counts(false),
      'broadcast': counts(true),
      'ackMs': _ack.toJson(),
      'rssiDbm': _rssi.toJson(),
      'snrDb': _snr.toJson(),
      'receivedTexts': receivedTexts,
      'processingErrors': processingErrors,
    });
  }
}
