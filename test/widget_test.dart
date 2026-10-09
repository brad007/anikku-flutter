import 'dart:convert';

import 'package:anikku/data/library_model.dart';
import 'package:anikku/ui/app.dart';
import 'package:anikku/ui/core/tv_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'source_support.dart';

import 'package:anikku/data/sources/anime_source.dart';

import 'package:anikku/domain/catalog.dart';
import 'package:anikku/ui/screens/detail_screen.dart';
import 'package:anikku/ui/screens/player_screen.dart';

void main() {
  testWidgets('browse groups related anime franchise search results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = FixtureSource();
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
      sources: [source],
      includeSamples: false,
    );
    await model.initialize();
    await tester.pumpWidget(AnikkuApp(model: model));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search')), 'Attack on Titan');
    await tester.pump(const Duration(milliseconds: 500));
    source.pending['Attack on Titan']!.complete(
      SourcePage([
        Anime(
          id: 'attack-on-titan',
          sourceId: source.id,
          title: 'Attack on Titan',
          episodes: const [],
          sourceUrl: Uri.parse('https://example.com/aot'),
        ),
        Anime(
          id: 'attack-on-titan-season-2',
          sourceId: source.id,
          title: 'Attack on Titan Season 2',
          episodes: const [],
          sourceUrl: Uri.parse('https://example.com/aot-2'),
        ),
        Anime(
          id: 'shingeki-3',
          sourceId: source.id,
          title: 'Shingeki no Kyojin 3',
          episodes: const [],
          sourceUrl: Uri.parse('https://example.com/aot-3'),
        ),
        Anime(
          id: 'no-regrets',
          sourceId: source.id,
          title: 'Attack on Titan: No Regrets',
          episodes: const [],
          sourceUrl: Uri.parse('https://example.com/aot-no-regrets'),
        ),
      ], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('title-provider::attack-on-titan')),
      findsOneWidget,
    );
    expect(find.text('Attack on Titan Season 2'), findsNothing);
    expect(find.text('Shingeki no Kyojin 3'), findsNothing);
    expect(find.text('Attack on Titan: No Regrets'), findsNothing);
    expect(find.text('4 titles under this anime'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('title-provider::attack-on-titan')),
    );
    await tester.pumpAndSettle();
    expect(find.text('MORE DETAILS'), findsOneWidget);
    expect(find.byKey(const Key('franchise-titles')), findsOneWidget);
    expect(find.text('Attack on Titan Season 2'), findsOneWidget);
    expect(find.text('Shingeki no Kyojin 3'), findsOneWidget);
    expect(find.text('Attack on Titan: No Regrets'), findsOneWidget);
    final mainRow = find.byKey(
      const ValueKey('franchise-title-provider::attack-on-titan'),
    );
    final ovaRow = find.byKey(
      const ValueKey('franchise-title-provider::no-regrets'),
    );
    final seasonTwoRow = find.byKey(
      const ValueKey('franchise-title-provider::attack-on-titan-season-2'),
    );
    final seasonThreeRow = find.byKey(
      const ValueKey('franchise-title-provider::shingeki-3'),
    );
    expect(
      tester.getTopLeft(mainRow).dy,
      lessThan(tester.getTopLeft(ovaRow).dy),
    );
    expect(
      tester.getTopLeft(ovaRow).dy,
      lessThan(tester.getTopLeft(seasonTwoRow).dy),
    );
    expect(
      tester.getTopLeft(seasonTwoRow).dy,
      lessThan(tester.getTopLeft(seasonThreeRow).dy),
    );
    await tester.tap(find.byKey(const Key('franchise-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('franchise-titles')), findsNothing);
    await tester.tap(find.byKey(const Key('franchise-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('franchise-titles')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('home rails group seasons and specials under one anime card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
      includeSamples: false,
    );
    await model.initialize();
    await model.importBackup(
      jsonEncode({
        'version': 1,
        'hiddenContinue': <String>[],
        'titles': [
          {
            'sourceId': 'provider',
            'id': 'attack-on-titan',
            'title': 'Attack on Titan',
            'status': 'Completed',
            'genres': ['Anime'],
            'episodes': [
              for (var i = 1; i <= 26; i++)
                {
                  'id': 'e$i',
                  'number': i,
                  'title': 'Episode $i',
                  'streams': [
                    {'url': 'https://example.com/aot-$i.mp4'},
                  ],
                },
            ],
          },
          {
            'sourceId': 'provider',
            'id': 'attack-on-titan-season-2',
            'title': 'Attack on Titan Season 2',
            'status': 'Completed',
            'genres': ['Anime'],
            'episodes': [
              for (var i = 1; i <= 12; i++)
                {
                  'id': 's2e$i',
                  'number': i,
                  'title': 'Episode $i',
                  'streams': [
                    {'url': 'https://example.com/aot-s2-$i.mp4'},
                  ],
                },
            ],
          },
        ],
        'catalogs': <Object>[],
        'favorites': <String>[],
        'progress': <String, Object>{},
        'categories': <String, String>{},
        'updates': <String>[],
        'autoPlay': true,
      }),
    );
    await tester.pumpWidget(AnikkuApp(model: model));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Completed series'),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('home')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('completed-series-provider::attack-on-titan')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('completed-series-provider::attack-on-titan-season-2'),
      ),
      findsNothing,
    );
    expect(find.text('2 titles under this anime'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('completed-series-provider::attack-on-titan')),
    );
    await tester.pumpAndSettle();
    expect(find.text('MORE DETAILS'), findsOneWidget);
    expect(find.text('Attack on Titan Season 2'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets(
    'remote source search opens details and loads episodes on demand',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = FixtureSource();
      final model = LibraryModel(
        store: MemoryStore(),
        catalogs: FixtureCatalogService(),
        sources: [source],
        includeSamples: false,
      );
      await model.initialize();
      await tester.pumpWidget(AnikkuApp(model: model));
      await tester.pumpAndSettle();
      expect(source.detailCalls, 0);
      await tester.tap(find.byKey(const ValueKey('nav-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search')), 'Anime');
      await tester.pump(const Duration(milliseconds: 500));
      source.pending['Anime']!.complete(
        SourcePage([source.title], hasMore: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('title-provider::show')));
      await tester.pumpAndSettle();
      expect(source.detailCalls, 1);
      expect(find.text('2 available'), findsOneWidget);
      expect(find.text('Watch now'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'unresolved source episodes render loading and failure without indexing missing streams',
    (tester) async {
      final model = LibraryModel(
        store: MemoryStore(),
        catalogs: FixtureCatalogService(),
      );
      await model.initialize();
      final episode = Episode(
        id: '1',
        title: 'Episode 1',
        number: 1,
        streams: const [],
        sourceUrl: Uri.parse('https://example.com/episode'),
      );
      final anime = Anime(
        id: 'show',
        sourceId: 'missing',
        title: 'Anime',
        episodes: [episode],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(model: model, anime: anime, episode: episode),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('This source is not installed'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets('detail screen groups episodes by season', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
      includeSamples: false,
    );
    await model.initialize();
    await model.importBackup(
      jsonEncode({
        'version': 1,
        'hiddenContinue': <String>[],
        'titles': [
          {
            'sourceId': 'test',
            'id': 'seasons',
            'title': 'Seasoned Anime',
            'episodes': [
              {
                'id': 's2e1',
                'season': 2,
                'number': 1,
                'title': 'Second season',
                'streams': [
                  {'url': 'https://example.com/s2e1.mp4'},
                ],
              },
              {
                'id': 's1e1',
                'season': 1,
                'number': 1,
                'title': 'First season',
                'streams': [
                  {'url': 'https://example.com/s1e1.mp4'},
                ],
              },
            ],
          },
        ],
        'catalogs': <Object>[],
        'favorites': <String>[],
        'progress': <String, Object>{},
        'categories': <String, String>{},
        'updates': <String>[],
        'autoPlay': true,
      }),
    );
    final anime = model.titles.single;
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(model: model, anime: anime),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First season'), findsOneWidget);
    expect(find.text('Second season'), findsNothing);
    await tester.tap(find.byKey(const Key('season-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 2').last);
    await tester.pumpAndSettle();
    expect(find.text('Second season'), findsOneWidget);
    expect(find.text('First season'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  Future<LibraryModel> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
    );
    await model.initialize();
    await tester.pumpWidget(AnikkuApp(model: model));
    await tester.pumpAndSettle();
    addTearDown(model.dispose);
    return model;
  }

  testWidgets('TV navigation responds to D-pad right and select', (
    tester,
  ) async {
    await mount(tester, const Size(1920, 1080));
    expect(find.text('FEATURED IN YOUR CATALOGS'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Bring your favorite stories together.'), findsOneWidget);
    expect(find.byKey(const ValueKey('title-samples::one')), findsOneWidget);
  });
  testWidgets('browse, save, categorize and search a title', (tester) async {
    final model = await mount(tester, const Size(1280, 720));
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('title-samples::one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to My List'));
    await tester.pumpAndSettle();
    expect(model.library, hasLength(1));
    await tester.tap(find.text('Set category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Weekend');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(model.categories, ['Weekend']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search')), 'missing title');
    await tester.pumpAndSettle();
    expect(find.text('No matching titles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('browse filters by genre, status, year and availability', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = LibraryModel(
      store: MemoryStore(),
      catalogs: FixtureCatalogService(),
      includeSamples: false,
    );
    await model.initialize();
    await model.importBackup(
      jsonEncode({
        'version': 1,
        'hiddenContinue': <String>[],
        'titles': [
          {
            'sourceId': 'direct',
            'id': 'adventure',
            'title': 'Adventure Film',
            'genres': ['Adventure'],
            'year': 2024,
            'status': 'Completed',
            'episodes': [
              {
                'id': 'video',
                'number': 1,
                'title': 'Play video',
                'streams': [
                  {'url': 'https://example.com/adventure.mp4'},
                ],
              },
            ],
          },
          {
            'sourceId': 'animegg',
            'id': 'comedy',
            'title': 'Comedy Quest',
            'genres': ['Comedy'],
            'year': 2025,
            'status': 'Ongoing',
            'sourceUrl': 'https://example.com/comedy',
            'episodes': <Object>[],
          },
        ],
        'catalogs': <Object>[],
        'favorites': <String>[],
        'progress': <String, Object>{},
        'categories': <String, String>{},
        'updates': <String>[],
        'autoPlay': true,
      }),
    );
    await tester.pumpWidget(AnikkuApp(model: model));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('Adventure Film'), findsOneWidget);
    expect(find.text('Comedy Quest'), findsOneWidget);
    await tester.tap(find.byKey(const Key('genre-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy').last);
    await tester.pumpAndSettle();
    expect(find.text('Adventure Film'), findsNothing);
    expect(find.text('Comedy Quest'), findsOneWidget);
    await tester.tap(find.byKey(const Key('status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ongoing').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('year-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('availability-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Needs details').last);
    await tester.pumpAndSettle();
    expect(find.text('Comedy Quest'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Adventure Film'), findsOneWidget);
    expect(find.text('Comedy Quest'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  testWidgets(
    'continue watching can be hidden without losing resume or history',
    (tester) async {
      final model = await mount(tester, const Size(1920, 1080));
      final anime = model.titles.first;
      await model.recordProgress(
        anime,
        anime.episodes.last,
        const Duration(seconds: 25),
        const Duration(seconds: 100),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue Watching'), findsOneWidget);
      expect(find.text('Episode 2 · 2 min left'), findsOneWidget);
      final remove = find.byWidgetPredicate(
        (w) => w is TvButton && w.label == 'Remove from Continue Watching',
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('Continue Watching'), findsNothing);
      expect(model.progress(anime, anime.episodes.last)!.positionMs, 25000);
      await tester.tap(find.byKey(const ValueKey('nav-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('title-samples::one')), findsOneWidget);
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(model.history, hasLength(1));
    },
  );

  testWidgets('remote focus scrolls a horizontal row to offscreen titles', (
    tester,
  ) async {
    final model = await mount(tester, const Size(1280, 720));
    for (var i = 0; i < 8; i++) {
      await model.addDirect('Movie $i', 'https://example.com/movie$i.mp4');
    }
    await tester.pumpAndSettle();
    final first = find.byKey(ValueKey('saved-${model.library.first.key}'));
    await tester.ensureVisible(first);
    final button = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: first,
        matching: find.byType(FocusableActionDetector),
      ),
    );
    button.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    final last = find.byKey(ValueKey('saved-${model.library.last.key}'));
    final focused = tester.widget<FocusableActionDetector>(
      find.descendant(of: last, matching: find.byType(FocusableActionDetector)),
    );
    expect(focused.focusNode!.hasFocus, isTrue);
    expect(tester.getRect(last).right, lessThanOrEqualTo(1280));
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(1920, 1080),
    const Size(1280, 720),
  ]) {
    testWidgets('all sections fit $size without overflow', (tester) async {
      await mount(tester, size);
      for (var section = 0; section < 7; section++) {
        final nav = find.byKey(ValueKey('nav-$section'));
        await tester.ensureVisible(nav);
        await tester.pumpAndSettle();
        await tester.tap(nav);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('focusable button activates once on remote select', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvButton(
            autofocus: true,
            onPressed: () => presses++,
            child: const Text('Play'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(presses, 1);
  });
}
