import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/watch_progress.dart';
import 'catalog_service.dart';
import 'download_manager.dart';
import 'library_repository.dart';
import 'sources/anime_source.dart';

class LibraryModel extends ChangeNotifier {
  LibraryModel({
    required this._store,
    required CatalogService catalogs,
    this.downloads,
    this.sources = const [],
    this.includeSamples = true,
  }) : _service = catalogs {
    downloads?.addListener(_downloadsChanged);
  }
  final DownloadManager? downloads;
  void _downloadsChanged() {
    if (!_disposed) notifyListeners();
  }

  final List<AnimeSource> sources;
  final bool includeSamples;
  bool searching = false;
  bool sourceLoading = false;
  List<Anime>? searchResults;
  int _searchGeneration = 0;
  bool _scheduling = false;
  final Set<String> _autoAttempted = {};

  void scheduleDownloads() {
    final manager = downloads;
    if (_scheduling ||
        manager == null ||
        !manager.ready ||
        !manager.automatic ||
        _disposed) {
      return;
    }
    _scheduling = true;
    unawaited(() async {
      try {
        for (final item in library) {
          if (_disposed || !manager.automatic) break;
          var anime = item;
          try {
            if (anime.episodes.isEmpty) anime = await ensureDetails(anime);
            final episode = resumeEpisode(anime);
            if (episode == null || !manager.shouldSchedule(anime, episode)) {
              continue;
            }
            final key = anime.episodeKey(episode);
            if (!_autoAttempted.add(key)) continue;
            final resolved = await resolveEpisode(anime, episode);
            if (!_disposed && manager.automatic && isFavorite(anime)) {
              manager.schedule([(anime: anime, episode: resolved)]);
            }
          } catch (e) {
            error = 'Automatic download could not be prepared: $e';
            if (!_disposed) notifyListeners();
          }
        }
      } finally {
        _scheduling = false;
      }
    }());
  }

  AnimeSource? _source(Anime anime) =>
      sources.where((s) => s.id == anime.sourceId).firstOrNull;
  final Map<String, Future<Anime>> _detailRequests = {};
  Future<Anime> ensureDetails(Anime anime, {bool refresh = false}) async {
    anime = current(anime);
    final source = _source(anime);
    if (source == null || (!refresh && anime.episodes.isNotEmpty)) return anime;
    final key = anime.key;
    if (_detailRequests[key] case final request?) return request;
    final request = () async {
      final detailed = await source.details(anime);
      final oldIds = anime.episodes.map((e) => e.id).toSet();
      if (isFavorite(anime)) {
        _updates.addAll(
          detailed.episodes
              .where((e) => !oldIds.contains(e.id))
              .map(detailed.episodeKey),
        );
      }
      _titles[key] = detailed;
      _notify();
      await _persist();
      return detailed;
    }();
    _detailRequests[key] = request;
    try {
      return await request;
    } finally {
      _detailRequests.remove(key);
    }
  }

  Future<Episode> resolveEpisode(Anime anime, Episode episode) async {
    if (episode.streams.isNotEmpty) return episode;
    final source = _source(anime);
    if (source == null) {
      throw const FormatException('This source is not installed.');
    }
    final streams = await source.resolve(anime, episode);
    if (streams.isEmpty) {
      throw const FormatException('No playable video was found.');
    }
    return Episode(
      id: episode.id,
      title: episode.title,
      number: episode.number,
      season: episode.season,
      streams: streams,
      sourceUrl: episode.sourceUrl,
    );
  }

  Future<void> downloadEpisode(Anime anime, Episode episode) async {
    try {
      final resolved = await resolveEpisode(anime, episode);
      if (DownloadManager.downloadable(
            resolved,
            quality: downloads?.quality ?? 'Highest',
          ) ==
          null) {
        throw const FormatException('This episode is streaming-only.');
      }
      downloads?.enqueue(anime, resolved);
    } catch (e) {
      error = 'Download unavailable: $e';
      _notify();
    }
  }

