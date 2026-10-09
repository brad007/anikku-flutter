// Adapted from Yuzono anime-extensions AnimeGG (Apache-2.0); see NOTICE.
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../../domain/catalog.dart';
import 'anime_source.dart';

/// Portable source adapter: stable episode pages, freshly resolved video URLs.
class AnimeGgSource implements AnimeSource {
  AnimeGgSource({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? Uri.parse('https://www.animegg.org');
  final http.Client _client;
  final Uri baseUrl;
  @override
  String get id => 'animegg';
  @override
  String get name => 'AnimeGG';

  Future<Document> _get(Uri uri) async {
    const limit = 5 * 1024 * 1024;
    final request = http.Request('GET', uri)
      ..headers.addAll({'User-Agent': 'Mozilla/5.0', 'Referer': '$baseUrl/'});
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw FormatException('$name returned HTTP ${response.statusCode}.');
    }
    if ((response.contentLength ?? 0) > limit) {
      throw const FormatException('Source page is too large.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 25),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > limit) {
        throw const FormatException('Source page is too large.');
      }
    }
    return html.parse(utf8.decode(bytes));
  }

  @override
  Future<SourcePage> browse({String query = '', int page = 1}) async {
    final searching = query.trim().isNotEmpty;
    final uri = searching
        ? baseUrl
              .resolve('/search/')
              .replace(queryParameters: {'q': query.trim()})
        : baseUrl
              .resolve('/popular-series')
              .replace(
                queryParameters: {
                  'sortBy': 'hits',
                  'sortDirection': 'DESC',
                  'ongoing': '',
                  'limit': '50',
                  'start': '0',
                },
              );
    final doc = await _get(uri);
    final titles = <String, Anime>{};
    for (final item in doc.querySelectorAll(searching ? 'a.mse' : '.fea')) {
      final link = searching ? item : item.querySelector('.rightpop a');
      final href = link?.attributes['href'];
      final title = searching
          ? item.querySelector('.first h2')?.text
          : link?.text;
      if (href == null || title == null || title.trim().isEmpty) continue;
      final url = baseUrl.resolve(href);
      final cover = item.querySelector('img')?.attributes['src'];
      titles[url.path] = Anime(
        id: url.path,
        sourceId: id,
        title: title.trim(),
        episodes: const [],
        sourceUrl: url,
        coverUrl: cover == null ? null : baseUrl.resolve(cover),
        genres: const ['Anime'],
      );
    }
    if (!searching && titles.isEmpty) {
      throw const FormatException(
        'The anime source layout changed or is unavailable.',
      );
    }
    return SourcePage(titles.values.toList(), hasMore: false);
  }

  @override
  Future<Anime> details(Anime anime) async {
    final doc = await _get(anime.sourceUrl!);
    final episodes = <String, Episode>{};
    for (final row in doc.querySelectorAll('.newmanga li div')) {
      final link = row.querySelector('.anm_det_pop');
      final href = link?.attributes['href'];
      if (href == null) continue;
      final url = baseUrl.resolve(href);
      final match = RegExp(r'(\d+(?:\.\d+)?)(?:-\d+(?:\.\d+)?)?$')
          .firstMatch(link!.text.trim());
      final number =
          double.tryParse(match?.group(1) ?? '') ??
          (episodes.length + 1).toDouble();
      final title = row.querySelector('.anititle')?.text.trim() ?? '';
      episodes[url.path] = Episode(
        id: url.path,
        number: number,
        title: title.isEmpty
            ? 'Episode ${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)}'
            : title,
        streams: const [],
        sourceUrl: url,
      );
    }
    if (episodes.isEmpty) {
      throw const FormatException('No episodes are available for this title.');
    }
    final sorted = episodes.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    final cover = doc.querySelector('.media .media-object')?.attributes['src'];
    final status = doc
        .querySelectorAll('.infoami span')
        .map((e) => e.text)
        .where((s) => s.contains('Status:'))
        .firstOrNull;
    return anime.copyWith(
      title: doc.querySelector('.media-body h1')?.text.trim(),
      description: doc.querySelector('.ptext')?.text.trim(),
      genres: [
        'Anime',
        ...doc.querySelectorAll('.tagscat a').map((e) => e.text.trim()),
      ],
      coverUrl: cover == null ? null : baseUrl.resolve(cover),
      status: status?.split('Status:').last.trim(),
      episodes: sorted,
    );
  }

  @override
  Future<List<VideoStream>> resolve(Anime anime, Episode episode) async {
    final doc = await _get(episode.sourceUrl!);
    final streams = <VideoStream>[];
    for (final frame in doc.querySelectorAll('.tab-pane iframe')) {
      final src = frame.attributes['src'];
      if (src == null || src.isEmpty) continue;
      final embedUrl = baseUrl.resolve(src);
      try {
        final embed = await _get(embedUrl);
        final script = embed
            .querySelectorAll('script')
            .map((e) => e.text)
            .where((s) => s.contains('var videoSources ='))
            .firstOrNull;
        if (script == null) continue;
        final raw = script
            .split('var videoSources =')
            .last
            .split(';')
            .first
            .trim();
        final normalized = raw.replaceAllMapped(
          RegExp(r'''(?<=[{,])\s*['"]?(\w+)['"]?\s*: '''.trimRight()),
          (m) => '"${m[1]}":',
        );
        final videos = jsonDecode(normalized) as List<dynamic>;
        final mode = frame.parent?.id.split('-').first.toUpperCase() ?? '';
        for (final value in videos) {
          final video = value as Map<String, dynamic>;
          final url = embedUrl.resolve(video['file'] as String);
          if (!['http', 'https'].contains(url.scheme)) continue;
          streams.add(
            VideoStream(
              url: url,
              label: '$mode · ${video['label'] ?? 'Auto'}',
              headers: {
                'Referer': embedUrl.origin,
                'User-Agent': 'Mozilla/5.0',
              },
            ),
          );
        }
      } on Exception {
        // A missing mirror must not hide another available language/server.
      }
    }
    if (streams.isEmpty) {
      throw const FormatException(
        'No video servers are available for this episode.',
      );
    }
    return streams;
  }

  @override
  void dispose() => _client.close();
}
