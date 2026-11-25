import 'package:flutter/foundation.dart';

class RadioDevice {
  const RadioDevice(this.id, this.name, this.rssi);
  final String id, name;
  final int rssi;
}

abstract class RadioTransport extends ChangeNotifier {
  bool get supported;
  bool get connected;
  bool get scanning;
  String get status;
  List<RadioDevice> get devices;
  Stream<Uint8List> get packets;
  Future<void> scan();
  Future<void> connect(String id);
  Future<void> write(Uint8List packet);
  Future<void> stop();
}
