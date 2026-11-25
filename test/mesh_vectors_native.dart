import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Uint8List meshVector(String name) {
  final data = jsonDecode(
    File('test/fixtures/mesh_vectors.json').readAsStringSync(),
  );
  final hex = data['vectors'][name] as String;
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
