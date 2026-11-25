import 'dart:typed_data';

import 'radio_transport.dart';

RadioTransport createRadioTransport() => _UnavailableRadio();

class _UnavailableRadio extends RadioTransport {
  @override
  bool get supported => false;
  @override
  bool get connected => false;
  @override
  bool get scanning => false;
  @override
  String get status =>
      'Радіомодуль підключається у встановленому Android/iPhone застосунку.';
  @override
  List<RadioDevice> get devices => const [];
  @override
  Stream<Uint8List> get packets => const Stream.empty();
  @override
  Future<void> scan() async => throw UnsupportedError(status);
  @override
  Future<void> connect(String id) async => throw UnsupportedError(status);
  @override
  Future<void> write(Uint8List packet) async => throw UnsupportedError(status);
  @override
  Future<void> stop() async {}
}
