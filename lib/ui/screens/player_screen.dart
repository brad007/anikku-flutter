import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../data/library_model.dart';
import '../../data/subtitle_service.dart';
import '../../domain/catalog.dart';
import '../../platform/cast_service.dart';
import '../../platform/window_service.dart';
import '../core/theme.dart';
import '../core/playback_buffer.dart';
import '../core/tv_button.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.model,
    required this.anime,
    required this.episode,
    this.controllerFactory,
  });
  final LibraryModel model;
  final Anime anime;
  final Episode episode;
  final VideoPlayerController Function(VideoStream)? controllerFactory;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? controller;
  VideoPlayerController? nextController;
  Episode? nextBufferedEpisode;
  int nextBufferedStreamIndex = 0;
  bool nextBuffering = false;
  Duration? previewPosition;
  Duration? previewFramePosition;
  double previewFraction = 0;
  bool scrubbing = false;
  bool previewLoading = false;
  int previewGeneration = 0;
  Uri? previewStreamUrl;
  Timer? previewTimer;
  VideoPlayerController? previewController;
  late Episode episode = widget.episode;
  int streamIndex = 0;
  int generation = 0;
  String? error;
  bool initializing = true;
  bool prebuffering = false;
  bool wantsPlayback = true;
  bool suspended = false;
  Completer<void>? bufferReady;
  Timer? bufferDeadline;

  void finishPrebuffer() {
    bufferDeadline?.cancel();
    bufferDeadline = null;
    final waiting = bufferReady;
    bufferReady = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  bool hasStartupBuffer(VideoPlayerValue value) =>
      bufferedAhead(value) >= const Duration(seconds: 3) ||
      (value.duration > Duration.zero &&
          bufferedThrough(value) >= value.duration);

  Future<void> prebuffer(VideoPlayerController player) async {
    if (hasStartupBuffer(player.value)) return;
    final waiting = Completer<void>();
    bufferReady = waiting;
    setState(() => prebuffering = true);
    // Some backends only fill after play is requested. Bound the startup wait
    // and then let native adaptive buffering take over rather than deadlocking.
    bufferDeadline = Timer(const Duration(seconds: 5), finishPrebuffer);
    await waiting.future;
  }

  bool advancing = false;
  Timer? saveTimer;
  bool controlsVisible = true;
  bool fullscreenActive = false;
  bool audioMuted = false;
  bool loadingSubtitles = false;
  int subtitleIndex = -1;
  final screenFocus = FocusNode();
  final playFocus = FocusNode();

  void focusPlayback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controlsVisible && playFocus.canRequestFocus) {
        playFocus.requestFocus();
      }
    });
  }

  void showControls() {
    if (mounted) {
      setState(() => controlsVisible = true);
      focusPlayback();
    }
  }

  void hideControls() {
    setState(() => controlsVisible = false);
    screenFocus.requestFocus();
  }

  Future<void> toggleFullscreen() async {
    if (!WindowService.isSupported) {
      hideControls();
      return;
    }
    final entering = !fullscreenActive;
    try {
      if (entering) {
        await WindowService.enterFullscreen();
      } else {
        await WindowService.exitFullscreen();
      }
      if (!mounted) return;
      setState(() {
        fullscreenActive = entering;
        controlsVisible = !entering;
      });
      if (entering) {
        screenFocus.requestFocus();
      } else {
        focusPlayback();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Fullscreen is unavailable.')),
      );
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        fullscreenActive = entering;
        controlsVisible = !entering;
      });
    }
  }

  Future<void> cycleSubtitles() async {
    if (loadingSubtitles) return;
    final active = controller;
    if (active == null || !active.value.isInitialized) return;
    final tracks = episode.streams[streamIndex].subtitles;
    final nextIndex = subtitleIndex + 1 >= tracks.length
        ? -1
        : subtitleIndex + 1;
    setState(() => loadingSubtitles = true);
    try {
      final captions = nextIndex < 0
          ? null
          : await SubtitleService().load(tracks[nextIndex]);
      if (!mounted || controller != active) return;
      await active.setClosedCaptionFile(
        captions == null ? null : Future.value(captions),
      );
      if (mounted) setState(() => subtitleIndex = nextIndex);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load subtitles. Check the subtitle URL and format.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loadingSubtitles = false);
    }
  }

  Future<void> disposePreviewController() async {
    previewGeneration++;
    previewTimer?.cancel();
    previewTimer = null;
    final pending = previewController;
    previewController = null;
    previewStreamUrl = null;
    previewFramePosition = null;
    previewLoading = false;
    if (pending != null) {
      await pending.dispose();
    }
  }

  Future<VideoPlayerController> previewControllerFor(VideoStream stream) async {
    final local = await widget.model.downloads?.localFile(
      widget.anime,
      episode,
      streamUrl: stream.url,
    );
    return widget.controllerFactory?.call(stream) ??
        (local != null
            ? VideoPlayerController.file(local)
            : VideoPlayerController.networkUrl(
                stream.url,
                httpHeaders: stream.headers,
              ));
  }

  void schedulePreviewFrame(Duration target) {
    previewTimer?.cancel();
    previewTimer = Timer(const Duration(milliseconds: 80), () {
      unawaited(updatePreviewFrame(target));
    });
  }

  Future<void> updatePreviewFrame(Duration target) async {
    if (episode.streams.isEmpty || streamIndex >= episode.streams.length) {
      return;
    }
    final stream = episode.streams[streamIndex];
    final token = ++previewGeneration;
    if (mounted) setState(() => previewLoading = true);
    try {
      var preview = previewController;
      if (preview == null || previewStreamUrl != stream.url) {
        final old = previewController;
        previewController = null;
        previewStreamUrl = stream.url;
        if (old != null) {
          await old.dispose();
        }
        preview = await previewControllerFor(stream);
        previewController = preview;
        await preview.initialize().timeout(const Duration(seconds: 20));
        await preview.setVolume(0);
        await preview.pause();
      }
      if (!mounted || token != previewGeneration) return;
      await preview.seekTo(target);
      await preview.pause();
      if (!mounted || token != previewGeneration) return;
      setState(() {
        previewLoading = false;
        previewFramePosition = target;
      });
    } catch (_) {
      if (mounted && token == previewGeneration) {
        setState(() {
          previewLoading = false;
          previewFramePosition = null;
        });
      }
    }
  }

  Future<void> disposeNextPrebuffer() async {
    final pending = nextController;
    nextController = null;
    nextBufferedEpisode = null;
    nextBufferedStreamIndex = 0;
    nextBuffering = false;
    if (pending != null) await pending.dispose();
  }

  Future<void> startNextPrebuffer() async {
    if (widget.controllerFactory != null ||
        nextBuffering ||
        nextController != null) {
      return;
    }
    final upcoming = nextEpisode;
    if (upcoming == null) return;
    nextBuffering = true;
    if (mounted) setState(() {});
    VideoPlayerController? prepared;
    try {
      var resolved = upcoming.streams.isEmpty
          ? await widget.model.resolveEpisode(widget.anime, upcoming)
          : upcoming;
      final index = preferredStreamIndex(
        resolved.streams,
        language: widget.model.preferredLanguage,
      );
      final stream = resolved.streams[index];
      final local = await widget.model.downloads?.localFile(
        widget.anime,
        resolved,
        streamUrl: stream.url,
      );
      prepared = local != null
          ? VideoPlayerController.file(local)
          : VideoPlayerController.networkUrl(
              stream.url,
              httpHeaders: stream.headers,
            );
      await prepared.initialize().timeout(const Duration(seconds: 30));
      await prepared.setVolume(0);
      await prepared.play();
      await Future<void>.delayed(const Duration(seconds: 2));
      await prepared.pause();
      await prepared.seekTo(Duration.zero);
      await prepared.setVolume(1);
      if (!mounted || nextEpisode?.id != upcoming.id) {
        await prepared.dispose();
        return;
      }
      nextController = prepared;
      nextBufferedEpisode = resolved;
      nextBufferedStreamIndex = index;
    } catch (_) {
      await prepared?.dispose();
    } finally {
      nextBuffering = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> playNextEpisode() async {
    final next = nextEpisode;
    if (next == null) return;
    await save(force: true);
    if (!mounted) return;
    final prepared = nextController;
    final preparedEpisode = nextBufferedEpisode;
    if (prepared != null && preparedEpisode?.id == next.id) {
      await disposePreviewController();
      final old = controller;
      old?.removeListener(changed);
      controller = null;
      if (old != null) await old.dispose();
      if (!mounted) return;
      nextController = null;
      nextBufferedEpisode = null;
      setState(() {
        episode = preparedEpisode!;
        streamIndex = nextBufferedStreamIndex;
        lastSaved = Duration.zero;
        initializing = false;
        prebuffering = false;
        wantsPlayback = true;
        error = null;
        controlsVisible = true;
      });
      controller = prepared;
      prepared.addListener(changed);
      await prepared.seekTo(Duration.zero);
      await prepared.play();
      focusPlayback();
      unawaited(startNextPrebuffer());
      return;
    }
    setState(() {
      episode = next;
      streamIndex = 0;
      lastSaved = Duration.zero;
    });
    await disposeNextPrebuffer();
    await load(position: Duration.zero);
  }

  Future<void> selectStream(int index) async {
    if (index == streamIndex || index < 0 || index >= episode.streams.length) {
      return;
    }
    final position = controller?.value.position;
    await save(force: true);
    if (!mounted) return;
    setState(() => streamIndex = index);
    await load(position: position, keepPlaybackIntent: true);
  }

  Future<void> toggleMute() async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    audioMuted = !audioMuted;
    await c.setVolume(audioMuted ? 0 : 1);
    if (mounted) setState(() {});
  }

  Future<void> openCastPicker() async {
    try {
      await CastService.showAirPlayPicker();
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'AirPlay is unavailable.')),
      );
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AirPlay is unavailable here.')),
      );
    }
  }

  Duration lastSaved = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => save());
  }

  Future<void> load({
    Duration? position,
    bool keepPlaybackIntent = false,
  }) async {
    final token = ++generation;
    final requestedPlayback = keepPlaybackIntent ? wantsPlayback : true;
    finishPrebuffer();
    await disposeNextPrebuffer();
    await disposePreviewController();
    final old = controller;
    controller = null;
    old?.removeListener(changed);
    if (old != null) await old.dispose();
    if (!mounted || token != generation) return;
    setState(() {
      initializing = true;
      prebuffering = false;
      wantsPlayback = requestedPlayback;
      error = null;
      subtitleIndex = -1;
      controlsVisible = true;
    });
    try {
      var local = await widget.model.downloads?.localFile(
        widget.anime,
        episode,
      );
      if (episode.streams.isEmpty && local == null) {
        episode = await widget.model.resolveEpisode(widget.anime, episode);
      }
      if (!mounted || token != generation) return;
      if (local != null && episode.streams.isEmpty) {
        final savedUrl = widget.model.downloads!
            .entry(widget.anime, episode)!
            .url;
        episode = Episode(
          id: episode.id,
          title: episode.title,
          number: episode.number,
          season: episode.season,
          streams: [VideoStream(url: savedUrl, label: 'Downloaded')],
          sourceUrl: episode.sourceUrl,
        );
      }
      if (position == null) {
        final savedUrl = widget.model.downloads
            ?.entry(widget.anime, episode)
            ?.url;
        final savedIndex = episode.streams.indexWhere((s) => s.url == savedUrl);
        streamIndex = savedIndex >= 0
            ? savedIndex
            : preferredStreamIndex(
                episode.streams,
                language: widget.model.preferredLanguage,
              );
      }
      if (streamIndex >= episode.streams.length) {
        streamIndex = preferredStreamIndex(
          episode.streams,
          language: widget.model.preferredLanguage,
        );
      }
      final stream = episode.streams[streamIndex];
      local = await widget.model.downloads?.localFile(
        widget.anime,
        episode,
        streamUrl: stream.url,
      );
      if (!mounted || token != generation) return;
      final created =
          widget.controllerFactory?.call(stream) ??
          (local != null
              ? VideoPlayerController.file(local)
              : VideoPlayerController.networkUrl(
                  stream.url,
                  httpHeaders: stream.headers,
                ));
      controller = created;
      await created.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || token != generation) return;
      final saved = widget.model.progress(widget.anime, episode);
      final resume =
          position ??
          (saved == null || saved.watched
              ? Duration.zero
              : Duration(milliseconds: saved.positionMs));
      if (resume > Duration.zero && resume < created.value.duration) {
        await created.seekTo(resume);
      }
      if (!mounted || token != generation) return;
      created.addListener(changed);
      if (local == null && wantsPlayback) await prebuffer(created);
      if (!mounted || token != generation) return;
      if (created.value.hasError) {
        throw StateError(created.value.errorDescription!);
      }
      if (wantsPlayback && !suspended) await created.play();
      if (mounted && token == generation) {
        setState(() {
          initializing = false;
          prebuffering = false;
        });
        focusPlayback();
      }
    } catch (e) {
      if (mounted && token == generation) {
        setState(() {
          initializing = false;
          error =
              'This stream could not be played. Check the URL, network connection and format.\n$e';
        });
      }
    }
  }

  void changed() {
    if (!mounted) return;
    final value = controller?.value;
    if (value == null) return;
    if (value.hasError) error = value.errorDescription;
    if (bufferReady != null && (value.hasError || hasStartupBuffer(value))) {
      finishPrebuffer();
    }
    final remaining = value.duration - value.position;
    if (!initializing &&
        error == null &&
        nextEpisode != null &&
        value.duration > Duration.zero &&
        remaining <= const Duration(seconds: 90)) {
      unawaited(startNextPrebuffer());
    }
    if (value.isCompleted && !advancing && !initializing && error == null) {
      advancing = true;
      unawaited(finishEpisode());
    }
    setState(() {});
  }

  Future<void> finishEpisode() async {
    await save(force: true);
    if (!mounted) return;
    final next = nextEpisode;
    if (next != null && widget.model.autoPlay) {
      await playNextEpisode();
    }
    advancing = false;
  }

  Episode? get nextEpisode {
    final index = widget.anime.episodes.indexWhere((e) => e.id == episode.id);
    return index >= 0 && index + 1 < widget.anime.episodes.length
        ? widget.anime.episodes[index + 1]
        : null;
  }

  Future<void> save({bool force = false}) async {
    final value = controller?.value;
    if (value == null || !value.isInitialized) return;
    if (!force && (value.position - lastSaved).inSeconds.abs() < 4) return;
    lastSaved = value.position;
    await widget.model.recordProgress(
      widget.anime,
      episode,
      value.position,
      value.duration,
    );
  }

  Future<void> toggle() async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    if (wantsPlayback) {
      setState(() => wantsPlayback = false);
      finishPrebuffer();
      await c.pause();
      await save(force: true);
    } else {
      setState(() => wantsPlayback = true);
      await c.play();
    }
  }

  Future<void> seek(int seconds) async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(
      Duration(
        milliseconds: (c.value.position.inMilliseconds + seconds * 1000).clamp(
          0,
          c.value.duration.inMilliseconds,
        ),
      ),
    );
    await save(force: true);
  }

  Future<void> skipConfigured(int seconds) async {
    await seek(seconds);
    if (controller != null && wantsPlayback && !controller!.value.isPlaying) {
      await controller!.play();
    }
  }

  Future<void> leave() async {
    wantsPlayback = false;
    finishPrebuffer();
    await controller?.pause();
    await save(force: true);
    if (fullscreenActive) {
      await WindowService.exitFullscreen().catchError((Object _) {});
      fullscreenActive = false;
    }
    if (mounted) Navigator.maybePop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    suspended = state != AppLifecycleState.resumed;
    if (suspended) {
      finishPrebuffer();
      unawaited(controller?.pause());
      unawaited(save(force: true));
    } else if (wantsPlayback && !initializing) {
      // Losing app focus while the startup buffer fills must not erase the
      // user's play request. An explicit Pause still remains paused.
      unawaited(controller?.play());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    saveTimer?.cancel();
    screenFocus.dispose();
    playFocus.dispose();
    unawaited(save(force: true));
    generation++;
    finishPrebuffer();
    unawaited(disposeNextPrebuffer());
    unawaited(disposePreviewController());
    if (fullscreenActive) {
      unawaited(WindowService.exitFullscreen().catchError((Object _) {}));
    }
    controller?.removeListener(changed);
    unawaited(controller?.dispose());
    super.dispose();
  }

  Widget previewFrame(Duration target) {
    final preview = previewController;
    final closeEnough =
        previewFramePosition != null &&
        (previewFramePosition! - target).inMilliseconds.abs() < 500;
    if (preview != null && preview.value.isInitialized && closeEnough) {
      return VideoPlayer(preview);
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: previewLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.image_outlined, color: Colors.white70),
    );
  }

  String time(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ready = !initializing && c != null && c.value.isInitialized;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): leave,
        const SingleActivator(LogicalKeyboardKey.goBack): leave,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): toggle,
        const SingleActivator(LogicalKeyboardKey.space): toggle,
        const SingleActivator(LogicalKeyboardKey.keyF): toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyJ): () => seek(-10),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seek(-10),
        const SingleActivator(LogicalKeyboardKey.keyL): () => seek(10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => seek(10),
        const SingleActivator(LogicalKeyboardKey.keyI): () =>
            skipConfigured(90),
        const SingleActivator(LogicalKeyboardKey.keyN): playNextEpisode,
        const SingleActivator(LogicalKeyboardKey.keyC): openCastPicker,
        const SingleActivator(LogicalKeyboardKey.keyS): cycleSubtitles,
        const SingleActivator(LogicalKeyboardKey.keyM): hideControls,
        const SingleActivator(LogicalKeyboardKey.keyR): () async {
          final c = controller;
          if (c == null || !c.value.isInitialized) return;
          await widget.model.markWatched(widget.anime, episode, false);
          await c.seekTo(Duration.zero);
          setState(() => wantsPlayback = true);
          await c.play();
        },
      },
      child: Focus(
        focusNode: screenFocus,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (!controlsVisible &&
              event is KeyDownEvent &&
              [
                LogicalKeyboardKey.select,
                LogicalKeyboardKey.enter,
                LogicalKeyboardKey.space,
                LogicalKeyboardKey.arrowUp,
                LogicalKeyboardKey.arrowDown,
                LogicalKeyboardKey.arrowLeft,
                LogicalKeyboardKey.arrowRight,
              ].contains(event.logicalKey)) {
            showControls();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: showControls,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Center(
                      child: ready
                          ? AspectRatio(
                              aspectRatio: c.value.aspectRatio > 0
                                  ? c.value.aspectRatio
                                  : 16 / 9,
                              child: VideoPlayer(c),
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (error == null &&
                        (initializing ||
                            (ready &&
                                wantsPlayback &&
                                c.value.isBuffering &&
                                !c.value.isCompleted)))
                      IgnorePointer(
                        child: Center(
                          child: Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const Key('buffering-overlay'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 22,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CircularProgressIndicator(
                                      color: brandRed,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    initializing && !prebuffering
                                        ? 'Loading video…'
                                        : 'Buffering…',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  if (c != null &&
                                      c.value.isInitialized &&
                                      bufferedAhead(c.value) >
                                          Duration.zero) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '${bufferedAhead(c.value).inSeconds}s ready',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (error != null)
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 660),
                          margin: const EdgeInsets.all(30),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 36,
                                color: brandRed,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                error!,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 18),
                              ActionButton(
                                'Retry',
                                icon: Icons.refresh,
                                onPressed: () {
                                  if (episode.sourceUrl != null) {
                                    episode = Episode(
                                      id: episode.id,
                                      title: episode.title,
                                      number: episode.number,
                                      season: episode.season,
                                      streams: const [],
                                      sourceUrl: episode.sourceUrl,
                                    );
                                    streamIndex = 0;
                                  }
                                  load();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (controlsVisible)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xE6000000), Colors.transparent],
                            ),
                          ),
                          child: Row(
                            children: [
                              ActionButton(
                                'Back',
                                icon: Icons.arrow_back,
                                onPressed: leave,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.anime.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    Text(
                                      episode.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: muted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (ready && c.value.caption.text.isNotEmpty)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: controlsVisible ? 175 : 36,
                        child: ClosedCaption(
                          text: c.value.caption.text,
                          textStyle: const TextStyle(
                            fontSize: 26,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (controlsVisible)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: EdgeInsets.all(
                            constraints.maxWidth < 600 ? 16 : 30,
                          ),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xF0000000)],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (ready) ...[
                                LayoutBuilder(
                                  builder: (context, barBox) {
                                    void updatePreview(double fraction) {
                                      final clamped = fraction.clamp(0.0, 1.0);
                                      final target = Duration(
                                        milliseconds:
                                            (clamped *
                                                    c
                                                        .value
                                                        .duration
                                                        .inMilliseconds)
                                                .round(),
                                      );
                                      setState(() {
                                        previewFraction = clamped;
                                        previewPosition = target;
                                      });
                                      schedulePreviewFrame(target);
                                    }

                                    final left =
                                        (previewFraction * barBox.maxWidth -
                                                110)
                                            .clamp(0.0, barBox.maxWidth - 220);
                                    final value =
                                        c.value.duration.inMilliseconds == 0
                                        ? 0.0
                                        : (c.value.position.inMilliseconds /
                                                  c
                                                      .value
                                                      .duration
                                                      .inMilliseconds)
                                              .clamp(0.0, 1.0);
                                    return MouseRegion(
                                      onHover: (event) => updatePreview(
                                        event.localPosition.dx /
                                            barBox.maxWidth,
                                      ),
                                      onExit: (_) {
                                        if (!scrubbing) {
                                          previewTimer?.cancel();
                                          setState(() {
                                            previewPosition = null;
                                            previewFramePosition = null;
                                            previewLoading = false;
                                          });
                                        }
                                      },
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          if (previewPosition != null)
                                            Positioned(
                                              key: const Key('seek-preview'),
                                              left: left,
                                              bottom: 38,
                                              child: Container(
                                                width: 220,
                                                padding: const EdgeInsets.all(
                                                  5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  ),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Colors.black87,
                                                      blurRadius: 18,
                                                    ),
                                                  ],
                                                ),
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    AspectRatio(
                                                      aspectRatio: 16 / 9,
                                                      child: ClipRect(
                                                        child: previewFrame(
                                                          previewPosition!,
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      bottom: 10,
                                                      child: Text(
                                                        time(previewPosition!),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 24,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          shadows: [
                                                            Shadow(
                                                              color:
                                                                  Colors.black,
                                                              blurRadius: 8,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          SliderTheme(
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                                  activeTrackColor: const Color(
                                                    0xFFFF6D1A,
                                                  ),
                                                  inactiveTrackColor:
                                                      Colors.white24,
                                                  thumbColor: const Color(
                                                    0xFFFF6D1A,
                                                  ),
                                                  overlayColor: const Color(
                                                    0x33FF6D1A,
                                                  ),
                                                  trackHeight: 3,
                                                  thumbShape:
                                                      const RoundSliderThumbShape(
                                                        enabledThumbRadius: 7,
                                                      ),
                                                ),
                                            child: Slider(
                                              label: 'Playback position',
                                              secondaryTrackValue:
                                                  c
                                                          .value
                                                          .duration
                                                          .inMilliseconds <=
                                                      0
                                                  ? 0
                                                  : (bufferedThrough(
                                                              c.value,
                                                            ).inMilliseconds /
                                                            c
                                                                .value
                                                                .duration
                                                                .inMilliseconds)
                                                        .clamp(0, 1),
                                              secondaryActiveColor:
                                                  Colors.white38,
                                              onChangeStart: (value) {
                                                scrubbing = true;
                                                updatePreview(value);
                                              },
                                              onChanged: (value) {
                                                updatePreview(value);
                                                final target = Duration(
                                                  milliseconds:
                                                      (value *
                                                              c
                                                                  .value
                                                                  .duration
                                                                  .inMilliseconds)
                                                          .round(),
                                                );
                                                c.seekTo(target);
                                              },
                                              onChangeEnd: (_) async {
                                                scrubbing = false;
                                                await save(force: true);
                                                previewTimer?.cancel();
                                                if (mounted) {
                                                  setState(() {
                                                    previewPosition = null;
                                                    previewFramePosition = null;
                                                    previewLoading = false;
                                                  });
                                                }
                                              },
                                              value: value,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 14),
                              ],
                              Text(
                                'Space pause/play • ←/→ or J/L seek • I skip intro • N next • F fullscreen • C cast • S subtitles',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _ControlIconButton(
                                    key: const Key('rewind-button'),
                                    tooltip: 'Back 10 seconds',
                                    icon: Icons.replay_10,
                                    onPressed: ready ? () => seek(-10) : null,
                                  ),
                                  _ControlIconButton(
                                    key: const Key('play-pause-button'),
                                    tooltip: ready && wantsPlayback
                                        ? 'Pause'
                                        : 'Play',
                                    icon: ready && wantsPlayback
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    autofocus: true,
                                    focusNode: playFocus,
                                    onPressed: ready ? toggle : null,
                                  ),
                                  _ControlIconButton(
                                    key: const Key('forward-button'),
                                    tooltip: 'Forward 10 seconds',
                                    icon: Icons.forward_10,
                                    onPressed: ready ? () => seek(10) : null,
                                  ),
                                  _ControlIconButton(
                                    key: const Key('mute-button'),
                                    tooltip: audioMuted ? 'Unmute' : 'Mute',
                                    icon: audioMuted
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    onPressed: ready ? toggleMute : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    ready
                                        ? '${time(c.value.position)} / ${time(c.value.duration)}'
                                        : '00:00 / 00:00',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (ready)
                                    _ControlIconButton(
                                      key: const Key('skip-intro-button'),
                                      tooltip: 'Skip intro 90s',
                                      icon: Icons.fast_forward,
                                      onPressed: () => skipConfigured(90),
                                    ),
                                  if (ready &&
                                      widget.model.skipIntroSeconds(
                                            widget.anime,
                                          ) >
                                          0 &&
                                      widget.model.skipIntroSeconds(
                                            widget.anime,
                                          ) !=
                                          90)
                                    _ControlIconButton(
                                      key: const Key(
                                        'skip-custom-intro-button',
                                      ),
                                      tooltip: 'Skip custom intro',
                                      icon: Icons.low_priority,
                                      onPressed: () => skipConfigured(
                                        widget.model.skipIntroSeconds(
                                          widget.anime,
                                        ),
                                      ),
                                    ),
                                  if (ready &&
                                      widget.model.skipRecapSeconds(
                                            widget.anime,
                                          ) >
                                          0)
                                    _ControlIconButton(
                                      key: const Key('skip-recap-button'),
                                      tooltip: 'Skip recap',
                                      icon: Icons.skip_next,
                                      onPressed: () => skipConfigured(
                                        widget.model.skipRecapSeconds(
                                          widget.anime,
                                        ),
                                      ),
                                    ),
                                  if (nextEpisode != null)
                                    _ControlIconButton(
                                      key: const Key('next-episode-button'),
                                      tooltip: nextBuffering
                                          ? 'Preloading next…'
                                          : nextController != null
                                          ? 'Next ready'
                                          : 'Next episode',
                                      icon: Icons.skip_next,
                                      onPressed: playNextEpisode,
                                    ),
                                  if (ready &&
                                      episode
                                          .streams[streamIndex]
                                          .subtitles
                                          .isNotEmpty)
                                    _ControlIconButton(
                                      key: const Key('subtitles-button'),
                                      tooltip: loadingSubtitles
                                          ? 'Loading subtitles…'
                                          : subtitleIndex < 0
                                          ? 'Subtitles off'
                                          : episode
                                                .streams[streamIndex]
                                                .subtitles[subtitleIndex]
                                                .label,
                                      icon: Icons.subtitles_outlined,
                                      onPressed: loadingSubtitles
                                          ? null
                                          : cycleSubtitles,
                                    ),
                                  if (episode.streams.length > 1)
                                    _PlayerDropdown<int>(
                                      key: const Key('resolution-dropdown'),
                                      icon: Icons.high_quality_outlined,
                                      label: episode.streams[streamIndex].label,
                                      value: streamIndex,
                                      items: [
                                        for (
                                          var i = 0;
                                          i < episode.streams.length;
                                          i++
                                        )
                                          _PlayerDropdownItem(
                                            value: i,
                                            label: episode.streams[i].label,
                                          ),
                                      ],
                                      onChanged: ready
                                          ? (value) =>
                                                unawaited(selectStream(value))
                                          : null,
                                    ),
                                  if (CastService.isSupported)
                                    _ControlIconButton(
                                      key: const Key('cast-button'),
                                      tooltip: 'Cast',
                                      icon: Icons.cast,
                                      onPressed: ready ? openCastPicker : null,
                                    ),
                                  if (ready)
                                    _ControlIconButton(
                                      key: const Key('speed-button'),
                                      tooltip: '${c.value.playbackSpeed}×',
                                      text:
                                          '${c.value.playbackSpeed.toStringAsFixed(c.value.playbackSpeed.truncateToDouble() == c.value.playbackSpeed ? 0 : 2)}×',
                                      onPressed: () {
                                        final speed = c.value.playbackSpeed;
                                        c.setPlaybackSpeed(
                                          speed >= 2 ? 1 : speed + .25,
                                        );
                                      },
                                    ),
                                  if (ready)
                                    _ControlIconButton(
                                      key: const Key('restart-button'),
                                      tooltip: 'Start over',
                                      icon: Icons.replay,
                                      onPressed: () async {
                                        await widget.model.markWatched(
                                          widget.anime,
                                          episode,
                                          false,
                                        );
                                        await c.seekTo(Duration.zero);
                                        setState(() => wantsPlayback = true);
                                        await c.play();
                                      },
                                    ),
                                  if (ready)
                                    _ControlIconButton(
                                      key: const Key('fullscreen-button'),
                                      tooltip: fullscreenActive
                                          ? 'Exit full screen'
                                          : 'Full screen',
                                      icon: fullscreenActive
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      onPressed: toggleFullscreen,
                                    ),
                                  if (ready)
                                    _ControlIconButton(
                                      key: const Key('hide-controls-button'),
                                      tooltip: 'Hide controls',
                                      icon: Icons.settings,
                                      onPressed: hideControls,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerDropdownItem<T> {
  const _PlayerDropdownItem({required this.value, required this.label});
  final T value;
  final String label;
}

class _PlayerDropdown<T> extends StatelessWidget {
  const _PlayerDropdown({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<_PlayerDropdownItem<T>> items;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: label,
    initialValue: value,
    enabled: onChanged != null,
    color: panel,
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          child: Text(
            item.label,
            style: TextStyle(
              color: item.value == value ? Colors.white : Colors.white70,
              fontWeight: item.value == value
                  ? FontWeight.w800
                  : FontWeight.w500,
            ),
          ),
        ),
    ],
    child: _ControlIconShell(
      tooltip: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 23),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
    ),
  );
}

class _ControlIconButton extends StatelessWidget {
  const _ControlIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.text,
    this.autofocus = false,
    this.focusNode,
  });

  final String tooltip;
  final IconData? icon;
  final String? text;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TvButton(
      label: tooltip,
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      quiet: true,
      padding: EdgeInsets.zero,
      child: _ControlIconShell(
        tooltip: tooltip,
        disabled: onPressed == null,
        child: text == null
            ? Icon(icon, size: 24)
            : Text(
                text!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    ),
  );
}

class _ControlIconShell extends StatelessWidget {
  const _ControlIconShell({
    required this.tooltip,
    required this.child,
    this.disabled = false,
  });

  final String tooltip;
  final Widget child;
  final bool disabled;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tooltip,
    child: Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: IconTheme.merge(
        data: const IconThemeData(size: 24),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontWeight: FontWeight.w900),
          child: Opacity(opacity: disabled ? .45 : 1, child: child),
        ),
      ),
    ),
  );
}
