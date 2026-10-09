# Portable catalogs

Serve a UTF-8 JSON document over HTTPS and enter its URL in Browse → Add catalog. [catalog.example.json](catalog.example.json) is a schema example, using placeholder URLs; replace them with your own media. `assets/catalog/sample.json` contains tested public sample URLs.

| Field | Required | Meaning |
| --- | --- | --- |
| `version` | Yes | Integer `1` |
| `id` | Yes | Stable catalog ID; no `::` |
| `name` | Yes | Display name |
| `titles` | Yes | List of title objects |
| title `id`, `title`, `episodes` | Yes | Stable ID, name, ordered episode records |
| title `description`, `coverUrl`, `genres`, `year`, `status` | No | Presentation metadata |
| episode `id`, `title`, `streams` | Yes | Stable episode ID and at least one video stream |
| episode `season` | No | Season number used for grouping and sorting, default `1`; use `0` for specials |
| episode `number` | No | Number used for sorting within a season, default `1`; fractional specials supported |
| stream `url` | Yes | Direct media URL, not an HTML page |
| stream `label` | No | Quality/source label, default `Auto` |
| stream `headers` | No | String key/value HTTP headers passed to the video player |
| stream `subtitles` | No | External subtitle tracks |
| subtitle `url`, `label` | Yes | Subtitle URL and language/display name |
| subtitle `format` | No | `vtt` (default) or `srt` |

Keep IDs stable as catalogs change. Progress is keyed by catalog + title + episode ID. Title IDs must be unique within a catalog; episode IDs within a title. The `direct` and `blender-samples` catalog IDs are reserved. A different catalog URL cannot silently replace another source with the same ID.

Catalogs are limited to 5 MiB, subtitle files to 2 MiB. Requests have timeouts, and malformed files/HTTP failures are reported without replacing the existing source. URLs must be absolute HTTP(S), without embedded credentials. **Use HTTPS for media**: native Apple/Android transport policy may reject cleartext HTTP. Subtitle requests do not inherit stream headers; use a public or signed subtitle URL.

Refresh compares episode IDs for saved library titles and populates Updates. Missing unsaved titles are removed from Browse; saved titles/history are retained. Removing a source retains saved library entries and watched history. A catalog is a data document, not executable code and not an Android extension repository.

Multiple `streams` provide alternatives selected using the resolution dropdown in the player. HLS adaptive quality remains the native player's responsibility. Subtitle selection cycles available tracks then Off. Stream changes reset subtitle selection. Auto-next follows season and episode order. Playback marks episodes watched at 95%; manual Mark unwatched clears the saved position.

Do not publish private access headers in a public catalog. Backups include those headers and media URLs. The app has no provider login, browser challenge or DRM license flow.
