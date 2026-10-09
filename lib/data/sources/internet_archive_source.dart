import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/catalog.dart';
import 'anime_source.dart';

/// Internet Archive video source for public archive items with direct MP4 files.
class InternetArchiveSource implements AnimeSource {
  InternetArchiveSource({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? Uri.parse('https://archive.org');

  final http.Client _client;
  final Uri baseUrl;

  @override
  String get id => 'internet_archive';

  @override
  String get name => 'Internet Archive';

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw FormatException('$name returned HTTP ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<SourcePage> browse({String query = '', int page = 1}) async {
    final search = query.trim();
    final archiveQuery = search.isEmpty
        ? 'mediatype:movies AND (subject:anime OR title:anime OR description:anime)'
        : 'mediatype:movies AND ($search)';
    final uri = baseUrl
        .resolve('/advancedsearch.php')
        .replace(
          queryParameters: {
            'q': archiveQuery,
            'fl[]': [
              'identifier',
              'title',
              'description',
              'date',
              'year',
              'licenseurl',
              'downloads',
            ],
            'sort[]': ['downloads desc', 'titleSorter asc'],
            'rows': '40',
            'page': '$page',
            'output': 'json',
          },
        );
    final json = await _json(uri);
    final response = json['response'] as Map<String, dynamic>?;
    final docs = (response?['docs'] as List<dynamic>? ?? const []);
    return SourcePage([
      for (final doc in docs)
        if (doc case final Map<String, dynamic> item) _animeFromSearchDoc(item),
    ], hasMore: docs.length == 40);
  }

  Anime _animeFromSearchDoc(Map<String, dynamic> item) {
    final identifier = '${item['identifier'] ?? ''}'.trim();
    final title = '${item['title'] ?? identifier}'.trim();
    return Anime(
      id: identifier,
      sourceId: id,
      title: title.isEmpty ? identifier : title,
      description: _plainText(item['description']),
      coverUrl: identifier.isEmpty
          ? null
          : baseUrl.resolve('/services/img/$identifier'),
      sourceUrl: identifier.isEmpty
          ? null
          : baseUrl.resolve('/details/$identifier'),
      genres: const ['Anime', 'Archive'],
      year: _year(item['year']) ?? _year(item['date']),
      status: 'Archive',
      episodes: const [],
    );
  }

  @override
  Future<Anime> details(Anime anime) async {
    final identifier = anime.id;
    final json = await _json(baseUrl.resolve('/metadata/$identifier'));
    final metadata = json['metadata'] as Map<String, dynamic>? ?? const {};
    final files =
        (json['files'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .where(_isVideoFile)
            .toList()
          ..sort(_compareArchiveFiles);
    if (files.isEmpty) {
      throw const FormatException('No playable MP4 files are available.');
    }
    return anime.copyWith(
      title: _metadataText(metadata['title']) ?? anime.title,
      description: _plainText(metadata['description']) == ''
          ? anime.description
          : _plainText(metadata['description']),
      year: _year(metadata['year']) ?? _year(metadata['date']) ?? anime.year,
      status: 'Archive',
      genres: const ['Anime', 'Archive'],
      episodes: [
        for (var i = 0; i < files.length; i++)
          Episode(
            id: _fileName(files[i]),
            title: _episodeTitle(files[i], i + 1),
            number: (i + 1).toDouble(),
            streams: [
              for (final file in _streamsForFile(identifier, files[i]))
                VideoStream(
                  url: file.url,
                  label: file.label,
                  headers: {
                    'Referer': baseUrl
                        .resolve('/details/$identifier')
                        .toString(),
                  },
                ),
            ],
            sourceUrl: baseUrl.resolve(
              '/download/$identifier/${Uri.encodeComponent(_fileName(files[i]))}',
            ),
          ),
      ],
    );
  }

  @override
  Future<List<VideoStream>> resolve(Anime anime, Episode episode) async =>
      episode.streams;

  Iterable<({Uri url, String label})> _streamsForFile(
    String identifier,
    Map<String, dynamic> file,
  ) sync* {
    final name = _fileName(file);
    final label = '${file['format'] ?? 'MP4'} · ${_sizeLabel(file['size'])}';
    yield (
      url: baseUrl.resolve(
        '/download/$identifier/${Uri.encodeComponent(name)}',
      ),
      label: label,
    );
  }

  bool _isVideoFile(Map<String, dynamic> file) {
    final name = _fileName(file).toLowerCase();
    final format = '${file['format'] ?? ''}'.toLowerCase();
    return (name.endsWith('.mp4') ||
            name.endsWith('.m4v') ||
            format.contains('mpeg4') ||
            format.contains('h.264')) &&
        !name.contains('_thumb') &&
        !name.contains('sample');
  }

  int _compareArchiveFiles(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aName = _fileName(a);
    final bName = _fileName(b);
    final aEpisode = _episodeNumber(aName);
    final bEpisode = _episodeNumber(bName);
    if (aEpisode != null && bEpisode != null && aEpisode != bEpisode) {
      return aEpisode.compareTo(bEpisode);
    }
    final quality = _qualityRank(b).compareTo(_qualityRank(a));
    if (quality != 0) return quality;
    return aName.compareTo(bName);
  }

  int _qualityRank(Map<String, dynamic> file) {
    final text = '${file['name']} ${file['format']}'.toLowerCase();
    if (text.contains('h.264')) return 4;
    if (text.contains('mpeg4')) return 3;
    if (text.contains('512kb')) return 1;
    return 2;
  }

  double? _episodeNumber(String name) {
    final match = RegExp(
      r'(?:^|[^a-z0-9])(?:e|ep|episode)?\s*(\d{1,4})(?:[^a-z0-9]|$)',
      caseSensitive: false,
    ).firstMatch(name);
    return double.tryParse(match?.group(1) ?? '');
  }

  String _episodeTitle(Map<String, dynamic> file, int fallback) {
    final title = _metadataText(file['title']);
    if (title != null && title.isNotEmpty) return title;
    final name = _fileName(file)
        .split('/')
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    return name.isEmpty
        ? 'Video $fallback'
        : name.replaceAll(RegExp(r'[_-]+'), ' ');
  }

  String _fileName(Map<String, dynamic> file) => '${file['name'] ?? ''}'.trim();

  String? _metadataText(Object? value) {
    if (value is List && value.isNotEmpty) return '${value.first}'.trim();
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  int? _year(Object? value) {
    final text = _metadataText(value) ?? '$value';
    final match = RegExp(r'(19|20)\d{2}').firstMatch(text);
    return int.tryParse(match?.group(0) ?? '');
  }

  String _plainText(Object? value) => (_metadataText(value) ?? '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _sizeLabel(Object? value) {
    final bytes = int.tryParse('$value') ?? 0;
    if (bytes <= 0) return 'MP4';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  void dispose() => _client.close();
}
