import 'dart:convert';

import 'package:flutter/services.dart';

import 'data.dart';

const starterModelId = 'qwen3-06b-q8';
const starterAssetDirectory = 'assets/offline_model';

class StarterModel {
  const StarterModel({
    required this.bytes,
    required this.sha256,
    required this.url,
    required this.title,
    required this.license,
    this.fileName = 'qwen3-06b-q8.gguf',
  });
  final int bytes;
  final String sha256, title, license;
  final Uri url;
  final String fileName;
}

class StarterAsset {
  const StarterAsset(this.path, this.bytes, this.sha256, this.title);
  final String path, sha256, title;
  final int bytes;
}

class StarterCatalog {
  const StarterCatalog({
    required this.model,
    required this.map,
    required this.knowledge,
  });
  final StarterModel model;
  final StarterAsset map, knowledge;

  static Future<StarterCatalog> load(AssetBundle bundle) async {
    final data = decodeObject(
      await bundle.loadString('$starterAssetDirectory/catalog.json'),
    );
    if (data['format'] != 'AMID_OFFLINE_STARTER' || data['version'] != 1) {
      throw const FormatException('Невідомий каталог офлайн-набору.');
    }
    String hash(Json value) {
      final digest = value['sha256'];
      if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const FormatException('У каталозі немає контрольної суми.');
      }
      return digest;
    }

    int length(Json value, int max) {
      final bytes = value['bytes'];
      if (bytes is! int || bytes <= 0 || bytes > max) {
        throw const FormatException('Некоректний розмір пакета.');
      }
      return bytes;
    }

    StarterAsset asset(String key, String path) {
      final value = Json.from(data[key] as Map);
      if (value['asset'] != path) {
        throw const FormatException('Невідомий вбудований матеріал.');
      }
      return StarterAsset(
        path,
        length(value, 32 << 20),
        hash(value),
        value['title'] as String,
      );
    }

    final model = Json.from(data['model'] as Map);
    final uri = Uri.parse(model['url'] as String);
    if (model['id'] != starterModelId ||
        model['file'] != 'qwen3-06b-q8.gguf' ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Некоректне джерело стартової моделі.');
    }
    return StarterCatalog(
      model: StarterModel(
        bytes: length(model, 8 << 30),
        sha256: hash(model),
        url: uri,
        title: model['title'] as String,
        license: model['license'] as String,
      ),
      map: asset('map', 'assets/world.geojson'),
      knowledge: asset('knowledge', 'assets/starter.json'),
    );
  }
}

class BundledModel {
  const BundledModel(this.chunkBytes, this.parts);
  final int chunkBytes, parts;

  static Future<BundledModel?> load(
    AssetBundle bundle,
    StarterModel model,
  ) async {
    final data = jsonDecode(
      await bundle.loadString('$starterAssetDirectory/bundle.json'),
    ) as Json;
    if (data['format'] != 'AMID_BUNDLED_MODEL' ||
        data['version'] != 1 ||
        data['included'] is! bool) {
      throw const FormatException('Некоректний вбудований набір.');
    }
    if (data['included'] == false) return null;
    final chunk = data['chunkBytes'], count = data['parts'];
    if (data['bytes'] != model.bytes ||
        data['sha256'] != model.sha256 ||
        chunk is! int ||
        chunk <= 0 ||
        chunk > 8 << 20 ||
        count is! int ||
        count != (model.bytes + chunk - 1) ~/ chunk) {
      throw const FormatException('Вбудована модель не відповідає каталогу.');
    }
    return BundledModel(chunk, count);
  }

  String asset(int index) =>
      '$starterAssetDirectory/model-${index.toString().padLeft(3, '0')}.part';
}
