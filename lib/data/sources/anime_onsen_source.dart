import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/catalog.dart';
import 'anime_source.dart';

class AnimeOnsenConfig {
  const AnimeOnsenConfig({
    required this.name,
    required this.baseUrl,
    required this.apiUrl,
    required this.searchUrl,
  });

  final String name;
  final Uri baseUrl;
  final Uri apiUrl;
  final Uri searchUrl;

  static AnimeOnsenConfig? fromValues({
    required String name,
    required String baseUrl,
    required String apiUrl,
    required String searchUrl,
  }) {
    final parsedBase = _httpsUri(baseUrl);
    final parsedApi = _httpsUri(apiUrl);
    final parsedSearch = _httpsUri(searchUrl);
    if (parsedBase == null && parsedApi == null && parsedSearch == null) {
      return null;
    }
    if (parsedBase == null || parsedApi == null || parsedSearch == null) {
      throw const FormatException(
        'AnimeOnsen source needs baseUrl, apiUrl and searchUrl.',
      );
    }
    return AnimeOnsenConfig(
      name: name.trim().isEmpty ? 'AnimeOnsen' : name.trim(),
      baseUrl: parsedBase,
      apiUrl: parsedApi,
      searchUrl: parsedSearch,
    );
  }
}

class AnimeOnsenSource implements AnimeSource {
  AnimeOnsenSource({required this.config, http.Client? client})
    : _client = client ?? http.Client();

  final AnimeOnsenConfig config;
  final http.Client _client;

  @override
  String get id => 'user_anime_onsen';

  @override
  String get name => config.name;

  Map<String, String> get _headers => {
    'User-Agent': 'Mozilla/5.0',
    'Accept': 'application/json, text/plain, */*',
    'Referer': '${config.baseUrl}/',
    'Origin': config.baseUrl.origin,
  };

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw FormatException('$name returned HTTP ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final response = await _client
        .post(
          uri,
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw FormatException('$name returned HTTP ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<SourcePage> browse({String query = '', int page = 1}) async {
    final search = query.trim();
    final Map<String, dynamic> json;
    if (search.isEmpty) {
      json = await _getJson(
        config.apiUrl
            .resolve('/v4/content/index')
            .replace(
              queryParameters: {
                'start': '${(page - 1).clamp(0, 9999) * 30}',
                'limit': '30',
              },
            ),
      );
    } else {
      json = await _postJson(
        config.searchUrl.resolve('/indexes/content/search'),
        {'q': search},
      );
    }
    final items =
        _list(json['hits']) ?? _list(json['content']) ?? _list(json['result']);
    final titles = [
      for (final item in items ?? const [])
        if (item is Map<String, dynamic>) _animeFromItem(item),
    ];
    final next = json['cursor'] is Map<String, dynamic>
        ? ((json['cursor'] as Map<String, dynamic>)['next'] as List<dynamic>? ??
                  const [])
              .isNotEmpty
        : titles.length == 30;
    return SourcePage(titles, hasMore: next);
  }

  Anime _animeFromItem(Map<String, dynamic> item) {
    final id = _text(item['content_id']) ?? _text(item['id']) ?? '';
    final title = _title(item) ?? id;
    return Anime(
      id: id,
      sourceId: this.id,
      title: title,
      coverUrl: id.isEmpty
          ? null
          : config.apiUrl.resolve('/v4/image/210x300/$id'),
      sourceUrl: id.isEmpty ? null : config.baseUrl.resolve('/details/$id'),
      genres: const ['Anime'],
      episodes: const [],
    );
  }

  @override
  Future<Anime> details(Anime anime) async {
    final id = anime.id;
    final details = await _getJson(
      config.apiUrl.resolve('/v4/content/$id/extensive'),
    );
    final episodesJson = await _getJson(
      config.apiUrl.resolve('/v4/content/$id/episodes'),
    );
    final episodes = <Episode>[];
    for (final entry in episodesJson.entries) {
      final number =
          double.tryParse(entry.key) ?? (episodes.length + 1).toDouble();
      final item = entry.value is Map<String, dynamic>
          ? entry.value as Map<String, dynamic>
          : const <String, dynamic>{};
      episodes.add(
        Episode(
          id: '$id/video/${entry.key}',
          title: _episodeTitle(entry.key, item),
          number: number,
          streams: const [],
          sourceUrl: config.apiUrl.resolve(
            '/v4/content/$id/video/${entry.key}',
          ),
        ),
      );
    }
    episodes.sort(compareEpisodeOrder);
    if (episodes.isEmpty) {
      throw const FormatException('No episodes are available for this title.');
    }
    final mal = details['mal_data'] is Map<String, dynamic>
        ? details['mal_data'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return anime.copyWith(
      title: _title(details) ?? anime.title,
      description: _text(mal['synopsis']) ?? anime.description,
      coverUrl: config.apiUrl.resolve('/v4/image/210x300/$id'),
      genres: [
        'Anime',
        for (final genre in _list(mal['genres']) ?? const [])
          if (genre is Map<String, dynamic> && _text(genre['name']) != null)
            _text(genre['name'])!,
      ],
      status: _status(_text(mal['status'])),
      episodes: episodes,
    );
  }

  @override
  Future<List<VideoStream>> resolve(Anime anime, Episode episode) async {
    final uri = episode.sourceUrl;
    if (uri == null) throw const FormatException('Episode has no source URL.');
    final data = await _getJson(uri);
    final uriJson = data['uri'] is Map<String, dynamic>
        ? data['uri'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final stream = _httpsUri('${uriJson['stream'] ?? ''}');
    if (stream == null) {
      throw const FormatException('No playable stream was returned.');
    }
    final metadata = data['metadata'] is Map<String, dynamic>
        ? data['metadata'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final subtitleNames = metadata['subtitles'] is Map<String, dynamic>
        ? metadata['subtitles'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final subtitleUrls = uriJson['subtitles'] is Map<String, dynamic>
        ? uriJson['subtitles'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return [
      VideoStream(
        url: stream,
        label: 'Default',
        headers: _headers,
        subtitles: [
          for (final entry in subtitleUrls.entries)
            if (_httpsUri('${entry.value}') != null)
              SubtitleTrack(
                url: _httpsUri('${entry.value}')!,
                label: '${subtitleNames[entry.key] ?? entry.key}',
                format: '${entry.value}'.toLowerCase().endsWith('.srt')
                    ? 'srt'
                    : 'vtt',
              ),
        ],
      ),
    ];
  }

  String _episodeTitle(String number, Map<String, dynamic> item) {
    final name = _text(item['nameEn']) ?? _text(item['nameJp']) ?? '';
    return name.isEmpty ? 'Episode $number' : 'Episode $number: $name';
  }

  String? _title(Map<String, dynamic> item) =>
      _text(item['content_title_en']) ??
      _text(item['content_title']) ??
      _text(item['content_title_jp']) ??
      _text(item['title']);

  String _status(String? status) =>
      status == 'finished_airing' ? 'Completed' : 'Ongoing';

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

String? _text(Object? value) {
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}

List<dynamic>? _list(Object? value) => value is List<dynamic> ? value : null;
