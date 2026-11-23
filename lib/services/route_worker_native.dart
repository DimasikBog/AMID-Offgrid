import 'dart:async';
import 'dart:isolate';

import '../models/route_network.dart';
import 'route_worker_common.dart';

/// Owns at most one calculation; replacement/cancellation closes its ports and
/// requests immediate isolate shutdown, including a late spawn completion.
class RouteWorker implements RouteCalculation {
  _RouteTask? _active;
  bool _disposed = false;
  @override
  bool get running => _active != null;

  @override
  Future<OfflineRoute> calculate(Map<String, dynamic> request) {
    if (_disposed) return Future.error(StateError('Розрахунок уже закритий.'));
    cancel();
    final task = _RouteTask();
    _active = task;
    return task.start(request).whenComplete(() {
      if (identical(_active, task)) _active = null;
    });
  }

  @override
  void cancel() {
    final task = _active;
    _active = null;
    task?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}

class _Request {
  const _Request(this.data, this.reply);
  final Map<String, dynamic> data;
  final SendPort reply;
}

void _calculate(_Request request) {
  try {
    final result = calculateOfflineRoute(request.data);
    Isolate.exit(request.reply, <Object>[result]);
  } catch (error, stack) {
    Isolate.exit(request.reply, <Object>[error, stack]);
  }
}

class _RouteTask {
  final _reply = RawReceivePort();
  final _result = Completer<OfflineRoute>();
  Isolate? _isolate;
  bool _done = false;

  Future<OfflineRoute> start(Map<String, dynamic> data) {
    _reply.handler = _receive;
    try {
      Isolate.spawn(
        _calculate,
        _Request(data, _reply.sendPort),
        onError: _reply.sendPort,
        onExit: _reply.sendPort,
        errorsAreFatal: true,
        debugName: 'AMID route',
      ).then<void>((isolate) {
        if (_done) {
          isolate.kill(priority: Isolate.immediate);
        } else {
          _isolate = isolate;
        }
      }, onError: (Object error, StackTrace stack) => _fail(error, stack));
    } catch (error, stack) {
      _fail(error, stack);
    }
    return _result.future;
  }

  void _receive(dynamic value) {
    if (_done) return;
    if (value is List && value.length == 1 && value.single is OfflineRoute) {
      _stop();
      _result.complete(value.single as OfflineRoute);
    } else if (value is List && value.length == 2) {
      if (value[1] is StackTrace && value[0] != null) {
        _fail(value[0] as Object, value[1] as StackTrace);
      } else {
        final error = RemoteError('${value[0]}', '${value[1]}');
        _fail(error, error.stackTrace);
      }
    } else {
      _fail(
        StateError('Обчислення завершилося без результату.'),
        StackTrace.current,
      );
    }
  }

  void _stop() {
    _done = true;
    _reply.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void _fail(Object error, StackTrace stack) {
    if (_done) return;
    _stop();
    _result.completeError(error, stack);
  }

  void cancel() => _fail(const RouteCalculationCancelled(), StackTrace.current);
}
