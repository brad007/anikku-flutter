import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../../domain/catalog.dart';
import 'anime_source.dart';

class AnikotoConfig {
  const AnikotoConfig({
    required this.name,
    required this.baseUrl,
    required this.episodeListTemplate,
    required this.serverListTemplate,
    required this.streamResolverTemplate,
  });

  final String name;
  final Uri baseUrl;
  final String episodeListTemplate;
  final String serverListTemplate;
  final String streamResolverTemplate;

  static AnikotoConfig? fromValues({
    required String name,
    required String baseUrl,
    required String episodeListTemplate,
    required String serverListTemplate,
    required String streamResolverTemplate,
  }) {
    final parsed = _httpsUri(baseUrl);
    if (parsed == null && baseUrl.trim().isEmpty) return null;
    if (parsed == null) {
      throw const FormatException('Anikoto source needs an HTTPS baseUrl.');
    }
    return AnikotoConfig(
      name: name.trim().isEmpty ? 'Anikoto' : name.trim(),
      baseUrl: parsed,
      episodeListTemplate: episodeListTemplate.trim().isEmpty
          ? '/ajax/episode/list/{id}'
          : episodeListTemplate.trim(),
      serverListTemplate: serverListTemplate.trim().isEmpty
          ? '/ajax/server/list?servers={episode}'
          : serverListTemplate.trim(),
      streamResolverTemplate: streamResolverTemplate.trim(),
    );
  }
}

/// Generic Anikoto-style source scaffold.
///
/// This rewrites the reusable parts of the Kotlin theme: listing pages, detail
/// pages, episode rows and a user-provided final stream resolver. It does not
/// include hoster bypass/decryption logic; provide a private resolver endpoint
/// that returns direct streams as JSON if your lawful source needs one.
class AnikotoSource implements AnimeSource {
  AnikotoSource({required this.config, http.Client? client})
    : _client = client ?? http.Client();

  final AnikotoConfig config;
  final http.Client _client;

  @override
  String get id => 'user_anikoto';

  @override
  String get name => config.name;

  Map<String, String> get _headers => {
    'User-Agent': 'Mozilla/5.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': '${config.baseUrl}/',
  };

