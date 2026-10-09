import 'package:flutter/foundation.dart';

@immutable
class VideoStream {
  const VideoStream({
    required this.url,
    this.label = 'Auto',
    this.headers = const {},
    this.subtitles = const [],
  });
  final Uri url;
  final String label;
  final Map<String, String> headers;
  final List<SubtitleTrack> subtitles;

  factory VideoStream.fromJson(Map<String, dynamic> json) => VideoStream(
    url: networkUri(json['url'], 'stream URL'),
    label: json['label'] as String? ?? 'Auto',
    subtitles: List.unmodifiable(
      (json['subtitles'] as List<dynamic>? ?? []).map(
        (e) => SubtitleTrack.fromJson(e as Map<String, dynamic>),
      ),
    ),
    headers: Map.unmodifiable(
      (json['headers'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as String),
      ),
    ),
  );
  Map<String, dynamic> toJson() => {
    'url': url.toString(),
    'label': label,
    'headers': headers,
    'subtitles': subtitles.map((e) => e.toJson()).toList(),
  };
}

@immutable
class SubtitleTrack {
  const SubtitleTrack({
    required this.url,
    required this.label,
    this.format = 'vtt',
  });
  final Uri url;
  final String label;
  final String format;
  factory SubtitleTrack.fromJson(Map<String, dynamic> json) {
    final format = json['format'] as String? ?? 'vtt';
    if (format != 'vtt' && format != 'srt') {
      throw const FormatException('Subtitles must use vtt or srt format.');
    }
    return SubtitleTrack(
      url: networkUri(json['url'], 'subtitle URL'),
      label: requiredText(json['label'], 'subtitle label'),
      format: format,
    );
  }
  Map<String, dynamic> toJson() => {
    'url': url.toString(),
    'label': label,
    'format': format,
  };
}

@immutable
class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.number,
    required this.streams,
    this.season = 1,
    this.sourceUrl,
  });
  final String id;
  final String title;
  final double number;
  final int season;
  final List<VideoStream> streams;
  final Uri? sourceUrl;

  factory Episode.fromJson(Map<String, dynamic> json) {
    final streams = (json['streams'] as List<dynamic>)
        .map((value) => VideoStream.fromJson(value as Map<String, dynamic>))
        .toList();
    if (streams.isEmpty && json['sourceUrl'] == null) {
      throw const FormatException('Every episode needs at least one stream.');
    }
    final season = json['season'] as num? ?? 1;
    if (season < 0 || season % 1 != 0) {
      throw const FormatException('Episode season must be a whole number.');
    }
    return Episode(
      id: requiredText(json['id'], 'episode id'),
      title: requiredText(json['title'], 'episode title'),
      number: (json['number'] as num? ?? 1).toDouble(),
      season: season.toInt(),
      streams: List.unmodifiable(streams),
      sourceUrl: json['sourceUrl'] == null
          ? null
          : networkUri(json['sourceUrl'], 'episode source URL'),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'number': number,
    if (season != 1) 'season': season,
    'streams': streams.map((e) => e.toJson()).toList(),
    if (sourceUrl != null) 'sourceUrl': sourceUrl.toString(),
  };
}

int compareEpisodeOrder(Episode a, Episode b) {
  final bySeason = a.season.compareTo(b.season);
  return bySeason != 0 ? bySeason : a.number.compareTo(b.number);
}

int preferredStreamIndex(List<VideoStream> streams, {String language = 'Any'}) {
  if (streams.isEmpty) return 0;
  final normalized = language.toLowerCase();
  final candidates = [
    for (var i = 0; i < streams.length; i++)
      if (normalized == 'any' ||
          streams[i].label.toLowerCase().contains(normalized))
        i,
  ];
  final indexes = candidates.isEmpty
      ? [for (var i = 0; i < streams.length; i++) i]
      : candidates;
  var bestIndex = indexes.first;
  var bestScore = _streamResolutionScore(streams[bestIndex]);
  for (final i in indexes.skip(1)) {
    final score = _streamResolutionScore(streams[i]);
    if (score > bestScore) {
      bestIndex = i;
      bestScore = score;
    }
  }
  return bestIndex;
}

VideoStream? preferredStream(
  List<VideoStream> streams, {
  String language = 'Any',
}) => streams.isEmpty
    ? null
    : streams[preferredStreamIndex(streams, language: language)];

