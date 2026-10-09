# Native anime source — 7 October 2026

Anikku's Android `ExtensionApi` reads a user-added repository's `index.min.json`, then installs APKs. That JSON lists extensions; it is not an anime/video catalog. The Flutter catalog format is separate.

Published extension source is available at [Yuzono anime-extensions](https://github.com/yuzono/anime-extensions), Apache-2.0, inspected at revision `212743bb47c364de32ecbd0e0bcfc766815a71fd`. APK decompilation was unnecessary. The implemented adapter is based on `src/en/animegg/src/eu/kanade/tachiyomi/animeextension/en/animegg/AnimeGG.kt`.

## Implemented path

`lib/data/sources/animegg_source.dart` implements the `AnimeSource` interface in Dart:

1. Browse the popular list at `https://www.animegg.org/popular-series`.
2. Search `/search/?q=...` and parse title cards.
3. Load title details and episode links only when needed.
4. Fetch an episode page and its subbed/dubbed player embeds.
5. Parse the published `videoSources` data into native MP4 streams and Referer headers.
6. Resolve URLs afresh when starting playback or downloads; persist stable title/episode IDs and pages, not temporary CDN links.

The app uses this source at startup. Search requests are debounced and stale responses cannot replace a newer query. Saved metadata and history survive source failures. Episode rows are revealed in batches of 50. The player can resume a downloaded episode without contacting the source, including after restarting the app.

Automatic downloads resolve the next unwatched episode for each saved title, respect the existing cap/dismissal policy, and run while the app is open. A failed download has a manual Retry action that resolves a new link. MP4 streams are supported; HLS offline packages are not.

## Verification

The live HTTP test found **Cowboy Bebop**, its **26 episodes**, and subbed/dubbed streams. Episode 1 returned HTTP 206, `video/mp4`, and an MP4 `ftyp` header. This is separate from the native integration test, which checks actual decoding, advancing playback, full automatic download and offline resume on each Apple target. See `docs/VALIDATION.md` and `evidence/*-source-integration.log` for the completed target results.

Fixture tests cover listing/search parsing, episode sorting/IDs, fresh links, missing mirrors, unavailable pages, cached state, refresh updates and search races. Availability for every title or region is not implied by testing one episode. The app displays errors when a source fails; it does not substitute stock videos.

## Rejected candidate

Anichi's listings, search and episode metadata worked, but its tested video CDN hosts refused connections from this machine. It is not enabled or shipped as a working provider. The investigation and prototype remain only in the ignored `upstream/extension-reference/` directory.

No Android APK runtime, CAPTCHA solver, login bypass or DRM removal is implemented. Other extensions require their own portable adapters and native playback verification.
