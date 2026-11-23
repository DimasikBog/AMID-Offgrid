import 'package:flutter/foundation.dart';

import '../models/data.dart';
import 'secure_channel.dart';
import 'store.dart';

class PreviewAdvertisement {
  const PreviewAdvertisement();
  String? get name => null;
}

class PreviewDiscovery {
  const PreviewDiscovery();
  PreviewAdvertisement get advertisement => const PreviewAdvertisement();
  int get rssi => 0;
}

class NearbyService extends ChangeNotifier {
  NearbyService(this.store);
  final AppStore store;
  bool get supported => false;
  bool get hosting => false;
  bool get scanning => false;
  bool get connected => false;
  bool get busy => false;
  bool get sending => false;
  String get status => 'Bluetooth — у встановленому застосунку';
  String get peerName => '';
  PairingTicket? get ticket => null;
  List<PreviewDiscovery> get discoveries => const [];
  Future<void> startHost() async {
    throw UnsupportedError('Відкрий встановлений застосунок Android/iPhone.');
  }

  Future<void> join(String code) async {
    throw UnsupportedError('Відкрий встановлений застосунок Android/iPhone.');
  }

  Future<void> connect(PreviewDiscovery device) async {
    throw UnsupportedError('Відкрий встановлений застосунок Android/iPhone.');
  }

  Future<void> send(Message message) async {
    throw UnsupportedError('Відкрий встановлений застосунок Android/iPhone.');
  }

  Future<void> stop() async {}
}
