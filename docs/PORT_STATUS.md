# Port status

Reference: komikku-app/anikku at `6e35b41f0cc7e375d15527bd61375435f998685a`.

The original Android app is a large Kotlin/Compose application with years of features. This first Flutter edition implements its core collection/watch workflow. It does not claim full parity.

| Upstream area | Flutter edition |
| --- | --- |
| Library and categories | Implemented: local profiles, favorites, named categories, watchlist statuses, search and sorting |
| Browse and global search | Native AnimeGG popular list and remote search, local search across portable catalogs, genre/year/status/source/availability/language filters, A-Z/last-updated/release-date/sub-dub sorting |
| Sources/extensions | Native Dart AnimeGG source adapter, portable JSON catalogs and direct URLs; no APK runtime |
| Anime detail and episode lists | Implemented, with season grouping, season watched/start-over actions, multiple streams, watched controls and configurable skip intro/recap times |
| Player | Native video via video_player + explicit tvOS implementation; AVPlayer-compatible codecs, buffering indicator, next-episode preloading, seek preview card, keyboard shortcuts, highest-by-default resolution dropdown, fullscreen, AirPlay and skip intro/recap controls |
| Watch progress/history | Per-profile Continue Watching, latest-episode resume, hide/reset history, 95% completion, new-episode tracking, next episode, restart, speed and timeline seek |
| Subtitles | External SRT/VTT; embedded track selection and ASS styling are not implemented |
| Updates | Manual source/catalog refresh and detection of new episodes for saved titles |
| Backups | Edition-specific JSON view/restore; Android protobuf backups not imported |
| Local media/download queue | Progressive MP4/M4V/MOV per-episode, per-season and full-title downloads; automatic next-unwatched queue; grouped by anime; persisted background-resumable queue; Highest/Smallest quality rules; Wi-Fi-only automatic pause mode; no app-level size cap; cancel/retry and local playback. No HLS/DRM offline packages. |
| MyAnimeList/AniList/Kitsu/other trackers | Not implemented |
| SyncYomi/Google Drive/cloud sync | Not implemented |
| Recommendations, related titles, merge, migration | Local genre-based related titles, recently added/completed/short-watch discovery rails and season grouping implemented. No provider recommendations, title merge or migration. |
| Dynamic theme palettes, adult filters, localization | Not implemented; English dark theme |
| Torrent, Discord presence, app updater | Not implemented |
| Cast | AirPlay picker on Apple platforms; Chromecast and custom receiver discovery are not implemented |
| Android TV/Fire TV remote behavior | Shared focus UI; not verified on hardware |
| Apple TV | Dedicated runner, community engine, native storage/player and simulator integration tests |
| App Store/TestFlight | Not submitted; physical device/signing/review still required |

UI and data code are separated so additional source adapters, trackers and synchronization can be implemented without changing the television interaction layer. Source access is data-driven and contains no Android runtime dependency. `NOTICE` preserves upstream attribution; the original reference checkout remains unmodified.
