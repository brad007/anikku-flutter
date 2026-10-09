import 'package:anikku/data/library_model.dart';
import 'package:anikku/domain/catalog.dart';
import 'package:anikku/ui/core/playback_buffer.dart';
import 'package:anikku/ui/core/theme.dart';
import 'package:anikku/ui/screens/player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'support.dart';

class BufferingController extends VideoPlayerController {
  BufferingController()
    : super.networkUrl(Uri.parse('https://example.com/video.mp4'));
  int playCalls = 0;
  @override
  Future<void> initialize() async {
    value = const VideoPlayerValue(
      duration: Duration(seconds: 100),
      size: Size(1280, 720),
      isInitialized: true,
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }
}

void main() {
  test(
    'buffer ahead merges touching ranges without counting gaps after a seek',
    () {
      final value = VideoPlayerValue(
        duration: const Duration(seconds: 100),
        position: const Duration(seconds: 20),
        buffered: [
          DurationRange(
            const Duration(seconds: 24),
            const Duration(seconds: 29),
          ),
          DurationRange(
            const Duration(seconds: 40),
            const Duration(seconds: 60),
          ),
          DurationRange(
            const Duration(seconds: 10),
            const Duration(seconds: 24),
          ),
        ],
      );
      expect(bufferedAhead(value), const Duration(seconds: 9));
      expect(
        bufferedAhead(
          value.copyWith(
            position: Duration.zero,
            buffered: [
              DurationRange(
                const Duration(milliseconds: 83),
                const Duration(seconds: 8),
              ),
            ],
          ),
        ),
        const Duration(seconds: 8),
      );
      expect(
        bufferedAhead(value.copyWith(position: const Duration(seconds: 32))),
        Duration.zero,
      );
      expect(
        bufferedThrough(
          value.copyWith(
            buffered: [
              DurationRange(Duration.zero, const Duration(seconds: 110)),
            ],
          ),
        ),
        const Duration(seconds: 100),
      );
    },
  );

  Future<LibraryModel> mount(
    WidgetTester tester,
    BufferingController controller, {
    Anime? playbackAnime,
    VideoPlayerController Function(VideoStream)? controllerFactory,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
    );
    await model.initialize();
    final anime = playbackAnime ?? model.titles.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: anikkuTheme(),
        home: PlayerScreen(
          model: model,
          anime: anime,
          episode: anime.episodes.first,
          controllerFactory: controllerFactory ?? (_) => controller,
        ),
      ),
    );
    await tester.pump();
    return model;
  }

  testWidgets(
    'startup waits for buffered media, then stalls recover without overriding pause',
    (tester) async {
      final controller = BufferingController();
      final model = await mount(tester, controller);
      expect(find.text('Buffering…'), findsOneWidget);
      expect(controller.playCalls, 0);
      controller.value = controller.value.copyWith(
        buffered: [DurationRange(Duration.zero, const Duration(seconds: 8))],
      );
      await tester.pump();
      await tester.pump();
      expect(controller.playCalls, 1);
      expect(find.byKey(const Key('buffering-overlay')), findsNothing);
      expect(
        tester.widget<Slider>(find.byType(Slider)).secondaryTrackValue,
        .08,
      );
      // AVPlayer may report rate=0 during a stall while playback is still requested.
      controller.value = controller.value.copyWith(
        isPlaying: false,
        isBuffering: true,
      );
      await tester.pump();
      expect(find.text('Buffering…'), findsOneWidget);
      expect(find.byKey(const Key('play-pause-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('hide-controls-button')));
      await tester.pump();
      expect(find.text('Buffering…'), findsOneWidget);
      await tester.tapAt(const Offset(640, 400));
      await tester.pump();
      await tester.tap(find.byKey(const Key('play-pause-button')));
      await tester.pump();
      expect(find.text('Buffering…'), findsNothing);
      controller.value = controller.value.copyWith(isBuffering: false);
      await tester.pump();
      expect(
        controller.playCalls,
        1,
        reason: 'Buffer recovery must not resume a user-paused video',
      );
      await tester.tap(find.byKey(const Key('play-pause-button')));
      await tester.pump();
      expect(controller.playCalls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets('resolution dropdown swaps streams and keeps pause intent', (
    tester,
  ) async {
    final first = BufferingController();
    final second = BufferingController();
    final labels = <String>[];
    final anime = Anime(
      id: 'quality',
      sourceId: 'test',
      title: 'Quality Show',
      episodes: [
        Episode(
          id: '1',
          title: 'Episode 1',
          number: 1,
          streams: [
            VideoStream(
              url: Uri.parse('https://example.com/360.mp4'),
              label: '360p',
            ),
            VideoStream(
              url: Uri.parse('https://example.com/720.mp4'),
              label: '720p',
            ),
          ],
        ),
      ],
    );
    final model = await mount(
      tester,
      first,
      playbackAnime: anime,
      controllerFactory: (stream) {
        labels.add(stream.label);
        return labels.length == 1 ? first : second;
      },
    );
    first.value = first.value.copyWith(
      buffered: [DurationRange(Duration.zero, const Duration(seconds: 8))],
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('resolution-dropdown')), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-pause-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('resolution-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('360p').last);
    await tester.pump();
    await tester.pump();
    expect(labels, ['720p', '360p']);
    expect(second.playCalls, 0);
    expect(find.byKey(const Key('play-pause-button')), findsOneWidget);
    expect(find.byKey(const Key('resolution-dropdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('cast button opens the AirPlay picker on Apple platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app.anikku/cast'), (
          call,
        ) async {
          expect(call.method, 'showAirPlayPicker');
          calls++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.anikku/cast'),
            null,
          ),
    );
    final controller = BufferingController();
    final model = await mount(tester, controller);
    controller.value = controller.value.copyWith(
      buffered: [DurationRange(Duration.zero, const Duration(seconds: 8))],
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('cast-button')));
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('fullscreen button toggles the native window channel', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app.anikku/window'), (
          call,
        ) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.anikku/window'),
            null,
          ),
    );
    final controller = BufferingController();
    final model = await mount(tester, controller);
    controller.value = controller.value.copyWith(
      buffered: [DurationRange(Duration.zero, const Duration(seconds: 8))],
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('fullscreen-button')));
    await tester.pump();
    expect(calls, ['enterFullscreen']);
    expect(find.byKey(const Key('fullscreen-button')), findsNothing);
    await tester.tapAt(const Offset(640, 400));
    await tester.pump();
    expect(find.byKey(const Key('fullscreen-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fullscreen-button')));
    await tester.pump();
    expect(calls, ['enterFullscreen', 'exitFullscreen']);
    expect(find.byKey(const Key('fullscreen-button')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'missing buffer reports cannot deadlock startup and errors replace buffering',
    (tester) async {
      final controller = BufferingController();
      final model = await mount(tester, controller);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(controller.playCalls, 1);
      controller.value = controller.value.copyWith(
        isBuffering: true,
        errorDescription: 'Connection lost',
      );
      await tester.pump();
      expect(find.text('Connection lost'), findsOneWidget);
      expect(find.text('Buffering…'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'focus changes during prebuffering preserve play intent but explicit pause does not resume',
    (tester) async {
      final controller = BufferingController();
      final model = await mount(tester, controller);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(controller.playCalls, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.playCalls, 1);
      await tester.tap(find.byKey(const Key('play-pause-button')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.playCalls, 1);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'leaving during startup cancels the buffer wait without playing',
    (tester) async {
      final controller = BufferingController();
      final model = await mount(tester, controller);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
      expect(controller.playCalls, 0);
      expect(tester.takeException(), isNull);
      model.dispose();
    },
  );
}
