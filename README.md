# Anikku for Flutter

A working Flutter port of Anikku's core library and watching experience, with a native **Apple TV / tvOS** runner and a remote-first interface. Android, iOS and macOS runners are also included.

This is an independent early port, not full feature parity with the Android application. The app opens with native **AnimeGG** and **Internet Archive** source adapters. AnimeGG provides anime search and episode playback; Internet Archive adds direct-file playback for archive items that expose compatible MP4/M4V files. **Portable JSON catalogs and direct video URLs** are also supported. Android APK extensions are not executable on Apple platforms.

## Install from GitHub Releases

Download the latest release from [GitHub Releases](https://github.com/brad007/anikku-flutter/releases).

| Platform | Asset | Install notes |
| --- | --- | --- |
| macOS | `Anikku-macOS.zip` | Unzip, move `anikku.app` to Applications, then open it. If Gatekeeper blocks the unsigned build, right-click → Open, or run `xattr -dr com.apple.quarantine /Applications/anikku.app` after you trust the build. |
| Android | `Anikku-android-debug.apk` | Copy to an Android device and sideload it. It is debug-signed for easy installation from GitHub. |
| Apple TV / tvOS | `Anikku-tvOS-unsigned.zip` | This is an unsigned developer artifact. Apple TV cannot install arbitrary unsigned apps from GitHub; a physical Apple TV build must be signed with your Apple Developer team in Xcode, or distributed through TestFlight/App Store. |

The release also includes `Anikku-tvOS-simulator.zip` for Apple TV simulator testing on macOS.

## Build from source

Clone the repository and install Flutter. Stock Flutter builds macOS, Android and iOS; Apple TV uses the pinned `flutter-tvos` toolchain.

```bash
git clone https://github.com/brad007/anikku-flutter.git
cd anikku-flutter
flutter pub get
flutter run -d macos
```

## Run on Apple TV

Requires macOS, Xcode with the tvOS SDK/runtime, and CocoaPods. tvOS is provided by the community [flutter-tvos](https://github.com/fluttertv/flutter-tvos) toolchain; the standard `flutter run` command cannot target Apple TV.

```bash
./tool/bootstrap_tvos.sh
.tools/flutter-tvos/bin/flutter-tvos devices
./tool/run_tvos.sh <apple-tv-simulator-id>
```

If no Apple TV simulator exists, install the runtime with `xcodebuild -downloadPlatform tvOS` and create an Apple TV in Xcode → Window → Devices and Simulators. This workspace already has **Anikku Apple TV** (`FD1004F6-B7AB-404D-B9A5-1E8C1FD42B5D`).

```bash
xcrun simctl boot FD1004F6-B7AB-404D-B9A5-1E8C1FD42B5D
./tool/run_tvos.sh FD1004F6-B7AB-404D-B9A5-1E8C1FD42B5D
```

For a physical Apple TV, pair it in Xcode, enable Developer Mode if requested, choose your signing team and a unique bundle identifier in `tvos/Runner.xcworkspace`, then:

```bash
./tool/run_tvos.sh <paired-apple-tv-id> --release
```

The setup script pins flutter-tvos `v3.47.6-tvos.1.11.1` at revision `88a497e6345d32f2aedba92c1fdb30f42d29a3d3`, which manages its own matching Flutter SDK. It does not change your installed Flutter SDK. Do not substitute arbitrary engine/SDK versions. The checked-in tvOS runner also guards against stale release frameworks when switching back to Debug; preserve it rather than regenerating `tvos/`.

## What works

- Remote/keyboard directional focus, Select/Enter activation and Back/Escape navigation.
- Cinematic Home, auto-rotating featured titles for an idle TV feel, horizontal poster rows, red-and-black styling, responsive top navigation and searchable title grids.
- My List favorites, named categories, watchlist statuses, genre rows, related titles, recently added/completed/short-watch discovery rows and alphabetical/source ordering.
- Portable catalog URL import, cached browsing, refresh and new-episode updates.
- Direct video URLs saved to the library.
- Native video playback, startup prebuffering, visible buffering status and buffered timeline progress, season-aware episode order, a resolution dropdown that defaults to the highest available stream, AirPlay casting on Apple platforms, fullscreen playback, pause, 10-second seek, speed, configurable skip-intro/skip-recap buttons, optional next-episode autoplay and hide/show controls.
- External SRT and WebVTT subtitles from catalogs.
- Per-profile Continue Watching, most-recent-episode resume, removable watch history, automatic watched state at 95%, season watched/start-over controls, and watched/unwatched controls.
- Atomic JSON file storage, plus JSON backup view/restore.
- Native AnimeGG browsing/search, lazy episode lists, fresh subbed/dubbed video resolution and downloads. Internet Archive browsing/search, metadata loading and direct MP4/M4V playback when files are available. Production startup excludes sample films; deterministic tests retain separate fixtures.
- Per-episode, season and full-title progressive-file downloads, highest/smallest quality rules, Wi-Fi-only pause mode, grouped download lists, background-resumable queues, cancellation, retry and local playback.

Use **Browse** to search the built-in anime sources, then narrow results by genre, year, status, source, availability and language/stream type when metadata is available. Browse can sort by A–Z, last updated, release date, subbed-first and dubbed-first. Related franchise results are collapsed into one anime card across Browse and Home rails, so searches and rows like Attack on Titan do not flood the UI with every season, movie and special as separate top-level entries. Opening that card shows a collapsible Crunchyroll-style season/movie/special selector ordered in a release-style sequence. To add another portable catalog, use **Browse → Add catalog** with an HTTPS URL serving the format in [docs/catalog.example.json](docs/catalog.example.json). For individual videos, use **Add video**. A website/watch-page URL is not a stream URL. See [the catalog specification](docs/CATALOGS.md).

The player uses the platform's supported codecs (AVPlayer on Apple TV), not mpv. MP4/H.264 and HLS are the primary targets. DRM, arbitrary MKV/ASS rendering, torrent playback, native embedded subtitle/audio-track selection and mpv filters are not implemented.

## Streaming-service features

The current Flutter edition now includes the expected living-room streaming controls: multiple local profiles, watchlist statuses, season-level progress actions, Continue Watching cleanup, new-episode tracking, source health diagnostics, preferred subtitle/dub language, download quality rules, Wi-Fi-only automatic download pausing, source/language filters and a rotating Home hero for TV idle browsing. The player preloads the next episode near the end, shows a seek preview card while scrubbing, supports keyboard shortcuts, and always includes a Skip intro 90s button. Custom Skip Intro and Skip Recap values can still be configured per title from the detail screen.

## TV controls

| Control | Action |
| --- | --- |
| Remote directions / arrow keys | Move focus |
| Select / Enter | Activate focused control |
| Back / Escape | Return to the previous screen |
| Play/Pause media key / Space | Toggle playback |
| J / L or Left / Right in player | Seek back / forward 10 seconds |
| I | Skip intro 90 seconds |
| N | Play the next episode |
| F | Toggle fullscreen |
| C | Open AirPlay cast picker on Apple platforms |
| S | Cycle subtitle tracks |
| M / Hide controls | Show the video without the overlay |
| R | Start the current episode over |
| Select or direction with controls hidden | Restore controls |

Text fields use the tvOS engine's system keyboard bridge. Tests inject Flutter key events; a physical Siri Remote still needs device testing.

## Storage and backups

The Apple TV sandbox only permits file writes to caches and temporary directories. This port uses **Library/Caches** on tvOS, and Application Support on the other targets. tvOS can purge caches; a local library is not a durable cloud backup. Keep a copy using Settings → View backup. Restore accepts this edition's JSON, not Android `.tachibk` files. The text-based backup UI is easier to use on desktop/mobile; an off-device TV transfer UI and cloud sync are not yet implemented.

Source URLs and optional stream headers are part of backups; keep them private. Failed saves are shown in the UI. Cached metadata stays available when a refresh fails; downloaded media is stored separately and is not included in JSON backups.

## Other platforms

```bash
flutter pub get
flutter run -d macos
flutter run -d <ios-or-android-device-id>
```

Stock Flutter 3.47.4 / Dart 3.13.3 was used for the host checks. tvOS builds use the pinned toolchain's Flutter 3.47.6. Do not run stock Flutter builds and tvOS builds concurrently in the same checkout because both generate `.dart_tool` files.

## Verify

```bash
flutter analyze
flutter test
./tool/test_tvos.sh <simulator-id>
# Also exercise a real HTTPS MP4; requires network access:
./tool/test_tvos.sh <simulator-id> --dart-define=TEST_NETWORK=true
.tools/flutter-tvos/bin/flutter-tvos build tvos --release --no-codesign
```

The native integration suite checks preferences, writable storage, navigation, AVPlayer playback, resume and keyboard/remote controls. With `TEST_NETWORK=true`, it also streams the anime sample, automatically downloads the full MP4, and plays the local copy. These tests run on both macOS and tvOS. A generated 12-second test clip makes the core player tests deterministic.

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/tvos_test.dart -d macos --dart-define=TEST_NETWORK=true
```

## Verify actual anime

```bash
flutter test test/live_source_test.dart --dart-define=LIVE_SOURCE=true
flutter drive --driver=test_driver/source_test.dart --target=integration_test/source_test.dart -d macos
.tools/flutter-tvos/bin/flutter-tvos drive --driver=test_driver/source_test.dart --target=integration_test/source_test.dart -d <tvOS-simulator-id>
```

The source integration test searches **Cowboy Bebop** through AnimeGG, loads its 26 episodes, resolves episode 1, checks a full-length video and advancing native playback, automatically downloads the entire episode, then reloads persisted state without any provider and verifies file-based playback resumes. Internet Archive source tests use deterministic metadata fixtures and verify direct MP4 episode construction. It saves platform-specific screenshots under `evidence/*-source-*.png`. Network availability can change; failures are shown rather than replaced with sample videos.

## Source policy

The app is built around source adapters and portable catalogs. It does not ship Android APK extension loading on Apple platforms, and it does not bundle piracy-source lists. To add a source, implement `AnimeSource` with searchable title metadata, stable episode pages or direct episodes, and `VideoStream` URLs that AVPlayer/video_player can open. For private or self-hosted content, a portable catalog is often easier than a compiled adapter.

Metadata-only APIs such as AniList are useful for ordering, posters and relations, but they do not provide playable video streams by themselves. Playable source adapters need direct MP4/M4V/MOV/HLS streams or an episode resolver that returns those streams.


### Plug in your own source URLs

The app has optional Dart rewrites for two extension shapes from the original Android ecosystem:

- `AnimeOnsenSource` for a JSON API shape with separate web, API and search hosts.
- `AnikotoSource` for an Anikoto-style HTML catalog where the final playable streams come from your own resolver endpoint.

The release does not ship those private source URLs. Put your own authorized URLs in a local JSON file and generate `lib/data/sources/user_source_config.dart`:

```bash
cp tools/source-config.example.json tools/source-config.local.json
python3 tools/plug_sources.py tools/source-config.local.json
flutter run -d macos
```

You can also avoid writing URLs into source files and pass them at build time:

```bash
python3 tools/plug_sources.py tools/source-config.local.json --defines
flutter run -d macos $(python3 tools/plug_sources.py tools/source-config.local.json --defines)
```

The JSON fields are:

| JSON path | Used by | What to put there |
| --- | --- | --- |
| `animeOnsen.name` | `AnimeOnsenSource.name` | Display name shown in Browse. |
| `animeOnsen.baseUrl` | web/deep links | HTTPS web app root, used for details links and request origin headers. |
| `animeOnsen.apiUrl` | catalog, details, episodes, video | HTTPS API root. The adapter calls `/v4/content/index`, `/v4/content/{id}/extensive`, `/v4/content/{id}/episodes`, `/v4/content/{id}/video/{episode}` and `/v4/image/210x300/{id}` below this URL. |
| `animeOnsen.searchUrl` | search | HTTPS search root. The adapter posts `{"q": "..."}` to `/indexes/content/search` below this URL. |
| `anikoto.name` | `AnikotoSource.name` | Display name shown in Browse. |
| `anikoto.baseUrl` | catalog/detail pages | HTTPS web app root. The adapter reads `/most-viewed/`, `/filter?keyword=...`, detail pages, and relative templates below this URL. |
| `anikoto.episodeListTemplate` | episodes | Path or HTTPS URL template returning JSON with an HTML payload in `result`, `html`, or `data`. Supports `{id}`. Default: `/ajax/episode/list/{id}`. |
| `anikoto.serverListTemplate` | reserved | Path or HTTPS URL template for server lists if you extend the scaffold. Supports `{episode}`. Default: `/ajax/server/list?servers={episode}`. |
| `anikoto.streamResolverTemplate` | playback | Path or HTTPS URL template returning `{"streams":[{"url":"https://...","label":"1080p"}]}`. Supports `{episode}` and `{epurl}`. Leave blank to browse/details only. |

The script validates that URL fields are `https://` and writes only the config file; it does not discover, download or recommend source sites. `tools/source-config.example.json` is the documented template. Keep your filled `tools/source-config.local.json` private.

## Playback buffering

Network playback aims to load three seconds ahead of the current position before starting, including after restoring a saved position. This startup wait is capped at five seconds; the native player then handles adaptive buffering and stall recovery. Offline files start immediately after initialization.

The player shows **Buffering…** while waiting for media, even with the controls hidden, and marks buffered progress in gray on the seek bar. Only contiguous loaded media at the current position counts toward the startup target. Pausing during a stall remains paused when the network recovers. Errors replace the buffering indicator with Retry; leaving the player cancels a pending startup wait.

For a shorter real-anime playback/buffer check without downloading the whole episode again:

```bash
flutter drive --driver=test_driver/source_test.dart --target=integration_test/source_test.dart -d macos --dart-define=PLAYBACK_ONLY=true
.tools/flutter-tvos/bin/flutter-tvos drive --driver=test_driver/source_test.dart --target=integration_test/source_test.dart -d <tvOS-simulator-id> --dart-define=PLAYBACK_ONLY=true
```

## Automatic downloads

Open **Downloads → Automatic downloads** to enable it. The app queues the next unwatched episode of each title in My List, including new episodes after you refresh a catalog. Finishing an episode queues the next one. Downloads run serially while the app process is active, using the current network. They do not continue after the app is quit or fully suspended by the OS. Automatic jobs are recalculated on the next launch; interrupted files restart from the beginning.

There is no app-level download size cap. Quality can be set to Highest or Smallest. Highest is the default. Wi-Fi only pauses automatic scheduling when enabled in this portable build; turn it off to resume queued automatic jobs. Downloads continue while the app process remains active in the background, and queued or interrupted jobs resume on the next launch. Cancelling/removing an episode prevents it being immediately downloaded again automatically. Playing downloaded media uses the local file; a purged/missing file falls back to streaming. macOS stores files in Application Support; Apple TV uses purgeable caches. Manual downloads are available per episode, per season and for a full title from the detail screen.

Only direct `.mp4`, `.m4v` and `.mov` URLs are downloadable in this implementation. HLS/DRM offline packages, native OS background transfer sessions, downloaded subtitle files and cross-device synchronization are not implemented. Online subtitles still require a network connection.


The original extension source and implemented adapter are documented in [docs/SOURCE_PORTING.md](docs/SOURCE_PORTING.md).

See [docs/VALIDATION.md](docs/VALIDATION.md) for observed results and [docs/PORT_STATUS.md](docs/PORT_STATUS.md) for feature parity. Logs and rendered evidence are in `evidence/`.

## Code map

- `lib/domain/`: catalog, episode, stream, subtitle and progress models.
- `lib/data/`: validated HTTP catalog/subtitle services, atomic storage and library state.
- `lib/ui/`: adaptive shell, shared focus controls, details and player.
- `tvos/`: dedicated tvOS Xcode runner, independent of `ios/`.
- `upstream/anikku/`: ignored reference checkout at `6e35b41f0cc7e375d15527bd61375435f998685a`.
- `.tools/flutter-tvos/`: ignored pinned community toolchain.

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for upstream attribution and sample-media credits.
