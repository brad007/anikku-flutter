import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:anikku/data/catalog_service.dart';
import 'package:anikku/data/download_manager.dart';
import 'package:anikku/data/library_model.dart';
import 'package:anikku/data/library_repository.dart';
import 'package:anikku/data/sources/animegg_source.dart';
import 'package:anikku/ui/app.dart';
import 'package:anikku/ui/core/theme.dart';
import 'package:anikku/ui/core/playback_buffer.dart';
import 'package:anikku/ui/screens/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    const bool.fromEnvironment('PLAYBACK_ONLY')
        ? 'real anime startup buffering, playback and buffered timeline'
        : 'real anime discovery, native playback, automatic download and offline resume',
    (tester) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      final root = await getApplicationCacheDirectory();
      final directory = Directory('${root.path}/anikku-live-source-test');
      if (await directory.exists()) await directory.delete(recursive: true);
      final store = FileStateStore(directory: () async => directory);
      var model = LibraryModel(
        store: store,
        catalogs: CatalogService(),
        includeSamples: false,
        sources: [AnimeGgSource()],
        downloads: DownloadManager(directory: () async => directory),
      );
      final key = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        binding.reportData ??= {};
        binding.reportData![name] = base64Encode(bytes!.buffer.asUint8List());
        binding.reportData!['platform'] = Platform.operatingSystem;
        image.dispose();
      }

      Future<void> until(
        bool Function() ready,
        String message, {
        int seconds = 60,
      }) async {
        for (var i = 0; i < seconds * 2 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(ready(), isTrue, reason: message);
      }

      try {
        await model.initialize();
        expect(model.titles.length, greaterThan(10));
        expect(
          model.titles.any((a) => a.sourceId == 'blender-samples'),
          isFalse,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: AnikkuApp(model: model),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await capture('source-home');
        await model.searchSources('Cowboy Bebop');
        final anime = await model.ensureDetails(
          model.searchResults!.firstWhere((a) => a.title == 'Cowboy Bebop'),
        );
        expect(anime.episodes.length, 26);
        expect(anime.episodes.first.number, 1);
        await model.toggleFavorite(anime);
        final episode = anime.episodes.first;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: anikkuTheme(),
              debugShowCheckedModeBanner: false,
              home: PlayerScreen(model: model, anime: anime, episode: episode),
            ),
          ),
        );
        await until(
          () => find.byType(VideoPlayer).evaluate().isNotEmpty,
          'Video did not initialize: ${find.textContaining('could not be played').evaluate().map((e) => (e.widget as Text).data)}',
        );
        var controller = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        expect(
          controller.value.duration,
          greaterThan(const Duration(minutes: 20)),
        );
        debugPrint('BUFFER_START: lifecycle=${WidgetsBinding.instance.lifecycleState}; value=${controller.value}');
        await controller.seekTo(const Duration(seconds: 95));
        debugPrint('BUFFER_SEEK: value=${controller.value}');
        await until(
          () => controller.value.position > const Duration(seconds: 97),
          'Native playback did not advance',
        );
        await controller.pause();
        await tester.pump(const Duration(milliseconds: 500));
        await capture('source-playing');
        await model.recordProgress(
          anime,
          episode,
          controller.value.position,
          controller.value.duration,
        );
        final duration = controller.value.duration;
        debugPrint(
          'REAL_ANIME_ONLINE: ${Platform.operatingSystem}; Cowboy Bebop episode 1; duration=$duration; video advanced',
        );
        if (const bool.fromEnvironment('PLAYBACK_ONLY')) {
          expect(bufferedAhead(controller.value), greaterThan(Duration.zero));
          expect(
            tester.widget<Slider>(find.byType(Slider)).secondaryTrackValue,
            greaterThan(tester.widget<Slider>(find.byType(Slider)).value),
          );
          expect(find.byKey(const Key('buffering-overlay')), findsNothing);
          binding.reportData!['playbackOnly'] = true;
          binding.reportData!['verified'] = true;
          debugPrint(
            'BUFFERING_VERIFIED: ${Platform.operatingSystem}; native buffered ahead=${bufferedAhead(controller.value)}; real anime advancing; buffer overlay cleared',
          );
          return;
        }
        await model.setAutomaticDownloads(true);
        await until(
          () =>
              model.downloads!.entry(anime, episode)?.status ==
              DownloadStatus.complete,
          'Automatic anime download failed: ${model.downloads!.error}',
          seconds: 300,
        );
        final bytes = model.downloads!.usedBytes;
        expect(bytes, greaterThan(1000000));
        await model.setAutomaticDownloads(false);
        await tester.pumpWidget(const SizedBox());
        model.dispose();
        // Reload persisted metadata and files without a source adapter: offline playback
        // must neither rediscover the episode nor depend on a still-valid server URL.
        model = LibraryModel(
          store: store,
          catalogs: CatalogService(),
          includeSamples: false,
          downloads: DownloadManager(directory: () async => directory),
        );
        await model.initialize();
        final restored = model.library.single;
        expect(restored.title, 'Cowboy Bebop');
        expect(restored.episodes.first.streams, isEmpty);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: anikkuTheme(),
              debugShowCheckedModeBanner: false,
              home: PlayerScreen(
                model: model,
                anime: restored,
                episode: restored.episodes.first,
              ),
            ),
          ),
        );
        await until(
          () => find.byType(VideoPlayer).evaluate().isNotEmpty,
          'Offline video did not initialize',
        );
        controller = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        expect(controller.dataSourceType, DataSourceType.file);
        await until(
          () => controller.value.position > const Duration(seconds: 98),
          'Offline resume did not advance',
        );
        await controller.pause();
        await tester.pump(const Duration(milliseconds: 500));
        await capture('source-offline');
        debugPrint(
          'REAL_ANIME_VERIFIED: ${Platform.operatingSystem}; Cowboy Bebop episode 1; 26 episodes; duration=$duration; automatic download=$bytes bytes; offline resume=${controller.value.position}',
        );
        binding.reportData!['verified'] = true;
      } finally {
        await tester.pumpWidget(const SizedBox());
        model.dispose();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
