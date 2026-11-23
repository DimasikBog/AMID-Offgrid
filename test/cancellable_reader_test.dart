import 'dart:async';

import 'package:amid_offgrid/services/backup_codec.dart';
import 'package:amid_offgrid/services/cancellable_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cancelling a digest closes a stalled source and reader can be reused',
    () async {
      final reader = CancellableReader(), listening = Completer<void>();
      var cancelled = false, sourceClosed = false;
      final source = StreamController<List<int>>(
        onListen: () => listening.complete(),
        onCancel: () => sourceClosed = true,
      );
      void check() {
        if (cancelled) throw const OperationCancelled();
      }

      final operation = sha256.bind(reader.read(source.stream, check)).first;
      final observed = operation.then<Object>(
        (digest) => digest,
        onError: (Object error) => error,
      );
      await listening.future;
      source.add([1, 2, 3]);
      cancelled = true;
      reader.cancel();
      expect(
        await observed.timeout(const Duration(seconds: 2)),
        isA<OperationCancelled>(),
      );
      expect(sourceClosed, isTrue);
      await source.close();
      cancelled = false;
      final digest = await sha256
          .bind(reader.read(Stream.value([1, 2, 3]), check))
          .first;
      expect(digest, sha256.convert([1, 2, 3]));
    },
  );
}
