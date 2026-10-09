# Validation — 8 October 2026

## Real anime source checks

Normal startup uses the native AnimeGG adapter and excludes the stock/sample catalog, including previously cached sample titles. The Android extension's published Apache-2.0 source was adapted to Dart; no APK runtime is required.

- `flutter analyze`: **no issues**.
- `flutter test`: **50 passed**, one live-network test intentionally skipped without `LIVE_SOURCE=true`.
- Explicit live HTTP test: **passed**. Searches Cowboy Bebop, finds 26 episodes, resolves subbed/dubbed variants, verifies MP4 bytes through HTTP 206. Log: `evidence/source-live.log`.
- **macOS**, 7 October: **passed**. Native playback of Cowboy Bebop episode 1, Asteroid Blues; duration **24:42.646**, video advances beyond a seek to 1:35. Automatically downloads **54,642,064 bytes**. Reloads persisted library/download state without any source adapter and resumes through a file controller beyond 1:38. Log: `evidence/macos-source-integration.log`.
- **Apple TV simulator**, 8 October: **passed**. Same episode and **24:42.646** runtime; automatically downloads **54,642,064 bytes** and resumes the local file beyond **1:38** after reloading persisted state without a source adapter. Log: `evidence/tvos-source-integration.log`.

The source test uses the actual app's LibraryModel, PlayerScreen, DownloadManager and native video plugin. It asserts a full episode duration and advancing playback, then checks the entire downloaded file after restarting model state. `evidence/*-source-playing.png` and `*-source-offline.png` contain decoded anime frames. `*-source-home.png` shows the real source's listings. The player screenshots use a minimal test host; normal app styling comes from AnikkuApp.

Fixture tests cover parsing, stable episode IDs, fresh stream resolution, mirror failures, source errors, lazy details, remote search, stale search responses, preserving history through updates, and the loading-state player regression. Availability for all listed episodes or regions is not implied by the tested episode.

## Buffering update — 8 October

Network startup targets three seconds of buffered video and waits at most five seconds before handing off to native adaptive buffering. Downloaded files bypass this wait. A live buffering overlay stays visible with controls hidden; the timeline shows loaded progress. Tiny frame-timestamp gaps are tolerated, while genuinely disconnected future ranges do not satisfy the target. App-focus changes preserve play intent; explicitly pausing a stalled video prevents automatic resume.

Unit/widget cases cover buffer ranges, startup gating, timeout fallback, stall/paused/error UI, cancellation, focus changes, season grouping, the resolution dropdown preserving pause intent, and the AirPlay cast channel. At that checkpoint, the full suite passed **53 tests** and static analysis was clean.

The `PLAYBACK_ONLY=true` native check resolves Cowboy Bebop episode 1, starts playback, seeks to 1:35, verifies advancing playback and buffered media ahead, and checks that the overlay clears and the slider shows the buffered portion. Both macOS and the Apple TV simulator passed again after the season, resolution dropdown and AirPlay changes. The complete download/offline source checks above remain separate from this shorter check.

## Streaming-service feature pass — 8 October

A product feature pass added local profiles, watchlist statuses, richer discovery rows, new-episode counts, per-season and full-title Download all actions, no app-level download cap, grouped download lists, background-resumable download queues, Highest/Smallest download quality rules, Wi-Fi-only automatic-download pausing, a constant Skip intro 90s control, configurable skip-intro/skip-recap controls, player keyboard shortcuts, next-episode preloading, seek preview cards, language/stream-type filters, Browse sorting, Continue Watching cleanup, a rotating TV-style Home hero, season-level progress actions and source health diagnostics. The player still defaults to the highest available stream and the Browse language filter applies when stream labels or resolved metadata identify subbed/dubbed variants.

Validation after the pass: `flutter test` passed **57 tests** with one live-network test intentionally skipped, `flutter analyze` reported **no issues**, the macOS debug build passed, the tvOS simulator debug build passed, and the unsigned no-codesign tvOS release build passed. The no-codesign build still warns that distribution requires an Apple Distribution certificate.

## Earlier core-feature checks — 7 October

Before the source adapter, each platform passed eight native network-suite cases and seven UI/storage/player cases. These cover writable storage, remote/keyboard navigation, AVPlayer controls, history/resume, downloads and offline UI. The older network fixture uses Namakura Gatana (1917); the new source test above independently verifies a full television anime episode. Stock films and synthetic clips remain only as deterministic test fixtures, not the normal browsing catalog.

