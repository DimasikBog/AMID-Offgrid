import 'store.dart';
import 'assistant.dart';
import 'importer.dart';
import 'nearby.dart';
import 'starter_setup.dart';
import 'catalog_service.dart';
import 'account_service.dart';
import 'radio_dock.dart';
import 'radio_transport_factory.dart';
import 'street_service.dart';

class Services {
  Services(this.store) {
    assistant = AssistantService(store);
    files = ImportService(store);
    setup = StarterSetup(store, files);
    nearby = NearbyService(store);
    catalog = CatalogService(store, files);
    account = AccountService(store: store);
    streets = StreetService(store);
    radioDock = RadioDockService(store, createRadioTransport());
  }
  final AppStore store;
  late final CatalogService catalog;
  late final AccountService account;
  late final StreetService streets;
  late final RadioDockService radioDock;
  late final AssistantService assistant;
  late final ImportService files;
  late final StarterSetup setup;
  late final NearbyService nearby;
  void dispose() {
    streets.dispose();
    radioDock.dispose();
    account.dispose();
    catalog.dispose();
    assistant.dispose();
    setup.dispose();
    files.cancel();
    files.dispose();
    nearby.dispose();
  }
}
