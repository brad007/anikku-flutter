import 'dart:convert';

import 'package:anikku/data/catalog_service.dart';
import 'package:anikku/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support.dart';

void main() {
  test(
    'catalog decoder keeps namespaced IDs, ordered episodes and headers',
    () {
      final json = catalogJson();
      final titles = json['titles'] as List<dynamic>;
      final title = titles.first as Map<String, dynamic>;
      final episodes = title['episodes'] as List<dynamic>;
      (episodes.last as Map<String, dynamic>)['season'] = 2;
      title['episodes'] = episodes.reversed.toList();
      final catalog = Catalog.fromJson(json);
      expect(catalog.titles.single.key, 'test::one');
      expect(catalog.titles.single.episodes.first.number, 1);
      expect(catalog.titles.single.episodes.first.season, 1);
      expect(catalog.titles.single.episodes.last.season, 2);
    },
  );
  test('invalid schema, schemes and duplicate episode IDs are rejected', () {
    final service = CatalogService();
    expect(() => service.decode('{"version":2}'), throwsFormatException);
    expect(
      () => networkUri('file:///etc/passwd', 'URL'),
      throwsFormatException,
    );
    expect(
      () => networkUri('https://user:password@example.com', 'URL'),
      throwsFormatException,
    );
    final json = catalogJson();
    final title =
        (json['titles'] as List<dynamic>).first as Map<String, dynamic>;
    final episodes = title['episodes'] as List<dynamic>;
    episodes.add(episodes.first);
    expect(() => Catalog.fromJson(json), throwsFormatException);
    service.dispose();
  });
  test('fetch imports real HTTP response and reports server errors', () async {
    final service = CatalogService(
      client: MockClient(
        (request) async => request.url.path == '/ok'
            ? http.Response(jsonEncode(catalogJson()), 200)
            : http.Response('Unavailable', 503),
      ),
    );
    expect(
      (await service.fetch(Uri.parse('https://example.com/ok'))).titles,
      hasLength(1),
    );
    await expectLater(
      service.fetch(Uri.parse('https://example.com/error')),
      throwsFormatException,
    );
    service.dispose();
  });
  test('catalog size is capped before parsing', () async {
    final service = CatalogService(
      client: MockClient(
        (_) async => http.Response('x' * (CatalogService.maxBytes + 1), 200),
      ),
    );
    await expectLater(
      service.fetch(Uri.parse('https://example.com')),
      throwsFormatException,
    );
    service.dispose();
  });
}