int _streamResolutionScore(VideoStream stream) {
  final text = '${stream.label} ${stream.url}'.toLowerCase();
  var best = -1;
  for (final match in RegExp(r'(\d{3,4})\s*p').allMatches(text)) {
    final value = int.tryParse(match.group(1)!);
    if (value != null && value > best) best = value;
  }
  for (final match in RegExp(r'(\d+(?:\.\d+)?)\s*k').allMatches(text)) {
    final value = double.tryParse(match.group(1)!);
    if (value != null) {
      final score = (value * 1000).round();
      if (score > best) best = score;
    }
  }
  if (text.contains('uhd')) best = best < 2160 ? 2160 : best;
  return best;
}

@immutable
class Anime {
  const Anime({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.episodes,
    this.description = '',
    this.coverUrl,
    this.genres = const [],
    this.year,
    this.status = 'Unknown',
    this.sourceUrl,
  });
  final String id;
  final String sourceId;
  final String title;
  final String description;
  final Uri? coverUrl;
  final Uri? sourceUrl;
  final List<String> genres;
  final int? year;
  final String status;
  final List<Episode> episodes;
  String get key => '$sourceId::$id';
  String episodeKey(Episode episode) => '$key::${episode.id}';

  Anime copyWith({
    List<Episode>? episodes,
    String? description,
    List<String>? genres,
    String? title,
    Uri? coverUrl,
    Uri? sourceUrl,
    int? year,
    String? status,
  }) => Anime(
    id: id,
    sourceId: sourceId,
    title: title ?? this.title,
    episodes: episodes ?? this.episodes,
    description: description ?? this.description,
    genres: genres ?? this.genres,
    coverUrl: coverUrl ?? this.coverUrl,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    year: year ?? this.year,
    status: status ?? this.status,
  );

  factory Anime.fromJson(Map<String, dynamic> json, String sourceId) {
    final episodes =
        (json['episodes'] as List<dynamic>)
            .map((value) => Episode.fromJson(value as Map<String, dynamic>))
            .toList()
          ..sort(compareEpisodeOrder);
    if (episodes.map((e) => e.id).toSet().length != episodes.length) {
      throw const FormatException('Episode IDs must be unique within a title.');
    }
    return Anime(
      id: requiredText(json['id'], 'title id'),
      sourceId: sourceId,
      title: requiredText(json['title'], 'title'),
      description: json['description'] as String? ?? '',
      sourceUrl: json['sourceUrl'] == null
          ? null
          : networkUri(json['sourceUrl'], 'title source URL'),
      coverUrl: json['coverUrl'] == null
          ? null
          : networkUri(json['coverUrl'], 'cover URL'),
      genres: List.unmodifiable(
        (json['genres'] as List<dynamic>? ?? []).cast<String>(),
      ),
      year: json['year'] as int?,
      status: json['status'] as String? ?? 'Unknown',
      episodes: List.unmodifiable(episodes),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    if (sourceUrl != null) 'sourceUrl': sourceUrl.toString(),
    if (coverUrl != null) 'coverUrl': coverUrl.toString(),
    'genres': genres,
    'year': year,
    'status': status,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}

@immutable
class Catalog {
  const Catalog({
    required this.id,
    required this.name,
    required this.titles,
    this.url,
    this.isSample = false,
  });
  final String id;
  final String name;
  final List<Anime> titles;
  final Uri? url;
  final bool isSample;

  factory Catalog.fromJson(
    Map<String, dynamic> json, {
    Uri? url,
    bool isSample = false,
  }) {
    if (json['version'] != 1) {
      throw const FormatException('This catalog needs version: 1.');
    }
    final id = requiredText(json['id'], 'catalog id');
    final titles = (json['titles'] as List<dynamic>)
        .map((value) => Anime.fromJson(value as Map<String, dynamic>, id))
        .toList();
    if (titles.map((e) => e.id).toSet().length != titles.length) {
      throw const FormatException('Title IDs must be unique within a catalog.');
    }
    return Catalog(
      id: id,
      name: requiredText(json['name'], 'catalog name'),
      titles: List.unmodifiable(titles),
      url: url,
      isSample: isSample,
    );
  }
  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'titles': titles.map((e) => e.toJson()).toList(),
  };
}

String requiredText(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $field.');
  }
  if (field.endsWith('id') && value.contains('::')) {
    throw FormatException('$field cannot contain ::.');
  }
  return value.trim();
}

Uri networkUri(Object? value, String field) {
  final uri = Uri.tryParse(requiredText(value, field));
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw FormatException(
      'Use an HTTP or HTTPS $field without embedded credentials.',
    );
  }
  return uri;
}
