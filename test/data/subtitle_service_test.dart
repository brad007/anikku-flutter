import 'package:anikku/data/subtitle_service.dart';
import 'package:anikku/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SRT and VTT captions preserve timing and Unicode text', () {
    final service = SubtitleService();
    final srt = service.parse(
      '1\n00:00:01,000 --> 00:00:03,000\nこんにちは\n\n',
      'srt',
    );
    final vtt = service.parse(
      'WEBVTT\n\n00:01.000 --> 00:03.000\nHello world\n\n',
      'vtt',
    );
    expect(srt.captions.single.text, 'こんにちは');
    expect(srt.captions.single.start.inSeconds, 1);
    expect(vtt.captions.single.text, 'Hello world');
    expect(vtt.captions.single.end.inSeconds, 3);
  });
  test('subtitle tracks roundtrip and reject unsupported formats', () {
    final stream = VideoStream.fromJson({
      'url': 'https://example.com/video.mp4',
      'subtitles': [
        {
          'url': 'https://example.com/en.vtt',
          'label': 'English',
          'format': 'vtt',
        },
      ],
    });
    expect(
      VideoStream.fromJson(stream.toJson()).subtitles.single.label,
      'English',
    );
    expect(
      () => SubtitleTrack.fromJson({
        'url': 'https://example.com/sub.ass',
        'label': 'English',
        'format': 'ass',
      }),
      throwsFormatException,
    );
  });
}
