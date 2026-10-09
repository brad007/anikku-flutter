import 'dart:convert';

import 'package:anikku/data/library_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  late MemoryStore store;
  late FixtureCatalogService service;
  late LibraryModel model;
  setUp(() async {
    store = MemoryStore();
    service = FixtureCatalogService();
    model = LibraryModel(store: store, catalogs: service);
    await model.initialize();
  });
  tearDown(() => model.dispose());

  test('samples stay out of Library until explicitly saved', () {
    expect(model.titles, hasLength(1));
    expect(model.library, isEmpty);
  });
  test(
    'favorites, categories, progress and settings survive restart',
    () async {
      final anime = model.titles.first;
      await model.toggleFavorite(anime);
      await model.setCategory(anime, 'Weekend');
      await model.recordProgress(
        anime,
        anime.episodes.first,
        const Duration(seconds: 25),
        const Duration(seconds: 100),
      );
      await model.setAutoPlay(false);
      final restored = LibraryModel(
        store: store,
        catalogs: FixtureCatalogService(),
      );
      await restored.initialize();
      expect(restored.library.single.key, anime.key);
      expect(restored.category(anime), 'Weekend');
      expect(restored.progress(anime, anime.episodes.first)?.positionMs, 25000);
      expect(restored.autoPlay, isFalse);
      restored.dispose();
    },
  );
  test(
    '95 percent watched selects the next episode and unwatch resets resume',
    () async {
      final anime = model.titles.first;
      await model.recordProgress(
        anime,
        anime.episodes.first,
        const Duration(seconds: 95),
        const Duration(seconds: 100),
      );
      expect(model.nextEpisode(anime)?.id, '2');
      await model.markWatched(anime, anime.episodes.first, false);
      expect(model.nextEpisode(anime)?.id, '1');
      expect(model.progress(anime, anime.episodes.first)?.positionMs, 0);
    },
  );
  test(
    'continue watching resumes the latest episode even after skipping one',
    () async {
      final anime = model.titles.first;
      await model.recordProgress(
        anime,
        anime.episodes.last,
        const Duration(seconds: 20),
        const Duration(seconds: 100),
      );
      expect(model.resumeEpisode(anime)?.id, '2');
      expect(model.continueWatching.single.key, anime.key);
      await model.recordProgress(
        anime,
        anime.episodes.last,
        const Duration(seconds: 98),
        const Duration(seconds: 100),
      );
      expect(model.continueWatching, isEmpty);
      expect(model.history, hasLength(1));
    },
  );
  test(
    'hide continue keeps progress, survives restart, and playback restores it',
    () async {
      final anime = model.titles.first;
      await model.recordProgress(
        anime,
        anime.episodes.first,
        const Duration(seconds: 25),
        const Duration(seconds: 100),
      );
      await model.hideFromContinue(anime);
      expect(model.continueWatching, isEmpty);
      expect(model.progress(anime, anime.episodes.first)!.positionMs, 25000);
      final restored = LibraryModel(
        store: store,
        catalogs: FixtureCatalogService(),
      );
      await restored.initialize();
      expect(restored.continueWatching, isEmpty);
      await restored.recordProgress(
        anime,
        anime.episodes.first,
        const Duration(seconds: 30),
        const Duration(seconds: 100),
      );
      expect(restored.continueWatching, hasLength(1));
      restored.dispose();
    },
  );
  test('clear history removes progress but preserves My List', () async {
    final anime = model.titles.first;
    await model.toggleFavorite(anime);
    await model.recordProgress(
      anime,
      anime.episodes.first,
      const Duration(seconds: 25),
      const Duration(seconds: 100),
    );
    await model.clearHistory(anime: anime);
    expect(model.history, isEmpty);
    expect(model.continueWatching, isEmpty);
    expect(model.library, hasLength(1));
    final restored = LibraryModel(
      store: store,
      catalogs: FixtureCatalogService(),
    );
    await restored.initialize();
    expect(restored.history, isEmpty);
    expect(restored.library, hasLength(1));
    restored.dispose();
  });
  test('refresh reports new episodes and keeps playback progress', () async {
    expect(
      await model.importCatalog('https://example.com/catalog.json'),
      isTrue,
    );
    final anime = model.titles.firstWhere((a) => a.sourceId == 'test');
    await model.toggleFavorite(anime);
    await model.recordProgress(
      anime,
      anime.episodes.first,
      const Duration(seconds: 5),
      const Duration(seconds: 100),
    );
    service.episodes = 3;
    await model.refresh();
    expect(model.updates.single.episodes, hasLength(3));
    expect(model.progress(anime, anime.episodes.first)?.positionMs, 5000);
    expect(
      model.isNew(model.updates.single, model.updates.single.episodes.last),
      isTrue,
    );
  });
  test('a failed refresh preserves cached titles', () async {
    await model.importCatalog('https://example.com/catalog.json');
    service.fail = true;
    expect(await model.refresh(), isFalse);
    expect(model.titles, hasLength(2));
    expect(model.error, contains('Network unavailable'));
  });
  test('malformed backups are atomic', () async {
    await model.toggleFavorite(model.titles.first);
    final before = model.exportBackup();
    final broken = jsonDecode(before) as Map<String, dynamic>;
    broken['autoPlay'] = 'bad';
    expect(await model.importBackup(jsonEncode(broken)), isFalse);
    expect(model.exportBackup(), before);
  });
  test('catalog identity collisions do not replace a source', () async {
    await model.importCatalog('https://example.com/a.json');
    expect(await model.importCatalog('https://example.com/b.json'), isFalse);
    expect(model.catalogs.last.url.toString(), 'https://example.com/a.json');
  });
  test(
    'direct URL adds a playable favorite without duplicating imports',
    () async {
      expect(
        await model.addDirect('My video', 'https://example.com/video.m3u8'),
        isTrue,
      );
      await model.addDirect('My video', 'https://example.com/video.m3u8');
      expect(model.library, hasLength(1));
      expect(
        model.library.single.episodes.single.streams.single.url.path,
        '/video.m3u8',
      );
      expect(
        await model.addDirect('Bad video', 'javascript:alert(1)'),
        isFalse,
      );
    },
  );
  test('removing a catalog keeps saved titles and history', () async {
    await model.importCatalog('https://example.com/catalog.json');
    final anime = model.titles.last;
    await model.toggleFavorite(anime);
    await model.removeCatalog(model.catalogs.last);
    expect(model.library.single.key, anime.key);
  });
  test('write failures surface and the next save can recover', () async {
    store.fail = true;
    await model.toggleFavorite(model.titles.first);
    expect(model.error, contains('Could not save'));
    store.fail = false;
    await model.setAutoPlay(false);
    expect(store.value?['autoPlay'], isFalse);
  });
  test('backup roundtrip retains catalog and viewing state', () async {
    await model.importCatalog('https://example.com/catalog.json');
    await model.toggleFavorite(model.titles.last);
    final backup = model.exportBackup();
    await model.toggleFavorite(model.titles.last);
    expect(await model.importBackup(backup), isTrue);
    expect(model.library, hasLength(1));
    expect(model.exportBackup(), backup);
  });
}
