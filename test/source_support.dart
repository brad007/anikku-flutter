import 'dart:async';

import 'package:anikku/data/sources/anime_source.dart';
import 'package:anikku/domain/catalog.dart';

class FixtureSource implements AnimeSource {
  @override
  String get id => 'provider';
  @override
  String get name => 'Provider';
  int detailCalls = 0;
  int count = 2;
  bool fail = false;
  final pending = <String, Completer<SourcePage>>{};
  Anime get title => Anime(
    id: 'show',
    sourceId: id,
    title: 'Anime',
    episodes: const [],
    sourceUrl: Uri.parse('https://example.com/show'),
  );
  @override
  Future<SourcePage> browse({String query = '', int page = 1}) async {
    if (fail) throw const FormatException('Source down');
    if (query.isNotEmpty) {
      return (pending[query] = Completer<SourcePage>()).future;
    }
    return SourcePage([title], hasMore: false);
  }

  @override
  Future<Anime> details(Anime anime) async {
    detailCalls++;
    if (fail) throw const FormatException('Source down');
    return anime.copyWith(
      episodes: [
        for (var i = 1; i <= count; i++)
          Episode(
            id: '$i',
            title: 'Episode $i',
            number: i.toDouble(),
            streams: const [],
            sourceUrl: Uri.parse('https://example.com/episode/$i'),
          ),
      ],
    );
  }

  @override
  Future<List<VideoStream>> resolve(Anime anime, Episode episode) async => [
    VideoStream(url: Uri.parse('https://example.com/temporary.mp4')),
  ];
  @override
  void dispose() {}
}
