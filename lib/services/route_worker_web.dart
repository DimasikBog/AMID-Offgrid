import 'dart:async';

import '../models/route_network.dart';
import 'route_worker_common.dart';

/// Browser fallback: one bounded calculation on the main event loop. A queued
/// calculation can be cancelled before it starts; it cannot be preempted mid-run.
class RouteWorker implements RouteCalculation {
  Completer<OfflineRoute>? _active;
  bool _disposed = false;
  @override
  bool get running => _active != null;

  @override
  Future<OfflineRoute> calculate(Map<String, dynamic> request) {
    if (_disposed) return Future.error(StateError('Розрахунок уже закритий.'));
    cancel();
    final result = Completer<OfflineRoute>();
    _active = result;
    Timer.run(() {
      if (result.isCompleted) return;
      try {
        final route = calculateOfflineRoute(request);
        _active = null;
        result.complete(route);
      } catch (error, stack) {
        _active = null;
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  void cancel() {
    final result = _active;
    _active = null;
    if (result != null && !result.isCompleted) {
      result.completeError(const RouteCalculationCancelled());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}