  Future<bool> downloadEpisodes(
    Anime anime,
    Iterable<Episode> episodes,
  ) => _operation(() async {
    final manager = downloads;
    if (manager == null) {
      throw const FormatException('Downloads are not available.');
    }
    final resolvedAnime = current(anime);
    final available = {
      for (final episode in resolvedAnime.episodes) episode.id: episode,
    };
    final selected = [
      for (final episode in episodes) available[episode.id] ?? episode,
    ];
    if (selected.isEmpty) {
      throw const FormatException('There are no episodes to download.');
    }
    var queued = 0;
    var alreadyQueued = 0;
    final failures = <String>[];
    for (final episode in selected) {
      final existing = manager.entry(resolvedAnime, episode);
      if (existing != null && existing.status != DownloadStatus.failed) {
        alreadyQueued++;
        continue;
      }
      try {
        final resolved = await resolveEpisode(resolvedAnime, episode);
        if (DownloadManager.downloadable(resolved, quality: manager.quality) ==
            null) {
          failures.add('${episode.title}: streaming-only');
          continue;
        }
        manager.enqueue(resolvedAnime, resolved);
        queued++;
      } catch (e) {
        failures.add(
          '${episode.title}: ${e.toString().replaceFirst('FormatException: ', '')}',
        );
      }
    }
    if (queued == 0) {
      if (failures.isNotEmpty) {
        throw FormatException(
          'No episodes could be queued. ${failures.join('; ')}',
        );
      }
      if (alreadyQueued > 0) {
        throw const FormatException(
          'All selected episodes are already queued or downloaded.',
        );
      }
    }
    if (failures.isNotEmpty) {
      error =
          'Queued $queued download${queued == 1 ? '' : 's'}, but ${failures.length} episode${failures.length == 1 ? '' : 's'} could not be queued: ${failures.take(3).join('; ')}';
    }
  });

  Future<void> searchSources(String query) async {
    final generation = ++_searchGeneration;
    if (query.trim().isEmpty) {
      searchResults = null;
      searching = false;
      _notify();
      return;
    }
    searching = true;
    searchResults = [];
    _notify();
    final found = <Anime>[];
    final failures = <String>[];
    for (final source in sources) {
      try {
        found.addAll((await source.browse(query: query)).titles);
      } catch (e) {
        failures.add('${source.name}: $e');
      }
    }
    if (generation != _searchGeneration || _disposed) return;
    for (final anime in found) {
      _titles.putIfAbsent(anime.key, () => anime);
    }
    searchResults = found.map(current).toList();
    searching = false;
    if (failures.isNotEmpty) error = failures.join('\n');
    _notify();
  }

  Future<void> _browseSources() async {
    if (sources.isEmpty) return;
    sourceLoading = true;
    _notify();
    for (final source in sources) {
      try {
        final page = await source.browse();
        for (final anime in page.titles) {
          _titles.putIfAbsent(anime.key, () => anime);
        }
        _catalogs[source.id] = Catalog(
          id: source.id,
          name: source.name,
          titles: page.titles,
        );
      } catch (e) {
        error = '${source.name} is unavailable: $e';
      }
    }
    sourceLoading = false;
    _notify();
    await _persist();
  }

  Future<void> setAutomaticDownloads(bool enabled) async {
    if (enabled) _autoAttempted.clear();
    await downloads?.setAutomatic(enabled);
    scheduleDownloads();
  }

  Future<void> setDownloadQuality(String value) async {
    await downloads?.setQuality(value);
    scheduleDownloads();
  }

  Future<void> setWifiOnlyDownloads(bool value) async {
    await downloads?.setWifiOnly(value);
    scheduleDownloads();
  }

  final StateStore _store;
  final CatalogService _service;
  final Map<String, Anime> _titles = {};
  final Map<String, Catalog> _catalogs = {};
  final Set<String> _favorites = {};
  final Map<String, WatchProgress> _progress = {};
  final Map<String, String> _categories = {};
  final Map<String, String> _watchStatuses = {};
  final Map<String, int> _skipIntroSeconds = {};
  final Map<String, int> _skipRecapSeconds = {};
  final Set<String> _updates = {};
  final Set<String> _hiddenContinue = {};
  final Set<String> _profiles = {'Default'};
  final Map<String, Map<String, dynamic>> _profileData = {};
  Future<void> _saveQueue = Future.value();
  bool loading = true;
  bool busy = false;
  String? error;
  bool autoPlay = true;
  String activeProfile = 'Default';
  String preferredLanguage = 'Any';
  Map<String, String> sourceHealth = {};
  bool _disposed = false;
  bool _canPersist = false;

