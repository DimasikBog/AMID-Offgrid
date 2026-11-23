import 'store.dart';
import 'assistant.dart';
import 'importer.dart';
import 'nearby.dart';

class Services {
  Services(this.store) {
    assistant = AssistantService(store);
    files = ImportService(store);
    nearby = NearbyService(store);
  }
  final AppStore store;
  late final AssistantService assistant;
  late final ImportService files;
  late final NearbyService nearby;
  void dispose() {
    assistant.dispose();
    files.cancel();
    files.dispose();
    nearby.dispose();
  }
}
