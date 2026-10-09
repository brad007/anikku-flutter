import 'dart:io';

import 'package:anikku/data/download_manager.dart';
import 'package:anikku/data/library_model.dart';
import 'package:anikku/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  late Directory folder;
  late HttpServer server;
  late DownloadManager manager;
  late Anime anime;
  var requests = 0;
  var mode = 'ok';
  Future<void> finish() async {
    for (var i = 0; i < 300; i++) {
      if (manager.entries.every(
        (e) =>
            e.status == DownloadStatus.complete ||
            e.status == DownloadStatus.failed,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Download did not settle');
  }

  setUp(() async {
    requests = 0;
    mode = 'ok';
    folder = await Directory.systemTemp.createTemp('anikku-download-test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      if (mode == 'error') {
        request.response.statusCode = 503;
        await request.response.close();
        return;
      }
      if (mode == 'page') {
        request.response.headers.contentType = ContentType.html;
        request.response.write('not a movie');
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType('video', 'mp4');
      if (mode != 'chunked') request.response.contentLength = 1024;
      if (mode == 'slow') {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      try {
        request.response.add(List.filled(1024, 42));
        await request.response.close();
      } catch (_) {
        /* cancellation closes the socket */
      }
    });
    anime = Anime(
      id: 'one',
      sourceId: 'test',
      title: 'Offline story',
      episodes: [
        for (var i = 1; i <= 2; i++)
          Episode(
            id: '$i',
            title: 'Episode $i',
            number: i.toDouble(),
            streams: [
              VideoStream(
                url: Uri.parse('http://127.0.0.1:${server.port}/$i.mp4'),
              ),
            ],
          ),
      ],
    );
    manager = DownloadManager(directory: () async => folder);
    await manager.initialize();
  });
  tearDown(() async {
    manager.dispose();
    await server.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await folder.delete(recursive: true);
  });

  test(
    'downloads atomically, restores index and plays from local file',
    () async {
      manager.enqueue(anime, anime.episodes.first);
      await finish();
      final file = await manager.localFile(anime, anime.episodes.first);
      expect(await file!.readAsBytes(), List.filled(1024, 42));
      expect(manager.usedBytes, 1024);
      expect(
        await manager.localFile(
          anime,
          anime.episodes.first,
          streamUrl: Uri.parse('https://example.com/other-quality.mp4'),
        ),
        isNull,
      );
      final restored = DownloadManager(directory: () async => folder);
      await restored.initialize();
      expect(restored.entries.single.status, DownloadStatus.complete);
      expect(await restored.localFile(anime, anime.episodes.first), isNotNull);
      restored.dispose();
    },
  );
  test('automatic scheduling is opt in and deduplicates jobs', () async {
    final jobs = [(anime: anime, episode: anime.episodes.first)];
    manager.schedule(jobs);
    expect(manager.entries, isEmpty);
    await manager.setAutomatic(true);
    manager.schedule(jobs);
    manager.schedule(jobs);
    await finish();
    expect(requests, 1);
  });
  test('queued downloads persist and resume on the next launch', () async {
    mode = 'slow';
    manager.enqueue(anime, anime.episodes.first);
    expect(
      manager.entries.single.status,
      anyOf(DownloadStatus.queued, DownloadStatus.downloading),
    );
    for (var i = 0; i < 20; i++) {
      if (await File('${folder.path}/downloads/index.json').exists()) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    manager.dispose();
    mode = 'ok';
    manager = DownloadManager(directory: () async => folder);
    await manager.initialize();
    await finish();
    expect(manager.entries.single.status, DownloadStatus.complete);
    expect(requests, greaterThanOrEqualTo(1));
  });
  test(
    'failures wait for retry and HTML masquerading as MP4 is rejected',
    () async {
      mode = 'error';
      manager.enqueue(anime, anime.episodes.first);
      await finish();
      expect(manager.entries.single.status, DownloadStatus.failed);
      await manager.setAutomatic(true);
      manager.schedule([(anime: anime, episode: anime.episodes.first)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests, 1);
      mode = 'page';
      manager.enqueue(anime, anime.episodes.first);
      await finish();
      expect(manager.entries.single.error, contains('page or playlist'));
      mode = 'ok';
      manager.enqueue(anime, anime.episodes.first);
      await finish();
      expect(manager.entries.single.status, DownloadStatus.complete);
    },
  );
  test(
    'cancel removes partial download and does not requeue automatically',
    () async {
      mode = 'slow';
      await manager.setAutomatic(true);
      manager.schedule([(anime: anime, episode: anime.episodes.first)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await manager.remove(manager.entries.single);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      manager.schedule([(anime: anime, episode: anime.episodes.first)]);
      expect(manager.entries, isEmpty);
      expect(
        await folder
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .toList(),
        isEmpty,
      );
    },
  );
  test(
    'purged cache file falls back to streaming without stale ready status',
    () async {
      manager.enqueue(anime, anime.episodes.first);
      await finish();
      await (await manager.localFile(anime, anime.episodes.first))!.delete();
      expect(await manager.localFile(anime, anime.episodes.first), isNull);
      expect(manager.entries, isEmpty);
    },
  );
  test(
    'removing a completed download frees storage and persists dismissal',
    () async {
      await manager.setAutomatic(true);
      manager.enqueue(anime, anime.episodes.first);
      await finish();
      await manager.remove(manager.entries.single);
      expect(manager.usedBytes, 0);
      final restored = DownloadManager(directory: () async => folder);
      await restored.initialize();
      restored.schedule([(anime: anime, episode: anime.episodes.first)]);
      expect(restored.entries, isEmpty);
      restored.dispose();
    },
  );
  test('startup removes interrupted and unindexed video files', () async {
    final downloadsFolder = Directory('${folder.path}/downloads');
    await File('${downloadsFolder.path}/123.mp4.part').writeAsBytes([1, 2]);
    await File('${downloadsFolder.path}/124.mp4').writeAsBytes([1, 2]);
    await File('${downloadsFolder.path}/notes.txt').writeAsString('keep');
    final restored = DownloadManager(directory: () async => folder);
    await restored.initialize();
    expect(
      await File('${downloadsFolder.path}/123.mp4.part').exists(),
      isFalse,
    );
    expect(await File('${downloadsFolder.path}/124.mp4').exists(), isFalse);
    expect(await File('${downloadsFolder.path}/notes.txt').exists(), isTrue);
    restored.dispose();
  });
  test('HLS is streaming only', () {
    final episode = Episode(
      id: 'hls',
      title: 'Live',
      number: 1,
      streams: [VideoStream(url: Uri.parse('https://example.com/live.m3u8'))],
    );
    expect(DownloadManager.downloadable(episode), isNull);
    manager.enqueue(anime, episode);
    expect(manager.entries, isEmpty);
  });
  test('downloadable stream chooses the highest labeled resolution', () {
    final episode = Episode(
      id: 'quality',
      title: 'Quality',
      number: 1,
      streams: [
        VideoStream(
          url: Uri.parse('https://example.com/quality-480.mp4'),
          label: '480p',
        ),
        VideoStream(
          url: Uri.parse('https://example.com/quality-1080.mp4'),
          label: '1080p',
        ),
        VideoStream(
          url: Uri.parse('https://example.com/quality-720.mp4'),
          label: '720p',
        ),
      ],
    );
    expect(DownloadManager.downloadable(episode)?.label, '1080p');
  });
  test('download all queues every selected episode', () async {
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
      downloads: manager,
    );
    final queued = await model.downloadEpisodes(anime, anime.episodes);
    expect(queued, isTrue);
    expect(manager.entries.map((entry) => entry.episodeTitle), [
      'Episode 1',
      'Episode 2',
    ]);
    await finish();
    expect(requests, 2);
    expect(manager.entries.map((entry) => entry.status).toSet(), {
      DownloadStatus.complete,
    });
    // Model owns manager; avoid disposing it twice in tearDown.
    model.dispose();
    manager = DownloadManager(directory: () async => folder);
  });
  test('library completion automatically queues the next episode', () async {
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
      downloads: manager,
    );
    await model.initialize();
    await model.toggleFavorite(anime);
    await model.setAutomaticDownloads(true);
    await finish();
    expect(manager.entries.single.episodeTitle, 'Episode 1');
    await model.recordProgress(
      anime,
      anime.episodes.first,
      const Duration(seconds: 98),
      const Duration(seconds: 100),
    );
    await finish();
    expect(manager.entries, hasLength(2));
    expect(manager.entries.last.episodeTitle, 'Episode 2');
    // Model owns manager; avoid disposing it twice in tearDown.
    model.dispose();
    manager = DownloadManager(directory: () async => folder);
  });
}