  List<Anime> get titles => List.unmodifiable(_titles.values);
  List<Anime> get library => List.unmodifiable(
    _titles.values.where((e) => _favorites.contains(e.key)),
  );
  List<Catalog> get catalogs => List.unmodifiable(_catalogs.values);
  List<String> get profiles => _profiles.toList()..sort();
  List<String> get categories =>
      _categories.values.where((e) => e.isNotEmpty).toSet().toList()..sort();
  List<Anime> get updates => library
      .where((a) => a.episodes.any((e) => _updates.contains(a.episodeKey(e))))
      .toList();
  List<Anime> get history =>
      _titles.values
          .where((a) => a.episodes.any((e) => progress(a, e) != null))
          .toList()
        ..sort((a, b) => lastWatched(b).compareTo(lastWatched(a)));
  List<Anime> get continueWatching => history
      .where(
        (a) => !_hiddenContinue.contains(a.key) && resumeEpisode(a) != null,
      )
      .toList();

  /// Resume the most recently started episode, even when earlier ones were skipped.
  /// A completed episode advances to the next unwatched episode in catalog order.
  Episode? resumeEpisode(Anime anime) {
    final started =
        anime.episodes.where((e) => progress(anime, e) != null).toList()..sort(
          (a, b) => progress(
            anime,
            b,
          )!.updatedAt.compareTo(progress(anime, a)!.updatedAt),
        );
    if (started.isEmpty) return nextEpisode(anime);
    final latest = started.first;
    if (!progress(anime, latest)!.watched) return latest;
    final index = anime.episodes.indexOf(latest);
    for (final episode in anime.episodes.skip(index + 1)) {
      if (!(progress(anime, episode)?.watched ?? false)) return episode;
    }
    return null;
  }

  Future<void> hideFromContinue(Anime anime) async {
    _hiddenContinue.add(anime.key);
    _notify();
    await _persist();
  }

  Future<void> clearHistory({Anime? anime}) async {
    if (anime == null) {
      _progress.clear();
      _hiddenContinue.clear();
    } else {
      for (final episode in anime.episodes) {
        _progress.remove(anime.episodeKey(episode));
      }
      _hiddenContinue.remove(anime.key);
    }
    _notify();
    await _persist();
  }

  List<Anime> relatedTo(Anime anime) => titles
      .where(
        (a) =>
            a.key != anime.key && a.genres.any((g) => anime.genres.contains(g)),
      )
      .toList();

  bool isFavorite(Anime anime) => _favorites.contains(anime.key);
  String category(Anime anime) => _categories[anime.key] ?? '';
  String watchStatus(Anime anime) => _watchStatuses[anime.key] ?? 'Watching';
  int skipIntroSeconds(Anime anime) => _skipIntroSeconds[anime.key] ?? 0;
  int skipRecapSeconds(Anime anime) => _skipRecapSeconds[anime.key] ?? 0;
  WatchProgress? progress(Anime anime, Episode episode) =>
      _progress[anime.episodeKey(episode)];
  bool isNew(Anime anime, Episode episode) =>
      _updates.contains(anime.episodeKey(episode));
  String sourceName(Anime anime) =>
      _source(anime)?.name ?? _catalogs[anime.sourceId]?.name ?? 'Direct URL';
  Anime current(Anime anime) => _titles[anime.key] ?? anime;
  DateTime lastWatched(Anime anime) => anime.episodes
      .map((e) => progress(anime, e)?.updatedAt ?? DateTime(1970))
      .fold(DateTime(1970), (a, b) => a.isAfter(b) ? a : b);
  Episode? nextEpisode(Anime anime) {
    final remaining = anime.episodes
        .where((e) => !(progress(anime, e)?.watched ?? false))
        .toList();
    return remaining.isEmpty ? null : remaining.first;
  }

  Future<void> initialize() async {
    try {
      final saved = await _store.read();
      if (saved != null) _restore(saved);
      _canPersist = true;
      if (includeSamples) {
        final sample = await _service.sample();
        _merge(sample, trackUpdates: false);
      } else {
        final sampleIds =
            _catalogs.values.where((c) => c.isSample).map((c) => c.id).toSet()
              ..add('blender-samples');
        _catalogs.removeWhere((key, _) => sampleIds.contains(key));
        _titles.removeWhere((_, a) => sampleIds.contains(a.sourceId));
      }
    } catch (e) {
      error = 'Could not load library: $e';
    }
    await downloads?.initialize();
    if (!includeSamples && downloads != null) {
      for (final entry
          in downloads!.entries
              .where((e) => e.key.startsWith('blender-samples::'))
              .toList()) {
        await downloads!.remove(entry);
      }
    }
    loading = false;
    _notify();
    if (sources.isNotEmpty) await _browseSources();
  }

