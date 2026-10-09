import 'package:anikku/data/library_model.dart';
import 'package:anikku/data/sources/anime_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import '../source_support.dart';

void main() {
  test('production removes prior sample titles, loads details lazily and preserves progress on refresh', () async {
    final store = MemoryStore();
    final old = LibraryModel(store: store, catalogs: FixtureCatalogService());
    await old.initialize();
    await old.toggleFavorite(old.titles.first);
    old.dispose();
    final source = FixtureSource();
    final model = LibraryModel(
      store: store,
      catalogs: FixtureCatalogService(),
      sources: [source],
      includeSamples: false,
    );
    addTearDown(model.dispose);
    await model.initialize();
    expect(model.titles.single.sourceId, source.id);
    expect(model.library, isEmpty);
    expect(source.detailCalls, 0);
    final results = await Future.wait([
      model.ensureDetails(model.titles.first),
      model.ensureDetails(model.titles.first),
    ]);
    expect(source.detailCalls, 1);
    final anime = results.first;
    await model.toggleFavorite(anime);
    await model.recordProgress(
      anime,
      anime.episodes.first,
      const Duration(seconds: 30),
      const Duration(minutes: 24),
    );
    await model.resolveEpisode(anime, anime.episodes.first);
    expect(model.exportBackup(), isNot(contains('temporary.mp4')));
    source.count = 3;
    await model.refresh();
    expect(model.library.single.episodes.length, 3);
    expect(model.progress(anime, anime.episodes.first)!.positionMs, 30000);
    expect(
      model.isNew(model.library.single, model.library.single.episodes.last),
      isTrue,
    );
    source.fail = true;
    expect(await model.refresh(), isFalse);
    expect(model.library.single.episodes.length, 3);
  });

  test(
    'out-of-order search results cannot replace a newer query or clear',
    () async {
      final source = FixtureSource();
      final model = LibraryModel(
        store: MemoryStore(),
        catalogs: FixtureCatalogService(),
        sources: [source],
        includeSamples: false,
      );
      addTearDown(model.dispose);
      await model.initialize();
      final first = model.searchSources('older');
      final second = model.searchSources('newer');
      source.pending['newer']!.complete(
        SourcePage([source.title.copyWith(title: 'Newer')], hasMore: false),
      );
      await second;
      // Search results should show the matching source result, while cached details survive.
      expect(model.searchResults, hasLength(1));
      await model.searchSources('');
      source.pending['older']!.complete(
        SourcePage([source.title], hasMore: false),
      );
      await first;
      expect(model.searchResults, isNull);
      expect(model.searching, isFalse);
    },
  );
}
