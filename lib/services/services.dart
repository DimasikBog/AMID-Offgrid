import 'store.dart';
import 'assistant.dart';
import 'importer.dart';
import 'nearby.dart';
import 'starter_setup.dart';

class Services {
  Services(this.store) {
    assistant = AssistantService(store);
    files = ImportService(store);
    setup = StarterSetup(store, files);
    nearby = NearbyService(store);
  }
  final AppStore store;
  late final AssistantService assistant;
  late final ImportService files;
  late final StarterSetup setup;
  late final NearbyService nearby;
  void dispose() {
    assistant.dispose();
    setup.dispose();
    files.cancel();
    files.dispose();
    nearby.dispose();
  }
}
