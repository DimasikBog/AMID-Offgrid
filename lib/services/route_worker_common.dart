import '../models/route_network.dart';

class RouteCalculationCancelled implements Exception {
  const RouteCalculationCancelled();
  @override
  String toString() => 'Розрахунок маршруту скасовано.';
}

abstract interface class RouteCalculation {
  bool get running;
  Future<OfflineRoute> calculate(Map<String, dynamic> request);
  void cancel();
  void dispose();
}