  Future<void> _persist() {
    if (!_canPersist) {
      error = 'Storage could not be loaded. Restart or restore a valid backup before saving.';
      _notify();
      return Future.value();
    }
    final snapshot = _snapshot();
    _saveQueue = _saveQueue.then((_) => _store.write(snapshot)).catchError((
      Object e,
    ) {
      error = 'Could not save library: $e';
      _notify();
    });
    return _saveQueue;
  }

  void _notify() {
    scheduleDownloads();
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> switchProfile(String name) async {
    final cleaned = requiredText(name, 'profile name');
    _profileData[activeProfile] = _profileSnapshot();
    _profiles.add(cleaned);
    activeProfile = cleaned;
    _applyProfile(_profileData[cleaned] ?? const {});
    _notify();
    await _persist();
  }

  Future<void> setWatchStatus(Anime anime, String value) async {
    _watchStatuses[anime.key] = value;
    if (!_favorites.contains(anime.key)) _favorites.add(anime.key);
    _titles[anime.key] = anime;
    _notify();
    await _persist();
  }

  Future<void> setSkipTimes(Anime anime, int intro, int recap) async {
    if (intro <= 0) {
      _skipIntroSeconds.remove(anime.key);
    } else {
      _skipIntroSeconds[anime.key] = intro.clamp(0, 600);
    }
    if (recap <= 0) {
      _skipRecapSeconds.remove(anime.key);
    } else {
      _skipRecapSeconds[anime.key] = recap.clamp(0, 600);
    }
    _notify();
    await _persist();
  }

  Future<void> setPreferredLanguage(String value) async {
    preferredLanguage = value;
    _notify();
    await _persist();
  }

  Future<void> markSeasonWatched(Anime anime, int season, bool watched) async {
    for (final episode in anime.episodes.where((e) => e.season == season)) {
      await markWatched(anime, episode, watched);
    }
  }

  Future<void> clearSeasonProgress(Anime anime, int season) async {
    for (final episode in anime.episodes.where((e) => e.season == season)) {
      _progress.remove(anime.episodeKey(episode));
    }
    _hiddenContinue.remove(anime.key);
    _notify();
    await _persist();
  }

  Future<void> checkSourceHealth() async {
    final results = <String, String>{};
    for (final source in sources) {
      try {
        final page = await source.browse();
        if (page.titles.isEmpty) {
          results[source.name] = 'No listings returned';
        } else {
          results[source.name] = 'Browse OK';
        }
      } catch (e) {
        results[source.name] = 'Unavailable: $e';
      }
    }
    sourceHealth = results;
    _notify();
  }

  Future<void> toggleFavorite(Anime anime) async {
    _titles[anime.key] = anime;
    if (!_favorites.add(anime.key)) {
      _favorites.remove(anime.key);
      _watchStatuses.remove(anime.key);
    } else {
      _watchStatuses.putIfAbsent(anime.key, () => 'Watching');
    }
    _notify();
    await _persist();
  }

  Future<void> setCategory(Anime anime, String value) async {
    _categories[anime.key] = value.trim();
    _notify();
    await _persist();
  }

  Future<void> setAutoPlay(bool value) async {
    autoPlay = value;
    _notify();
    await _persist();
  }

  Future<void> markWatched(Anime anime, Episode episode, bool watched) async {
    final old = progress(anime, episode);
    _progress[anime.episodeKey(episode)] = WatchProgress(
      positionMs: watched ? old?.durationMs ?? 0 : 0,
      durationMs: old?.durationMs ?? 0,
      updatedAt: DateTime.now(),
      watched: watched,
    );
    _updates.remove(anime.episodeKey(episode));
    _notify();
    await _persist();
  }

  Future<void> recordProgress(
    Anime anime,
    Episode episode,
    Duration position,
    Duration duration,
  ) async {
    if (duration.inMilliseconds <= 0) return;
    _hiddenContinue.remove(anime.key);
    final key = anime.episodeKey(episode);
    final watched =
        (_progress[key]?.watched ?? false) ||
        position.inMilliseconds / duration.inMilliseconds >= .95;
    _progress[key] = WatchProgress(
      positionMs: position.inMilliseconds.clamp(0, duration.inMilliseconds),
      durationMs: duration.inMilliseconds,
      updatedAt: DateTime.now(),
      watched: watched,
    );
    _updates.remove(key);
    _notify();
    await _persist();
  }

  Future<bool> importCatalog(String value) => _operation(() async {
    final catalog = await _service.fetch(networkUri(value, 'catalog URL'));
    if (catalog.id == 'direct' ||
        catalog.id == 'blender-samples' ||
        sources.any((s) => s.id == catalog.id)) {
      throw const FormatException('This catalog ID is reserved.');
    }
    final existing = _catalogs[catalog.id];
    if (existing != null && existing.url != catalog.url) {
      throw const FormatException(
        'A different URL already uses this catalog ID.',
      );
    }
    _merge(catalog);
    await _persist();
  });
  Future<bool> refresh() => _operation(() async {
    final failures = <String>[];
    _autoAttempted.clear();
    await _browseSources();
    for (final anime in library.where((a) => _source(a) != null)) {
      try {
        await ensureDetails(anime, refresh: true);
      } catch (e) {
        failures.add('${anime.title}: $e');
      }
    }
    for (final catalog in catalogs.where((c) => c.url != null)) {
      try {
        final updated = await _service.fetch(catalog.url!);
        if (updated.id != catalog.id) {
          throw const FormatException('Catalog ID changed.');
        }
        _merge(updated);
      } catch (e) {
        failures.add('${catalog.name}: $e');
      }
    }
    await _persist();
    if (failures.isNotEmpty) throw FormatException(failures.join('\n'));
  });
  Future<void> removeCatalog(Catalog catalog) async {
    _catalogs.remove(catalog.id);
    _titles.removeWhere(
      (key, value) =>
          value.sourceId == catalog.id &&
          !_favorites.contains(key) &&
          !value.episodes.any(
            (e) => _progress.containsKey(value.episodeKey(e)),
          ),
    );
    _notify();
    await _persist();
  }

  Future<bool> addDirect(String title, String url) => _operation(() async {
    final uri = networkUri(url, 'video URL');
    final id = base64Url.encode(utf8.encode(uri.toString()));
    final anime = Anime(
      id: id,
      sourceId: 'direct',
      title: requiredText(title, 'title'),
      episodes: [
        Episode(
          id: 'video',
          title: 'Play video',
          number: 1,
          streams: [VideoStream(url: uri)],
        ),
      ],
      genres: const ['Direct video'],
    );
    _titles[anime.key] = anime;
    _favorites.add(anime.key);
    _watchStatuses[anime.key] = 'Watching';
    await _persist();
  });
  Future<bool> _operation(Future<void> Function() action) async {
    if (busy) return false;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      return error == null;
    } catch (e) {
      error = e.toString().replaceFirst('FormatException: ', '');
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void _merge(Catalog catalog, {bool trackUpdates = true}) {
    for (final anime in catalog.titles) {
      final previous = _titles[anime.key];
      if (trackUpdates && previous != null && _favorites.contains(anime.key)) {
        final oldIds = previous.episodes.map((e) => e.id).toSet();
        _updates.addAll(
          anime.episodes
              .where((e) => !oldIds.contains(e.id))
              .map(anime.episodeKey),
        );
      }
      _titles[anime.key] = anime;
    }
    final keys = catalog.titles.map((a) => a.key).toSet();
    _titles.removeWhere(
      (key, value) =>
          value.sourceId == catalog.id &&
          !keys.contains(key) &&
          !_favorites.contains(key) &&
          !value.episodes.any(
            (e) => _progress.containsKey(value.episodeKey(e)),
          ),
    );
    _catalogs[catalog.id] = catalog;
  }

  Map<String, dynamic> _profileSnapshot() => {
    'hiddenContinue': _hiddenContinue.toList(),
    'favorites': _favorites.toList(),
    'progress': _progress.map((key, value) => MapEntry(key, value.toJson())),
    'categories': Map<String, String>.of(_categories),
    'updates': _updates.toList(),
    'watchStatuses': Map<String, String>.of(_watchStatuses),
    'skipIntroSeconds': Map<String, int>.of(_skipIntroSeconds),
    'skipRecapSeconds': Map<String, int>.of(_skipRecapSeconds),
  };

  Map<String, dynamic> _snapshot() {
    _profileData[activeProfile] = _profileSnapshot();
    return {
      'version': 1,
      'activeProfile': activeProfile,
      'profiles': _profiles.toList(),
      'profileData': Map<String, dynamic>.of(_profileData),
      'hiddenContinue': _hiddenContinue.toList(),
      'titles': _titles.values
          .map((a) => {...a.toJson(), 'sourceId': a.sourceId})
          .toList(),
      'catalogs': catalogs
          .map(
            (c) => {
              'catalog': c.toJson(),
              'url': c.url?.toString(),
              'isSample': c.isSample,
            },
          )
          .toList(),
      'favorites': _favorites.toList(),
      'progress': _progress.map((key, value) => MapEntry(key, value.toJson())),
      'categories': Map<String, String>.of(_categories),
      'updates': _updates.toList(),
      'watchStatuses': Map<String, String>.of(_watchStatuses),
      'skipIntroSeconds': Map<String, int>.of(_skipIntroSeconds),
      'skipRecapSeconds': Map<String, int>.of(_skipRecapSeconds),
      'autoPlay': autoPlay,
      'preferredLanguage': preferredLanguage,
    };
  }

  String exportBackup() =>
      const JsonEncoder.withIndent('  ').convert(_snapshot());
  Future<bool> importBackup(String json) => _operation(() async {
    _restore(jsonDecode(json) as Map<String, dynamic>);
    _canPersist = true;
    await _persist();
  });
  void _restore(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    // Parse everything before replacing live state, so invalid backups are atomic.
    final titles = (json['titles'] as List<dynamic>).map((e) {
      final m = e as Map<String, dynamic>;
      return Anime.fromJson(m, requiredText(m['sourceId'], 'source id'));
    }).toList();
    final catalogs = (json['catalogs'] as List<dynamic>).map((e) {
      final m = e as Map<String, dynamic>;
      return Catalog.fromJson(
        m['catalog'] as Map<String, dynamic>,
        url: m['url'] == null ? null : networkUri(m['url'], 'catalog URL'),
        isSample: m['isSample'] as bool? ?? false,
      );
    }).toList();
    final profileNames = (json['profiles'] as List<dynamic>? ?? ['Default'])
        .cast<String>();
    final profileData = (json['profileData'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as Map<String, dynamic>));
    final activeProfile = json['activeProfile'] as String? ?? 'Default';
    final activeProfileData = profileData[activeProfile] ?? json;
    final autoPlay = json['autoPlay'] as bool? ?? true;
    final preferredLanguage = json['preferredLanguage'] as String? ?? 'Any';
    _titles
      ..clear()
      ..addEntries(titles.map((a) => MapEntry(a.key, a)));
    _catalogs
      ..clear()
      ..addEntries(catalogs.map((c) => MapEntry(c.id, c)));
    _profiles
      ..clear()
      ..addAll(profileNames.isEmpty ? ['Default'] : profileNames);
    _profileData
      ..clear()
      ..addAll(profileData);
    this.activeProfile = _profiles.contains(activeProfile)
        ? activeProfile
        : _profiles.first;
    _applyProfile(activeProfileData);
    this.autoPlay = autoPlay;
    this.preferredLanguage = preferredLanguage;
  }

  void _applyProfile(Map<String, dynamic> data) {
    _favorites
      ..clear()
      ..addAll((data['favorites'] as List<dynamic>? ?? []).cast<String>());
    _progress
      ..clear()
      ..addAll(
        (data['progress'] as Map<String, dynamic>? ?? {}).map(
          (k, v) =>
              MapEntry(k, WatchProgress.fromJson(v as Map<String, dynamic>)),
        ),
      );
    _categories
      ..clear()
      ..addAll(
        (data['categories'] as Map<String, dynamic>? ?? {})
            .cast<String, String>(),
      );
    _updates
      ..clear()
      ..addAll((data['updates'] as List<dynamic>? ?? []).cast<String>());
    _hiddenContinue
      ..clear()
      ..addAll((data['hiddenContinue'] as List<dynamic>? ?? []).cast<String>());
    _watchStatuses
      ..clear()
      ..addAll(
        (data['watchStatuses'] as Map<String, dynamic>? ?? {})
            .cast<String, String>(),
      );
    _skipIntroSeconds
      ..clear()
      ..addAll(
        (data['skipIntroSeconds'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
      );
    _skipRecapSeconds
      ..clear()
      ..addAll(
        (data['skipRecapSeconds'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
      );
  }

  @override
  void dispose() {
    _disposed = true;
    _service.dispose();
    for (final source in sources) {
      source.dispose();
    }
    downloads?.removeListener(_downloadsChanged);
    downloads?.dispose();
    super.dispose();
  }
}