  Future<Document> _getDocument(Uri uri) async {
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw FormatException('$name returned HTTP ${response.statusCode}.');
    }
    return html.parse(response.body)
      ..documentElement?.attributes['data-location'] = uri.toString();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {Uri? referer}) async {
    final response = await _client
        .get(
          uri,
          headers: {
            ..._headers,
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest',
            if (referer != null) 'Referer': referer.toString(),
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw FormatException('$name returned HTTP ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<SourcePage> browse({String query = '', int page = 1}) async {
    final uri = query.trim().isEmpty
        ? config.baseUrl
              .resolve('/most-viewed/')
              .replace(queryParameters: {'page': '$page'})
        : config.baseUrl
              .resolve('/filter')
              .replace(
                queryParameters: {'keyword': query.trim(), 'page': '$page'},
              );
    final doc = await _getDocument(uri);
    final items = doc.querySelectorAll('div.ani.items > div.item, a.item');
    final titles = <String, Anime>{};
    for (final item in items) {
      final link = item.querySelector(
        'a.name, .info .name, a[href*="/watch/"]',
      );
      final href = link?.attributes['href'] ?? item.attributes['href'];
      final title =
          link?.text.trim() ?? item.querySelector('.name')?.text.trim();
      if (href == null || title == null || title.isEmpty) continue;
      final url = config.baseUrl.resolve(href).replace(query: '');
      final cover =
          item.querySelector('img')?.attributes['data-src'] ??
          item.querySelector('img')?.attributes['src'];
      titles[url.path] = Anime(
        id: url.path,
        sourceId: id,
        title: title,
        sourceUrl: url,
        coverUrl: cover == null ? null : config.baseUrl.resolve(cover),
        genres: const ['Anime'],
        episodes: const [],
      );
    }
    return SourcePage(
      titles.values.toList(),
      hasMore:
          doc.querySelector('nav > ul.pagination > li.active ~ li') != null,
    );
  }

  @override
  Future<Anime> details(Anime anime) async {
    final sourceUrl = anime.sourceUrl;
    if (sourceUrl == null) {
      throw const FormatException('Title has no source URL.');
    }
    final doc = await _getDocument(sourceUrl);
    final title = doc.querySelector('h1.title, h2.title')?.text.trim();
    final sourceId =
        doc.querySelector('[data-id]')?.attributes['data-id'] ??
        doc.querySelector('[data-tip]')?.attributes['data-tip'];
    final cover =
        doc
            .querySelector('.poster img, img.film-poster-img')
            ?.attributes['data-src'] ??
        doc
            .querySelector('.poster img, img.film-poster-img')
            ?.attributes['src'];
    final episodes = sourceId == null || sourceId.isEmpty
        ? <Episode>[]
        : await _episodes(sourceId, sourceUrl);
    if (episodes.isEmpty) {
      throw const FormatException('No episodes are available for this title.');
    }
    return anime.copyWith(
      title: title?.isEmpty == false ? title : anime.title,
      description: doc
          .querySelector('.description, .synopsis, .content')
          ?.text
          .trim(),
      coverUrl: cover == null ? null : config.baseUrl.resolve(cover),
      genres: [
        'Anime',
        ...doc
            .querySelectorAll(
              'div:contains(Genres) > span > a, a[href*="genre"]',
            )
            .map((e) => e.text.trim()),
      ],
      status: doc.querySelector('div:contains(Status) > span')?.text.trim(),
      episodes: episodes,
    );
  }

  Future<List<Episode>> _episodes(String sourceId, Uri referer) async {
    final uri = _templateUri(config.episodeListTemplate, {'id': sourceId});
    final json = await _getJson(uri, referer: referer);
    final document = _htmlPayload(json);
    final rows = document.querySelectorAll(
      'div.episodes ul > li > a, a[data-num]',
    );
    final episodes = <Episode>[];
    for (final row in rows) {
      final numberText = row.attributes['data-num'] ?? row.text;
      final number =
          double.tryParse(
            RegExp(r'\d+(?:\.\d+)?').firstMatch(numberText)?.group(0) ?? '',
          ) ??
          (episodes.length + 1).toDouble();
      final ids =
          row.attributes['data-ids'] ??
          row.attributes['data-id'] ??
          row.attributes['href'] ??
          '';
      if (ids.isEmpty) {
        continue;
      }
      final title = row.parent?.querySelector('span.d-title')?.text.trim();
      final epPath =
          '${referer.path}/ep-${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)}';
      episodes.add(
        Episode(
          id: ids,
          title: title == null || title.isEmpty
              ? 'Episode ${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)}'
              : title,
          number: number,
          streams: const [],
          sourceUrl: config.baseUrl.resolve(epPath),
        ),
      );
    }
    episodes.sort(compareEpisodeOrder);
    return episodes;
  }

  @override
  Future<List<VideoStream>> resolve(Anime anime, Episode episode) async {
    if (config.streamResolverTemplate.isEmpty) {
      throw const FormatException(
        'This Anikoto-style source needs ANIKKU_ANIKOTO_STREAM_RESOLVER_TEMPLATE.',
      );
    }
    final resolver = _templateUri(config.streamResolverTemplate, {
      'episode': episode.id,
      'epurl': Uri.encodeComponent(episode.sourceUrl?.path ?? ''),
    });
    final json = await _getJson(resolver, referer: episode.sourceUrl);
    final streams = (json['streams'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_streamFromJson)
        .whereType<VideoStream>()
        .toList();
    if (streams.isEmpty) {
      throw const FormatException('No playable streams were returned.');
    }
    return streams;
  }

  VideoStream? _streamFromJson(Map<String, dynamic> json) {
    final url = _httpsUri('${json['url'] ?? json['file'] ?? ''}');
    if (url == null) return null;
    return VideoStream(
      url: url,
      label: '${json['label'] ?? 'Auto'}',
      headers: {
        'Referer': '${json['referer'] ?? config.baseUrl.origin}',
        'User-Agent': 'Mozilla/5.0',
      },
    );
  }

  Document _htmlPayload(Map<String, dynamic> json) {
    final htmlPayload =
        '${json['result'] ?? json['html'] ?? json['data'] ?? ''}';
    return html.parse(htmlPayload);
  }

  Uri _templateUri(String template, Map<String, String> values) {
    var output = template;
    for (final entry in values.entries) {
      output = output.replaceAll('{${entry.key}}', entry.value);
    }
    return output.startsWith('http')
        ? Uri.parse(output)
        : config.baseUrl.resolve(output);
  }

  @override
  void dispose() => _client.close();
}

Uri? _httpsUri(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.scheme != 'https') return null;
  return uri;
}
