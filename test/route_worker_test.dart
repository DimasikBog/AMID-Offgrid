import 'dart:io';
import 'dart:isolate';

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/models/route_network.dart';
import 'package:amid_offgrid/services/route_worker_common.dart';
import 'package:amid_offgrid/services/route_worker_native.dart' as native;
import 'package:amid_offgrid/services/route_worker_web.dart' as web;
import 'package:flutter_test/flutter_test.dart';

Json input() => {
  'network': decodeObject(
    File('examples/route_network.json').readAsStringSync(),
  )['routing'],
  'from': 'a',
  'to': 'c',
};

Future<Object> outcome(Future<OfflineRoute> operation) =>
    operation.then<Object>((value) => value, onError: (Object error) => error);

void contract(String name, RouteCalculation Function() create) {
  test(
    '$name result, typed error and reuse complete without a running job',
    () async {
      final worker = create();
      addTearDown(worker.dispose);
      final result = await worker.calculate(input());
      expect(result.nodes.map((n) => n.id), ['a', 'b', 'c']);
      expect(worker.running, isFalse);
      await expectLater(
        worker.calculate({...input(), 'to': 'd'}),
        throwsFormatException,
      );
      expect(worker.running, isFalse);
      expect(
        (await worker.calculate({...input(), 'from': 'c', 'to': 'a'}))
            .legs
            .single
            .reversed,
        isTrue,
      );
    },
  );
  test(
    '$name replacement, cancellation and disposal retire old work',
    () async {
      final worker = create();
      addTearDown(worker.dispose);
      final first = outcome(worker.calculate(input()));
      final second = outcome(worker.calculate({...input(), 'to': 'd'}));
      worker.cancel();
      worker.cancel();
      expect(await first, isA<RouteCalculationCancelled>());
      expect(await second, isA<RouteCalculationCancelled>());
      expect(worker.running, isFalse);
      expect((await worker.calculate(input())).points, hasLength(3));
      final third = outcome(worker.calculate(input()));
      worker.dispose();
      expect(await third, isA<RouteCalculationCancelled>());
      expect(worker.running, isFalse);
      await expectLater(worker.calculate(input()), throwsStateError);
    },
  );
}

void main() {
  contract('native isolate', native.RouteWorker.new);
  contract('browser event loop', web.RouteWorker.new);
  test(
    'native spawn failure closes its task and permits a later calculation',
    () async {
      final worker = native.RouteWorker(), port = ReceivePort();
      addTearDown(worker.dispose);
      addTearDown(port.close);
      await expectLater(
        worker.calculate({...input(), 'unsendable': port}),
        throwsArgumentError,
      );
      expect(worker.running, isFalse);
      expect((await worker.calculate(input())).nodes.last.id, 'c');
    },
  );
}
