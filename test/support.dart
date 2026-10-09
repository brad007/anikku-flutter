import 'dart:convert';

import 'package:anikku/data/catalog_service.dart';
import 'package:anikku/data/library_repository.dart';
import 'package:anikku/domain/catalog.dart';

class MemoryStore implements StateStore {
  Map<String, dynamic>? value;
  bool fail = false;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw StateError('Disk full');
    this.value = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    writes++;
  }
}

Map<String, dynamic> catalogJson({String id = 'test', int episodes = 2}) => {
  'version': 1,
  'id': id,
  'name': 'Test catalog',
  'titles': [
    {
      'id': 'one',
      'title': 'A test story',
      'description': 'A test description.',
      'genres': ['Adventure'],
      'episodes': [
        for (var i = 1; i <= episodes; i++)
          {
            'id': '$i',
            'number': i,
            'title': 'Episode $i',
            'streams': [
              {'url': 'https://example.com/$i.mp4', 'label': '1080p'},
            ],
          },
      ],
    },
  ],
};

class FixtureCatalogService extends CatalogService {
  int episodes = 2;
  bool fail = false;
  @override
  Future<Catalog> sample() async =>
      Catalog.fromJson(catalogJson(id: 'samples'), isSample: true);
  @override
  Future<Catalog> fetch(Uri url) async {
    if (fail) throw const FormatException('Network unavailable');
    return Catalog.fromJson(catalogJson(episodes: episodes), url: url);
  }
}
