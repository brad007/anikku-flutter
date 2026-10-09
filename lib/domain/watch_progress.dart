import 'package:flutter/foundation.dart';

@immutable
class WatchProgress {
  const WatchProgress({
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.watched = false,
  });
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;
  final bool watched;
  double get fraction =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1);
  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
    positionMs: (json['positionMs'] as int).clamp(0, 1 << 53),
    durationMs: (json['durationMs'] as int).clamp(0, 1 << 53),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    watched: json['watched'] as bool? ?? false,
  );
  Map<String, dynamic> toJson() => {
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt.toIso8601String(),
    'watched': watched,
  };
}
