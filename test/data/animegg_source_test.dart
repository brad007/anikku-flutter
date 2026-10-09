import 'package:anikku/data/sources/animegg_source.dart';
import 'package:anikku/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('source parses listings, stable episodes, languages and fresh video links', () async {
    var resolution = 0;
    final source = AnimeGgSource(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path == '/popular-series') {
          return http.Response('''
        <li class="fea"><img src="/cover.jpg"><div class="rightpop"><a href="/series/show">A real series</a></div></li>
      ''', 200);
        }
        if (path == '/search/') {
          expect(request.url.queryParameters['q'], 'spaces & symbols');
          return http.Response(
            '<a class="mse" href="/series/show"><div class="first"><h2>A real series</h2></div></a>',
            200,
          );
        }
        if (path == '/series/show') {
          return http.Response('''
        <div class="media-body"><h1>A real series</h1></div><p class="ptext">Story</p>
        <ul class="newmanga">
          <li><div><a class="anm_det_pop" href="/show-2"><strong>Show 2</strong></a><i class="anititle">Second</i></div></li>
          <li><div><a class="anm_det_pop" href="/show-1"><strong>Show 1</strong></a><i class="anititle">First</i></div></li>
        </ul>
      ''', 200);
        }
        if (path == '/show-1') {
          return http.Response('''
        <div class="tab-pane" id="subbed-Animegg"><iframe src="/embed/1"></iframe></div>
        <div class="tab-pane" id="dubbed-Animegg"><iframe src="/embed/2"></iframe></div>
      ''', 200);
        }
        if (path == '/embed/1') {
          return http.Response(
            '<script>var videoSources = [{file: "/play/video.mp4?token=${++resolution}", label: "720p", isBk: false}];</script>',
            200,
          );
        }
        return http.Response('mirror down', 503);
      }),
    );
    addTearDown(source.dispose);
    final page = await source.browse();
    expect(page.titles.single.sourceId, 'animegg');
    expect(page.titles.single.episodes, isEmpty);
    expect(
      (await source.browse(query: 'spaces & symbols')).titles.single.id,
      '/series/show',
    );
    final anime = await source.details(page.titles.single);
    expect(anime.episodes.map((e) => e.number), [1, 2]);
    final restored = Anime.fromJson(anime.toJson(), source.id);
    expect(restored.episodes.first.sourceUrl!.path, '/show-1');
    final first = await source.resolve(anime, anime.episodes.first);
    final second = await source.resolve(anime, anime.episodes.first);
    expect(first.single.label, 'SUBBED · 720p');
    expect(first.single.headers['Referer'], 'https://www.animegg.org');
    expect(first.single.url, isNot(second.single.url));
    expect(
      anime.episodes.first.streams,
      isEmpty,
      reason: 'Transient video URLs must not become persisted episode metadata',
    );
  });

  test('missing source layout and blocked responses fail honestly', () async {
    for (final status in [200, 403]) {
      final source = AnimeGgSource(
        client: MockClient(
          (_) async => http.Response('<html>Unavailable</html>', status),
        ),
      );
      await expectLater(source.browse(), throwsFormatException);
      source.dispose();
    }
  });
}
