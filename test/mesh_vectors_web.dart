import 'dart:convert';
import 'dart:typed_data';

Uint8List meshVector(String name) {
  const encoded = String.fromEnvironment('OFFGRID_MESH_VECTORS_BASE64');
  if (encoded.isEmpty) {
    throw StateError(
      'Run scripts/check_catalog_browser.py to supply reference vectors.',
    );
  }
  final data = jsonDecode(utf8.decode(base64.decode(encoded)));
  final hex = data['vectors'][name] as String;
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
