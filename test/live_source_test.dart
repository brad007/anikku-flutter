import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:anikku/data/sources/animegg_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'live provider discovers anime, episodes and a real MP4 stream',
    () async {
      HttpOverrides.global = null;
      final source = AnimeGgSource();
      try {
        final page = await source.browse();
        expect(page.titles.length, greaterThan(5));
        final search = await source.browse(query: 'Cowboy Bebop');
        expect(
          search.titles.any(
            (a) => a.title.toLowerCase().contains('cowboy bebop'),
          ),
          isTrue,
        );
        final anime = await source.details(search.titles.first);
        expect(anime.episodes, isNotEmpty);
        final streams = await source.resolve(anime, anime.episodes.first);
        expect(streams, isNotEmpty);
        final response = await http.get(
          streams.first.url,
          headers: {...streams.first.headers, 'Range': 'bytes=0-1023'},
        );
        expect(response.statusCode, 206);
        expect(response.headers['content-type'], contains('video/mp4'));
        expect(
          String.fromCharCodes(response.bodyBytes.skip(4).take(4)),
          'ftyp',
        );
        debugPrint(
          'SOURCE_VERIFIED: ${anime.title}; ${anime.episodes.length} episodes; ${streams.length} streams; MP4 bytes HTTP 206',
        );
        debugPrint('SEARCH_VERIFIED: Cowboy Bebop found');
      } finally {
        source.dispose();
      }
    },
    skip: !const bool.fromEnvironment('LIVE_SOURCE'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
