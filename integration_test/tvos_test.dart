import 'dart:io';
import 'dart:convert';

import 'package:anikku/data/catalog_service.dart';
import 'package:anikku/data/download_manager.dart';
import 'package:anikku/domain/catalog.dart';

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:anikku/data/library_model.dart';
import 'package:anikku/data/library_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:anikku/ui/app.dart';
import 'package:anikku/ui/core/theme.dart';
import 'package:anikku/ui/screens/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../test/support.dart';

Future<void> saveEvidence(GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final folder = await getTemporaryDirectory();
  await File('${folder.path}/$name.png')
      .writeAsBytes(bytes!.buffer.asUint8List());
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![name] = base64Encode(bytes.buffer.asUint8List());
  binding.reportData!['platform'] = Platform.operatingSystem;
  image.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Let the tvOS engine enable native focus semantics before test baselines.
  setUpAll(() async {
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  testWidgets('native preferences persist and reload on the target', (
    tester,
  ) async {
    debugPrint('NATIVE_PLATFORM: ${Platform.operatingSystem}');
    final prefs = await SharedPreferences.getInstance();
    const key = 'anikku.integration_test.probe';
    expect(await prefs.setString(key, 'tvOS persistence probe'), isTrue);
    await prefs.reload();
    expect(prefs.getString(key), 'tvOS persistence probe');
    await prefs.remove(key);
  });

  testWidgets('native cache file store roundtrips a library', (tester) async {
    final cache = await getApplicationCacheDirectory();
    final directory = Directory('${cache.path}/anikku-integration-test');
    final store = FileStateStore(directory: () async => directory);
    try {
      await store.write({'version': 1, 'probe': 'native storage'});
      expect((await store.read())!['probe'], 'native storage');
      await store.write({'version': 1, 'probe': 'replaced atomically'});
      expect((await store.read())!['probe'], 'replaced atomically');
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
  testWidgets('TV browse, library save and remote back', (tester) async {
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
    );
    await model.initialize();
    final evidenceKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceKey,
        child: AnikkuApp(model: model),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(
      Platform.isMacOS ? LogicalKeyboardKey.enter : LogicalKeyboardKey.select,
    );
    await tester.pumpAndSettle();
    expect(find.text('Bring your favorite stories together.'), findsOneWidget);
    await saveEvidence(evidenceKey, 'tvos-browse');
    await tester.tap(find.byKey(const ValueKey('title-samples::one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to My List'));
    await tester.pumpAndSettle();
    expect(model.library, hasLength(1));
    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
      platform: 'android',
    );
    await tester.pumpAndSettle();
    expect(find.text('Bring your favorite stories together.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('native AVPlayer initializes, plays, pauses and seeks', (
    tester,
  ) async {
    final controller = VideoPlayerController.asset('assets/test/playback.mp4');
    await controller.initialize().timeout(const Duration(seconds: 25));
    expect(controller.value.size.width, greaterThan(0));
    expect(controller.value.duration.inSeconds, greaterThanOrEqualTo(10));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
    await controller.play();
    await tester.pump(const Duration(seconds: 2));
    final position = await controller.position;
    expect(position!.inMilliseconds, greaterThan(0));
    await controller.pause();
    expect(controller.value.isPlaying, isFalse);
    await controller.seekTo(const Duration(seconds: 6));
    expect((await controller.position)!.inSeconds, greaterThanOrEqualTo(5));
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });

  testWidgets('player UI saves progress and resumes on Apple TV', (
    tester,
  ) async {
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
    );
    await model.initialize();
    final anime = model.titles.first;
    final episode = anime.episodes.first;
    await model.recordProgress(
      anime,
      episode,
      const Duration(seconds: 3),
      const Duration(seconds: 12),
    );
    final evidenceKey = GlobalKey();
    VideoPlayerController? player;
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceKey,
        child: MaterialApp(
          theme: anikkuTheme(),
          home: PlayerScreen(
            model: model,
            anime: anime,
            episode: episode,
            controllerFactory: (_) => player = VideoPlayerController.asset(
              'assets/test/playback.mp4',
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 100 && !(player?.value.isInitialized ?? false); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(player!.value.isInitialized, isTrue);
    expect(player!.value.position.inSeconds, greaterThanOrEqualTo(3));
    await tester.pump(const Duration(milliseconds: 250));
    await saveEvidence(evidenceKey, 'tvos-playback');
    await tester.tap(find.text('Hide controls'));
    await tester.pump();
    expect(find.text('Pause'), findsNothing);
    await tester.sendKeyEvent(
      Platform.isMacOS ? LogicalKeyboardKey.enter : LogicalKeyboardKey.select,
    );
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    // After reveal the primary action must receive focus for remote Select.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(
      Platform.isMacOS ? LogicalKeyboardKey.enter : LogicalKeyboardKey.select,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(player!.value.isPlaying, isFalse);
    expect(
      model.progress(anime, episode)!.positionMs,
      greaterThanOrEqualTo(3000),
    );
    await tester.sendKeyEvent(
      LogicalKeyboardKey.mediaPlayPause,
      physicalKey: PhysicalKeyboardKey.mediaPlayPause,
      platform: 'android',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(player!.value.isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    model.dispose();
  });

  testWidgets(
    'automatic download is playable from Downloads with source offline',
    (tester) async {
      final folder = await Directory.systemTemp.createTemp('anikku-offline-ui');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = (await rootBundle.load('assets/test/playback.mp4')).buffer
          .asUint8List();
      server.listen((request) async {
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      final manager = DownloadManager(directory: () async => folder);
      final model = LibraryModel(
        store: MemoryStore(),
        catalogs: FixtureCatalogService(),
        downloads: manager,
      );
      try {
        await model.initialize();
        final anime = Anime(
          id: 'offline',
          sourceId: 'test',
          title: 'Offline playback test',
          episodes: [
            Episode(
              id: 'one',
              title: 'Locally downloaded test clip',
              number: 1,
              streams: [
                VideoStream(
                  url: Uri.parse('http://127.0.0.1:${server.port}/clip.mp4'),
                ),
              ],
            ),
          ],
        );
        await model.toggleFavorite(anime);
        await model.setAutomaticDownloads(true);
        for (
          var i = 0;
          i < 200 && manager.entries.single.status != DownloadStatus.complete;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(manager.entries.single.status, DownloadStatus.complete);
        await server.close(force: true);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: AnikkuApp(model: model),
          ),
        );
        await tester.pumpAndSettle();
        final nav = find.byKey(const ValueKey('nav-6'));
        await tester.ensureVisible(nav);
        await tester.tap(nav);
        await tester.pumpAndSettle();
        expect(find.text('Automatic downloads · On'), findsOneWidget);
        await saveEvidence(key, 'tvos-downloads');
        await tester.tap(find.text('Play offline'));
        for (
          var i = 0;
          i < 100 && find.byType(VideoPlayer).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(seconds: 1));
        final player = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        expect(player.dataSourceType, DataSourceType.file);
        expect(player.value.isPlaying, isTrue);
        await tester.tap(find.text('Pause'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          model.progress(anime, anime.episodes.first)!.positionMs,
          greaterThan(0),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        await server.close(force: true);
        model.dispose();
        await folder.delete(recursive: true);
      }
    },
  );

  testWidgets('real bundled catalog renders on Apple TV', (tester) async {
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: CatalogService(),
    );
    await model.initialize();
    expect(model.titles, hasLength(4));
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AnikkuApp(model: model),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await saveEvidence(key, 'tvos-home');
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await saveEvidence(key, 'tvos-catalog');
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  if (const bool.fromEnvironment('TEST_NETWORK')) {
    testWidgets('real anime streams, downloads and plays offline', (
      tester,
    ) async {
      final folder = await Directory.systemTemp.createTemp(
        'anikku-native-download',
      );
      final downloads = DownloadManager(directory: () async => folder);
      final service = CatalogService();
      final catalog = await service.sample();
      final anime = catalog.titles.firstWhere((a) => a.id == 'namakura-gatana');
      final episode = anime.episodes.single;
      final online = VideoPlayerController.networkUrl(
        episode.streams.first.url,
      );
      final key = GlobalKey();
      VideoPlayerController? offline;
      try {
        await online.initialize().timeout(const Duration(seconds: 45));
        expect(online.value.duration.inSeconds, greaterThan(200));
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              home: Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: AspectRatio(
                    aspectRatio: online.value.aspectRatio,
                    child: VideoPlayer(online),
                  ),
                ),
              ),
            ),
          ),
        );
        await online.seekTo(const Duration(seconds: 35));
        await online.play();
        await tester.pump(const Duration(seconds: 3));
        expect((await online.position)!.inSeconds, greaterThan(35));
        expect(online.value.size.width, greaterThan(0));
        await saveEvidence(key, 'tvos-anime');
        await online.pause();
        await downloads.initialize();
        await downloads.setAutomatic(true);
        downloads.schedule([(anime: anime, episode: episode)]);
        for (
          var i = 0;
          i < 1800 &&
              downloads.entries.single.status != DownloadStatus.complete &&
              downloads.entries.single.status != DownloadStatus.failed;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          downloads.entries.single.status,
          DownloadStatus.complete,
          reason: downloads.entries.single.error,
        );
        final local = await downloads.localFile(anime, episode);
        expect(local, isNotNull);
        offline = VideoPlayerController.file(local!);
        await offline.initialize().timeout(const Duration(seconds: 25));
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: VideoPlayer(offline))),
        );
        await offline.seekTo(const Duration(seconds: 35));
        await offline.play();
        await tester.pump(const Duration(seconds: 2));
        expect((await offline.position)!.inSeconds, greaterThan(35));
        expect(offline.dataSourceType, DataSourceType.file);
        debugPrint(
          'ANIME_VERIFIED: ${anime.title}; online duration=${online.value.duration}; downloaded=${downloads.usedBytes} bytes; offline playback advanced',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await online.dispose();
        await offline?.dispose();
        downloads.dispose();
        service.dispose();
        await folder.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 4)));

    testWidgets('HTTPS playback uses a real remote MP4', (tester) async {
      final player = VideoPlayerController.networkUrl(
        Uri.parse('https://media.w3.org/2010/05/bunny/trailer.mp4'),
      );
      try {
        await player.initialize().timeout(const Duration(seconds: 30));
        await player.play();
        await tester.pump(const Duration(seconds: 2));
        expect((await player.position)!.inMilliseconds, greaterThan(0));
        expect(player.value.size.width, greaterThan(0));
      } finally {
        await player.dispose();
      }
    });
  }
}
