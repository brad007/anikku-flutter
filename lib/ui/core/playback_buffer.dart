import 'package:video_player/video_player.dart';

/// Only count media reachable from the playhead; a later cached range may have
/// a gap after a seek and must not satisfy the startup buffer.
Duration bufferedThrough(VideoPlayerValue value) {
  var end = value.position.inMilliseconds;
  final ranges = [...value.buffered]
    ..sort((a, b) => a.start.compareTo(b.start));
  for (final range in ranges) {
    // Audio/video timestamps can start a frame after the requested position
    // (for example 83 ms at the start of an MP4). Ignore tiny clock gaps.
    if (range.start.inMilliseconds > end + 100) break;
    if (range.end.inMilliseconds > end) end = range.end.inMilliseconds;
  }
  return Duration(milliseconds: end.clamp(0, value.duration.inMilliseconds));
}

Duration bufferedAhead(VideoPlayerValue value) {
  final milliseconds =
      bufferedThrough(value).inMilliseconds - value.position.inMilliseconds;
  return Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
}