The Netflix-inspired UI includes cinematic Home, horizontal rows, My List, related genres, Continue Watching, dated/removable history and a black/white/red palette. Automatic progressive-file downloads have storage caps, cancellation, retry and offline playback. The broader feature gaps remain in PORT_STATUS.md.

Native tvOS runs on **Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator**, Xcode 27.0, with pinned flutter-tvos `v3.47.6-tvos.1.11.1`. Mac runs use stock Flutter 3.47.4. The first tvOS run encountered AVFoundation OSStatus -12746 for local and network media. Restarting only the dedicated Anikku simulator resolved it; the complete network suite then passed. The failed run is retained as `tvos-integration-before-restart.log`.

The native test harness uses Enter on macOS and Select on tvOS. Back/media events use explicit physical-key mappings where the test framework lacks them. The `integration_test plugin was not detected` warning is expected with the Flutter Driver bridge; the host driver requires screenshots and test results, so an empty run cannot pass. Setup and teardown contribute two entries to the printed test counter.

Native screenshots in `evidence/` were rendered and inspected. The test-pattern video is intentionally synthetic. The anime screenshots contain actual decoded movie frames; The older Home/catalog screenshots use sample artwork; source-prefixed evidence uses real anime listings. Key injection does not verify a physical Siri Remote's touch/Bluetooth behavior.

## Remaining device and parity checks

- No physical Apple TV was paired/tested. Device installation, real Siri Remote behavior, HDR/4K, long playback sessions and background/resume on hardware remain unverified.
- The ARM64 device artifact is deliberately unsigned and cannot be installed as-is. Signing/provisioning is required. No App Store or TestFlight submission occurred.
- The toolchain reports no Apple Distribution certificate in this environment. Distribution requires the appropriate certificate, including signing the embedded Flutter engine.
- tvOS cache data may be purged by the OS. Cloud/iCloud persistence is not implemented.
- Subtitle parsing has SRT/VTT unit tests; downloaded video does not cache external subtitle files. Hardware subtitle delivery remains unverified.
- HTTPS MP4 is verified. Provider-specific HLS, codecs, authenticated headers, subtitle endpoints and regional/network restrictions need testing with the actual catalog you plan to use.
- Android/iOS runners are generated and share the tested responsive UI; see additional build results below. Hardware flows are unverified.
- Feature gaps are explicitly listed in `docs/PORT_STATUS.md`.

## Reproduce

```bash
flutter analyze
flutter test
flutter drive --driver=test_driver/source_test.dart --target=integration_test/source_test.dart -d macos
.tools/flutter-tvos/bin/flutter-tvos drive --driver=test_driver/source_test.dart --target=integration_test/source_test.dart -d <tvOS-simulator-id>
.tools/flutter-tvos/bin/flutter-tvos build tvos --release --no-codesign
```

The host driver writes TV evidence images into `evidence/`. The test suite uses isolated memory state and a removable native storage probe. Do not run the integration suite against an app installation holding your only copy of a library: `flutter drive` may uninstall its test app at the end.

## Previous platform build baseline — 6 October 2026

- macOS debug build: passed (`evidence/macos-build.log`). The upstream video-player plugin emits Swift optionality warnings; these are not build failures.
- iOS simulator debug build: passed (`evidence/ios-build.log`), producing `build/ios/iphonesimulator/Runner.app`.
- Android debug APK build: passed (`evidence/android-build.log`), producing `build/app/outputs/flutter-apk/app-debug.apk`.

## Build-mode regression fixed

Building a release and then a simulator debug app exposed a stale `App.framework` left in the tvOS staging directory. The generated embed phase copied that AOT framework into Debug, which changed native asset lookup and caused AVPlayer's bundled test clip to fail with OSStatus `-17913`. The dedicated tvOS runner now removes `App.framework` from Debug output and embeds it only for AOT configurations. The native suite was rerun after this release-to-debug transition; bundled playback and network playback passed. Do not regenerate `tvos/` over the custom runner without preserving this build-phase guard.

The normal entry point (`lib/main.dart`) was rebuilt and launched on macOS and the Apple TV simulator on 8 October after the source tests. The unsigned ARM64 tvOS release build also passed. `evidence/tvos-app.png` shows the actual launched app with real source artwork and titles; `tvos-launch.log`, `tvos-debug.log`, `tvos-release.log` and `macos-build.log` record those checks. Android/iOS were not rebuilt for the source adapter; their 6 October build results remain historical evidence only.
