import 'package:anikku/data/sources/internet_archive_source.dart';
import 'package:anikku/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'source searches archive metadata and builds direct MP4 episodes',
    () async {
      final source = InternetArchiveSource(
        client: MockClient((request) async {
          if (request.url.path == '/advancedsearch.php') {
            expect(request.url.queryParameters['q'], contains('Cowboy Bebop'));
            return http.Response('''
          {
            "response": {
              "docs": [
                {
                  "identifier": "anime_item",
                  "title": "Archive Anime",
                  "description": "<p>Playable item</p>",
                  "date": "1963"
                }
              ]
            }
          }
          ''', 200);
          }
          if (request.url.path == '/metadata/anime_item') {
            return http.Response('''
          {
            "metadata": {
              "title": "Archive Anime Full",
              "description": "Clean description",
              "year": "1963"
            },
            "files": [
              {"name": "Episode_02_512kb.mp4", "format": "512Kb MPEG4", "size": "52428800"},
              {"name": "Episode_01_h264.mp4", "format": "h.264", "size": "104857600"},
              {"name": "anime_item_meta.xml", "format": "Metadata"}
            ]
          }
          ''', 200);
          }
          return http.Response('missing', 404);
        }),
      );
      addTearDown(source.dispose);

      final page = await source.browse(query: 'Cowboy Bebop');
      expect(page.titles.single.title, 'Archive Anime');
      expect(
        page.titles.single.coverUrl.toString(),
        contains('/services/img/'),
      );

      final details = await source.details(page.titles.single);
      expect(details.title, 'Archive Anime Full');
      expect(details.year, 1963);
      expect(details.episodes.map((e) => e.title), [
        'Episode 01 h264',
        'Episode 02 512kb',
      ]);
      expect(
        details.episodes.first.streams.single.url.toString(),
        contains('/download/anime_item/Episode_01_h264.mp4'),
      );
      expect(details.episodes.first.streams.single.label, 'h.264 · 100 MB');
      expect(await source.resolve(details, details.episodes.first), isNotEmpty);
    },
  );

  test('items without compatible video fail honestly', () async {
    final source = InternetArchiveSource(
      client: MockClient(
        (_) async => http.Response('''
        {"metadata": {"title": "Text Only"}, "files": [{"name":"meta.xml","format":"Metadata"}]}
      ''', 200),
      ),
    );
    addTearDown(source.dispose);
    await expectLater(
      source.details(
        Anime(
          id: 'text_only',
          sourceId: source.id,
          title: 'Text Only',
          episodes: const [],
          sourceUrl: Uri.parse('https://archive.org/details/text_only'),
        ),
      ),
      throwsFormatException,
    );
  });
}
