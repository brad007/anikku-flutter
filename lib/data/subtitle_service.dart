import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../domain/catalog.dart';

class SubtitleService {
  Future<ClosedCaptionFile> load(SubtitleTrack track) async {
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', track.url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw FormatException(
          'Subtitle server returned HTTP ${response.statusCode}.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Subtitle file exceeds 2 MB.');
        }
      }
      return parse(utf8.decode(bytes), track.format);
    } finally {
      client.close();
    }
  }

  ClosedCaptionFile parse(String text, String format) =>
      format == 'srt' ? SubRipCaptionFile(text) : WebVTTCaptionFile(text);
}
