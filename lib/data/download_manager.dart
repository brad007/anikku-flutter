import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';

enum DownloadStatus { queued, downloading, complete, failed }

class EpisodeDownload {
  EpisodeDownload({
    required this.key,
    required this.title,
    required this.episodeTitle,
    required this.url,
    required this.filename,
    this.automatic = false,
    this.status = DownloadStatus.queued,
    this.bytes = 0,
  });
  final String key;
  final String title;
  final String episodeTitle;
  final Uri url;
  final String filename;
  final bool automatic;
  DownloadStatus status;
  int bytes;
  int? total;
  String? error;
  bool cancelled = false;
  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'episodeTitle': episodeTitle,
    'url': url.toString(),
    'filename': filename,
    'automatic': automatic,
    'bytes': bytes,
    'total': total,
    'status': status.name,
    'error': error,
  };
}

/// Serial progressive-file downloads. Partial files are never playable.
/// Queued and interrupted jobs are persisted and resumed when the app launches.
class DownloadManager extends ChangeNotifier {
  DownloadManager({required this.directory});
  final Future<Directory> Function() directory;
  final Map<String, EpisodeDownload> _entries = {};
  final List<({EpisodeDownload entry, VideoStream stream})> _queue = [];
  final Set<String> _dismissed = {};
  Directory? _folder;
  bool automatic = false;
  bool automaticWifiOnly = false;
  String quality = 'Highest';
  bool ready = false;
  bool _running = false;
  bool _disposed = false;
  HttpClient? _activeClient;
  EpisodeDownload? _active;
  Future<void> _writes = Future.value();
  String? error;
  List<EpisodeDownload> get entries => List.unmodifiable(_entries.values);
  int get usedBytes => entries
      .where((e) => e.status == DownloadStatus.complete)
      .fold(0, (sum, e) => sum + e.bytes);
  EpisodeDownload? entry(Anime a, Episode e) => _entries[a.episodeKey(e)];
  static bool supports(VideoStream stream) => RegExp(
    r'\.(mp4|m4v|mov)$',
    caseSensitive: false,
  ).hasMatch(stream.url.path);
  static VideoStream? downloadable(Episode e, {String quality = 'Highest'}) {
    final streams = e.streams.where(supports).toList();
    if (streams.isEmpty) return null;
    if (quality == 'Smallest') {
      return streams.reduce((a, b) {
        final preferred = preferredStream([a, b]);
        return preferred == a ? b : a;
      });
    }
    return preferredStream(streams);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final base = await directory();
      _folder = Directory('${base.path}/downloads');
      await _folder!.create(recursive: true);
      final index = File('${_folder!.path}/index.json');
      if (await index.exists()) {
        final data =
            jsonDecode(await index.readAsString()) as Map<String, dynamic>;
        automatic = data['automatic'] as bool? ?? false;
        automaticWifiOnly = data['automaticWifiOnly'] as bool? ?? false;
        quality = data['quality'] as String? ?? quality;
        _dismissed.addAll(
          (data['dismissed'] as List<dynamic>? ?? []).cast<String>(),
        );
        for (final item in data['entries'] as List<dynamic>? ?? []) {
          final m = item as Map<String, dynamic>;
          final filename = m['filename'] as String;
          if (!RegExp(r'^\d+\.(mp4|m4v|mov)$').hasMatch(filename)) continue;
          final status = DownloadStatus.values.firstWhere(
            (value) => value.name == m['status'],
            orElse: () => DownloadStatus.complete,
          );
          final file = File('${_folder!.path}/$filename');
          final bytes = m['bytes'] as int? ?? 0;
          if (status == DownloadStatus.complete &&
              (!await file.exists() ||
                  await file.length() != bytes ||
                  bytes <= 0)) {
            continue;
          }
          final e =
              EpisodeDownload(
                  key: m['key'] as String,
                  title: m['title'] as String,
                  episodeTitle: m['episodeTitle'] as String,
                  url: Uri.parse(m['url'] as String),
                  filename: filename,
                  bytes: status == DownloadStatus.complete ? bytes : 0,
                  automatic: m['automatic'] as bool? ?? false,
                  status: status == DownloadStatus.downloading
                      ? DownloadStatus.queued
                      : status,
                )
                ..total = m['total'] as int?
                ..error = m['error'] as String?;
          _entries[e.key] = e;
          if (e.status == DownloadStatus.queued) {
            _queue.add((entry: e, stream: VideoStream(url: e.url)));
          }
        }
      }
      // A crash may leave incomplete files. They are never included in the index.
      await for (final file in _folder!.list()) {
        if (file is File) {
          final name = file.uri.pathSegments.last;
          if (name.endsWith('.part') ||
              (RegExp(r'^\d+\.(mp4|m4v|mov)$').hasMatch(name) &&
                  !_entries.values.any((e) => e.filename == name))) {
            await file.delete();
          }
        }
      }
      ready = true;
      unawaited(_drain());
    } catch (_) {
      error =
          'Download storage could not be opened. Restart the app to try again.';
    }
    _notify();
  }

  Future<void> _persist() {
    if (_folder == null || _disposed) return Future.value();
    final data = jsonEncode({
      'automatic': automatic,
      'automaticWifiOnly': automaticWifiOnly,
      'quality': quality,
      'dismissed': _dismissed.toList(),
      'entries': entries.map((e) => e.toJson()).toList(),
    });
    _writes = _writes
        .then((_) async {
          final temporary = File('${_folder!.path}/index.json.tmp');
          await temporary.writeAsString(data, flush: true);
          await temporary.rename('${_folder!.path}/index.json');
        })
        .catchError((Object _) {
          error = 'Could not save download settings.';
          _notify();
        });
    return _writes;
  }

  Future<void> setAutomatic(bool enabled) async {
    automatic = enabled;
    if (!enabled) {
      for (final e in entries.where(
        (e) => e.automatic && e.status != DownloadStatus.complete,
      )) {
        e.cancelled = true;
        _entries.remove(e.key);
        if (_active == e) _activeClient?.close(force: true);
      }
    }
    await _persist();
    _notify();
  }

  Future<void> setWifiOnly(bool enabled) async {
    automaticWifiOnly = enabled;
    await _persist();
    _notify();
  }

  Future<void> setQuality(String value) async {
    quality = value;
    await _persist();
    _notify();
  }

  /// Called when the library or playback progress changes. Failed jobs wait for Retry.
  bool shouldSchedule(Anime anime, Episode episode) {
    final key = anime.episodeKey(episode);
    return !_entries.containsKey(key) && !_dismissed.contains(key);
  }

  void schedule(Iterable<({Anime anime, Episode episode})> upcoming) {
    if (!ready || !automatic || automaticWifiOnly || _disposed) return;
    for (final item in upcoming) {
      final key = item.anime.episodeKey(item.episode);
      if (_entries.containsKey(key) || _dismissed.contains(key)) continue;
      enqueue(item.anime, item.episode, automatic: true);
    }
  }

  void enqueue(Anime anime, Episode episode, {bool automatic = false}) {
    if (!ready || _disposed) return;
    final stream = downloadable(episode, quality: quality);
    if (stream == null) return;
    final key = anime.episodeKey(episode);
    final old = _entries[key];
    if (old != null && old.status != DownloadStatus.failed) return;
    _dismissed.remove(key);
    final ext = stream.url.path.split('.').last.toLowerCase();
    final e = EpisodeDownload(
      key: key,
      title: anime.title,
      episodeTitle: episode.title,
      url: stream.url,
      filename: '${DateTime.now().microsecondsSinceEpoch}.$ext',
      automatic: automatic,
    );
    _entries[key] = e;
    _queue.add((entry: e, stream: stream));
    unawaited(_persist());
    _notify();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final job = _queue.removeAt(0);
        if (job.entry.cancelled) continue;
        await _download(job.entry, job.stream);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _download(EpisodeDownload e, VideoStream stream) async {
    final file = File('${_folder!.path}/${e.filename}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _activeClient = client;
    _active = e;
    IOSink? sink;
    try {
      e.status = DownloadStatus.downloading;
      _notify();
      final request = await client
          .getUrl(stream.url)
          .timeout(const Duration(seconds: 20));
      stream.headers.forEach((key, value) => request.headers.set(key, value));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw const FormatException(
          'The server did not return a downloadable video.',
        );
      }
      final type = response.headers.contentType?.mimeType ?? '';
      if (type.contains('text') ||
          type.contains('json') ||
          type.contains('mpegurl')) {
        throw const FormatException(
          'This URL returned a page or playlist instead of a video file.',
        );
      }
      e.total = response.contentLength > 0 ? response.contentLength : null;
      sink = file.openWrite();
      var lastUpdate = DateTime.now();
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (e.cancelled || _disposed) throw const FormatException('Cancelled');
        sink.add(chunk);
        // Apply backpressure so long movies do not accumulate in memory.
        await sink.flush();
        e.bytes += chunk.length;
        if (DateTime.now().difference(lastUpdate).inMilliseconds > 250) {
          lastUpdate = DateTime.now();
          _notify();
        }
      }
      await sink.close();
      sink = null;
      if (e.cancelled || _disposed) throw const FormatException('Cancelled');
      if (e.bytes == 0 || (e.total != null && e.bytes != e.total)) {
        throw const FormatException('The download was incomplete. Try again.');
      }
      await file.rename('${_folder!.path}/${e.filename}');
      e.status = DownloadStatus.complete;
      await _persist();
    } catch (failure) {
      e.status = DownloadStatus.failed;
      e.error = failure is FormatException
          ? failure.message
          : 'Download interrupted. Check your connection and retry.';
      await _persist();
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        /* The error is already reported above. */
      }
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        /* Startup cleans orphaned partial files. */
      }
      client.close(force: true);
      _activeClient = null;
      _active = null;
      _notify();
    }
  }

  Future<File?> localFile(
    Anime anime,
    Episode episode, {
    Uri? streamUrl,
  }) async {
    final e = entry(anime, episode);
    if (streamUrl != null && e?.url != streamUrl) return null;
    if (e == null || e.status != DownloadStatus.complete || _folder == null) {
      return null;
    }
    final file = File('${_folder!.path}/${e.filename}');
    if (await file.exists()) return file;
    _entries.remove(e.key);
    await _persist();
    _notify();
    return null;
  }

  Future<void> remove(EpisodeDownload e) async {
    e.cancelled = true;
    _dismissed.add(e.key);
    _entries.remove(e.key);
    if (_active == e) _activeClient?.close(force: true);
    if (_folder != null && e.status == DownloadStatus.complete) {
      final file = File('${_folder!.path}/${e.filename}');
      if (await file.exists()) await file.delete();
    }
    await _persist();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _activeClient?.close(force: true);
    super.dispose();
  }
}
