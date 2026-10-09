import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/library_model.dart';
import '../../domain/catalog.dart';
import '../core/poster.dart';
import '../core/featured_title.dart';
import 'player_screen.dart';
import '../core/theme.dart';
import '../core/tv_button.dart';
import 'detail_screen.dart';
import 'downloads_screen.dart';
import 'input_dialog.dart';

class BrowseTitleGroup {
  const BrowseTitleGroup(this.representative, this.members);

  final Anime representative;
  final List<Anime> members;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.model});
  final LibraryModel model;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int section = 5;
  String query = '';
  Timer? searchTimer;
  String category = 'All';
  String source = 'All';
  String browseGenre = 'All';
  String browseStatus = 'All';
  String browseYear = 'All';
  String browseAvailability = 'All';
  String browseLanguage = 'Any';
  String browseSort = 'A–Z';
  String listStatus = 'All';
  bool alphabetical = true;
  int heroIndex = 0;
  Timer? heroTimer;
  final search = TextEditingController();
  static const names = [
    'My List',
    'Browse',
    'New episodes',
    'History',
    'Settings',
    'Home',
    'Downloads',
  ];
  LibraryModel get model => widget.model;
  @override
  void initState() {
    super.initState();
    heroTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && section == 5 && model.titles.isNotEmpty) {
        setState(() => heroIndex++);
      }
    });
  }

  @override
  void dispose() {
    searchTimer?.cancel();
    heroTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  void changeSection(int value) => setState(() {
    section = value;
    query = '';
    search.clear();
    searchTimer?.cancel();
    if (value != 1) resetBrowseFilters();
    if (model.sources.isNotEmpty) model.searchSources('');
  });

  void resetBrowseFilters() {
    source = 'All';
    browseGenre = 'All';
    browseStatus = 'All';
    browseYear = 'All';
    browseAvailability = 'All';
    browseLanguage = 'Any';
  }

  bool get hasBrowseFilters =>
      source != 'All' ||
      browseGenre != 'All' ||
      browseStatus != 'All' ||
      browseYear != 'All' ||
      browseAvailability != 'All' ||
      browseLanguage != 'Any';
  Future<void> addCatalog() async {
    final value = await requestFields(
      context,
      title: 'Add a catalog',
      description: 'Enter the URL of a portable Anikku JSON catalog. Your titles and episodes will be cached for browsing.',
      fields: const [InputField('Catalog URL')],
      submit: 'Add catalog',
    );
    if (value != null) await model.importCatalog(value.first);
  }

  Future<void> addVideo() async {
    final value = await requestFields(
      context,
      title: 'Add a video',
      description: 'Use a direct MP4 or HLS stream URL. Web page links cannot be played.',
      fields: const [InputField('Title'), InputField('Video URL')],
      submit: 'Add to My List',
    );
    if (value != null && await model.addDirect(value[0], value[1]) && mounted) {
      changeSection(0);
    }
  }

  void openTitle(Anime anime, {List<Anime>? franchiseTitles}) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DetailScreen(
            model: model,
            anime: anime,
            franchiseTitles: franchiseTitles ?? const [],
          ),
        ),
      );

  Future<void> playTitle(Anime anime) async {
    try {
      anime = await model.ensureDetails(anime);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load episodes: $e')));
      }
      return;
    }
    if (!mounted) return;
    final episode =
        model.resumeEpisode(anime) ??
        (anime.episodes.isEmpty ? null : anime.episodes.first);
    if (episode != null) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PlayerScreen(model: model, anime: anime, episode: episode),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            changeSection(5),
        const SingleActivator(LogicalKeyboardKey.goBack): () =>
            changeSection(5),
      },
      child: Scaffold(
        body: SafeArea(
          child: model.loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1100;
                    final nav = SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final i in [5, 1, 0, 2, 3, 6, 4])
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: TvButton(
                                key: ValueKey('nav-$i'),
                                autofocus: i == 5,
                                quiet: true,
                                selected: section == i,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                onPressed: () => changeSection(i),
                                child: Text(
                                  i == 2 && model.updates.isNotEmpty
                                      ? '${names[i]} (${model.updates.length})'
                                      : names[i],
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                    return Column(
                      children: [
                        Container(
                          color: const Color(0xFF090909),
                          padding: EdgeInsets.symmetric(
                            horizontal: wide ? 54 : 18,
                            vertical: 16,
                          ),
                          child: wide
                              ? Row(
                                  children: [
                                    brand(),
                                    const SizedBox(width: 36),
                                    Expanded(child: nav),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    brand(),
                                    const SizedBox(height: 12),
                                    nav,
                                  ],
                                ),
                        ),
                        if (model.error != null)
                          Container(
                            color: const Color(0xFF45171A),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    model.error!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ActionButton(
                                  'Dismiss',
                                  icon: Icons.close,
                                  onPressed: model.clearError,
                                ),
                              ],
                            ),
                          ),
                        if (model.busy)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(
                          child: section == 5
                              ? home()
                              : Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    wide ? 64 : 24,
                                    30,
                                    wide ? 64 : 24,
                                    0,
                                  ),
                                  child: content(wide),
                                ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    ),
  );

  Widget brand() => const Text(
    'ANIKKU',
    style: TextStyle(
      color: brandRed,
      fontSize: 30,
      height: 1,
      letterSpacing: -1.5,
      fontWeight: FontWeight.w900,
    ),
  );

  Widget home() {
    final titles = model.titles;
    final continuing = model.continueWatching;
    final animeTitles = titles
        .where((a) => a.genres.contains('Anime'))
        .toList();
    final featured = continuing.isNotEmpty
        ? continuing.first
        : titles.isEmpty
        ? null
        : animeTitles.isEmpty
        ? titles[heroIndex % titles.length]
        : animeTitles[heroIndex % animeTitles.length];
    final genres =
        titles
            .expand((a) => a.genres)
            .where((g) => g != 'Sample')
            .toSet()
            .toList()
          ..sort();
    return ListView(
      key: const PageStorageKey('home'),
      children: [
        if (model.sourceLoading) const LinearProgressIndicator(),
        if (featured != null)
          FeaturedTitle(
            anime: featured,
            eyebrow: continuing.isNotEmpty
                ? 'Pick up where you left off'
                : 'Featured in your catalogs',
            actions: [
              ActionButton(
                continuing.isNotEmpty ? 'Continue watching' : 'Play',
                icon: Icons.play_arrow,
                primary: true,
                onPressed: () => playTitle(featured),
              ),
              ActionButton(
                'More info',
                icon: Icons.info_outline,
                onPressed: () => openTitle(featured),
              ),
            ],
            footer: Text(
              model.sourceName(featured),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
        if (continuing.isNotEmpty)
          rail('Continue Watching', continuing, id: 'continue', resume: true),
        if (model.library.isNotEmpty)
          rail('My List', model.library, id: 'saved'),
        if (model.updates.isNotEmpty)
          rail('New episodes', model.updates, id: 'updates'),
        rail(
          'Recently added',
          titles.reversed.take(12).toList(),
          id: 'recently-added',
        ),
        rail(
          'Completed series',
          titles
              .where((a) => a.status.toLowerCase().contains('complete'))
              .toList(),
          id: 'completed-series',
        ),
        rail(
          'Short watches',
          titles
              .where((a) => a.episodes.isNotEmpty && a.episodes.length <= 12)
              .toList(),
          id: 'short-watches',
        ),
        if (continuing.isNotEmpty)
          rail(
            'Because you watched ${continuing.first.title}',
            model.relatedTo(continuing.first).take(12).toList(),
            id: 'because-you-watched',
          ),
        rail('Explore your catalogs', titles, id: 'catalog'),
        for (final genre in genres.take(4))
          rail(
            genre,
            titles.where((a) => a.genres.contains(genre)).toList(),
            id: 'genre-$genre',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(64, 20, 24, 48),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ActionButton(
                'Add catalog',
                icon: Icons.playlist_add,
                onPressed: addCatalog,
              ),
              ActionButton('Add video', icon: Icons.add, onPressed: addVideo),
            ],
          ),
        ),
      ],
    );
  }

  Widget rail(
    String title,
    List<Anime> titles, {
    required String id,
    bool resume = false,
  }) {
    if (titles.isEmpty) return const SizedBox.shrink();
    final groups = resume
        ? [
            for (final title in titles) BrowseTitleGroup(title, [title]),
          ]
        : groupTitleList(titles);
    final displayTitles = groups.map((group) => group.representative).toList();
    final groupSizes = {
      for (final group in groups)
        group.representative.key: group.members.length,
    };
    final groupMembers = {
      for (final group in groups) group.representative.key: group.members,
    };
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        return Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: wide ? 64 : 24),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: wide ? 25 : 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: resume ? 268 : 228,
                child: ListView.separated(
                  key: PageStorageKey('rail-$id'),
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: wide ? 58 : 18),
                  itemCount: displayTitles.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => SizedBox(
                    width: wide ? 320 : 270,
                    child: animeCard(
                      displayTitles[i],
                      keyPrefix: id,
                      resume: resume,
                      groupedTitles: resume
                          ? null
                          : groupSizes[displayTitles[i].key],
                      groupedAnime: resume
                          ? null
                          : groupMembers[displayTitles[i].key],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget content(bool wide) {
    if (section == 4) return settings();
    if (section == 6) return downloads();
    final original = switch (section) {
      0 => model.library,
      1 =>
        query.isNotEmpty && model.sources.isNotEmpty
            ? [
                ...?model.searchResults,
                ...model.titles.where(
                  (a) => !model.sources.any((s) => s.id == a.sourceId),
                ),
              ]
            : model.titles,
      2 => model.updates,
      _ => model.history,
    };
    final matched = original.where(matchesSearch).toList();
    final browseGenres =
        matched
            .expand((a) => a.genres)
            .where((g) => g.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final browseStatuses =
        matched
            .map((a) => a.status.trim().isEmpty ? 'Unknown' : a.status.trim())
            .toSet()
            .toList()
          ..sort();
    final browseYears =
        matched.map((a) => a.year?.toString() ?? 'Unknown').toSet().toList()
          ..sort((a, b) {
            if (a == 'Unknown') return 1;
            if (b == 'Unknown') return -1;
            return b.compareTo(a);
          });
    final filteredTitles = matched
        .where(
          (a) =>
              (section != 0 ||
                  category == 'All' ||
                  model.category(a) == category) &&
              (section != 0 ||
                  listStatus == 'All' ||
                  model.watchStatus(a) == listStatus) &&
              (section != 1 || matchesBrowseFilters(a)),
        )
        .toList();
    final browseGroups = section == 1
        ? groupTitleList(filteredTitles, queryAware: true)
        : const <BrowseTitleGroup>[];
    final groupSizes = {
      for (final group in browseGroups)
        group.representative.key: group.members.length,
    };
    final groupMembers = {
      for (final group in browseGroups) group.representative.key: group.members,
    };
    final titles = section == 1
        ? browseGroups.map((group) => group.representative).toList()
        : filteredTitles;
    if (section == 1) {
      sortBrowseTitles(titles);
    } else if (alphabetical && section != 3) {
      titles.sort((a, b) => a.title.compareTo(b.title));
    }
    return CustomScrollView(
      key: PageStorageKey('section-$section'),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                names[section],
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              Text(switch (section) {
                0 => 'All your favorites. Ready when you are.',
                1 => 'Bring your favorite stories together.',
                2 => 'Fresh episodes from your saved catalogs.',
                _ => 'Your recently watched titles, right where you left them.',
              }, style: const TextStyle(color: muted)),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (section < 2)
                    ActionButton(
                      'Add video',
                      icon: Icons.add,
                      onPressed: addVideo,
                    ),
                  if (section == 1)
                    ActionButton(
                      'Add catalog',
                      icon: Icons.playlist_add,
                      onPressed: addCatalog,
                    ),
                  if (section == 2 || section == 1)
                    ActionButton(
                      'Refresh catalogs',
                      icon: Icons.refresh,
                      onPressed: model.busy ? null : model.refresh,
                    ),
                  if (section != 3)
                    ActionButton(
                      alphabetical ? 'A–Z' : 'Source order',
                      icon: Icons.sort,
                      onPressed: () =>
                          setState(() => alphabetical = !alphabetical),
                    ),
                  if (section == 3 && model.history.isNotEmpty)
                    ActionButton(
                      'Clear history',
                      icon: Icons.delete_outline,
                      onPressed: clearHistory,
                    ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                key: const Key('search'),
                controller: search,
                decoration: InputDecoration(
                  hintText: 'Search ${names[section].toLowerCase()}',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) {
                  setState(() => query = v);
                  searchTimer?.cancel();
                  if (section == 1 && model.sources.isNotEmpty) {
                    searchTimer = Timer(
                      const Duration(milliseconds: 450),
                      () => model.searchSources(v),
                    );
                  }
                },
              ),
              const SizedBox(height: 18),
              if (section == 0 && model.categories.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in ['All', ...model.categories])
                      TvButton(
                        selected: category == name,
                        onPressed: () => setState(() => category = name),
                        child: Text(name),
                      ),
                  ],
                ),
              if (section == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final status in const [
                        'All',
                        'Watching',
                        'Plan to watch',
                        'Completed',
                        'On hold',
                        'Dropped',
                      ])
                        TvButton(
                          selected: listStatus == status,
                          onPressed: () => setState(() => listStatus = status),
                          child: Text(status),
                        ),
                    ],
                  ),
                ),
              if (section == 1)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TvButton(
                      selected: source == 'All',
                      onPressed: () => setState(() => source = 'All'),
                      child: const Text('All sources'),
                    ),
                    for (final catalog in model.catalogs)
                      TvButton(
                        selected: source == catalog.id,
                        onPressed: () => setState(() => source = catalog.id),
                        child: Text(catalog.name),
                      ),
                  ],
                ),
              if (section == 1) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    filterMenu(
                      key: const Key('genre-filter'),
                      label: 'Genre',
                      icon: Icons.category_outlined,
                      value: browseGenre,
                      values: ['All', ...browseGenres],
                      onChanged: (value) => setState(() => browseGenre = value),
                    ),
                    filterMenu(
                      key: const Key('status-filter'),
                      label: 'Status',
                      icon: Icons.radio_button_checked,
                      value: browseStatus,
                      values: ['All', ...browseStatuses],
                      onChanged: (value) =>
                          setState(() => browseStatus = value),
                    ),
                    filterMenu(
                      key: const Key('year-filter'),
                      label: 'Year',
                      icon: Icons.calendar_today_outlined,
                      value: browseYear,
                      values: ['All', ...browseYears],
                      onChanged: (value) => setState(() => browseYear = value),
                    ),
                    filterMenu(
                      key: const Key('availability-filter'),
                      label: 'Availability',
                      icon: Icons.playlist_play,
                      value: browseAvailability,
                      values: const [
                        'All',
                        'Playable now',
                        'Needs details',
                        'Direct videos',
                      ],
                      onChanged: (value) =>
                          setState(() => browseAvailability = value),
                    ),
                    filterMenu(
                      key: const Key('language-filter'),
                      label: 'Language',
                      icon: Icons.record_voice_over,
                      value: browseLanguage,
                      values: const ['Any', 'Subbed', 'Dubbed'],
                      onChanged: (value) =>
                          setState(() => browseLanguage = value),
                    ),
                    filterMenu(
                      key: const Key('browse-sort'),
                      label: 'Sort',
                      icon: Icons.sort,
                      value: browseSort,
                      values: const [
                        'A–Z',
                        'Last updated',
                        'Release date',
                        'Subbed first',
                        'Dubbed first',
                      ],
                      onChanged: (value) => setState(() => browseSort = value),
                    ),
                    if (hasBrowseFilters)
                      ActionButton(
                        'Clear filters',
                        icon: Icons.filter_alt_off,
                        onPressed: () => setState(resetBrowseFilters),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              if (section == 1 && model.searching)
                const LinearProgressIndicator(),
              if (titles.isEmpty && !model.searching)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        query.isNotEmpty
                            ? 'No matching titles'
                            : section == 1 && hasBrowseFilters
                            ? 'No titles match these filters'
                            : switch (section) {
                                0 => 'Make room for your next favorite.',
                                2 => 'You’re all caught up.',
                                3 => 'Your next story starts here.',
                                _ => 'No titles in this source.',
                              },
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      ActionButton(
                        'Explore catalogs',
                        icon: Icons.arrow_forward,
                        onPressed: () => changeSection(1),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, i) => animeCard(
              titles[i],
              history: section == 3,
              groupedTitles: section == 1 ? groupSizes[titles[i].key] : null,
              groupedAnime: section == 1 ? groupMembers[titles[i].key] : null,
            ),
            childCount: titles.length,
          ),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 380,
            mainAxisExtent: section == 3 ? 300 : 240,
            crossAxisSpacing: 14,
            mainAxisSpacing: 22,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 30)),
      ],
    );
  }

  List<BrowseTitleGroup> groupTitleList(
    List<Anime> titles, {
    bool queryAware = false,
  }) {
    if (titles.length < 2) {
      return [
        for (final title in titles) BrowseTitleGroup(title, [title]),
      ];
    }
    final grouped = <String, List<Anime>>{};
    for (final title in titles) {
      grouped
          .putIfAbsent(franchiseKey(title, queryAware: queryAware), () => [])
          .add(title);
    }
    return [
      for (final members in grouped.values)
        BrowseTitleGroup(
          representativeTitle(members),
          List.unmodifiable(members),
        ),
    ];
  }

  Anime representativeTitle(List<Anime> titles) {
    if (titles.length == 1) return titles.single;
    final normalizedQuery = normalizedTitle(query);
    final sorted = [...titles]
      ..sort((a, b) {
        final aScore = representativeScore(a, normalizedQuery);
        final bScore = representativeScore(b, normalizedQuery);
        if (aScore != bScore) return aScore.compareTo(bScore);
        return a.title.compareTo(b.title);
      });
    return sorted.first;
  }

  int representativeScore(Anime anime, String normalizedQuery) {
    final title = normalizedTitle(anime.title);
    final lower = anime.title.toLowerCase();
    var score = anime.title.length;
    if (normalizedQuery.isNotEmpty && title == normalizedQuery) score -= 10000;
    if (title == 'attackontitan') score -= 9000;
    if (anime.episodes.isNotEmpty) score -= 1000 + anime.episodes.length;
    if (anime.sourceUrl != null) score -= 200;
    if (RegExp(
      r'\b(season|part|movie|special|ova|ona|chronicle|regrets|bow|arrow)\b',
    ).hasMatch(lower)) {
      score += 600;
    }
    return score;
  }

  String franchiseKey(Anime anime, {bool queryAware = false}) {
    final title = normalizedTitle(anime.title);
    if (title.contains('attackontitan') ||
        title.contains('shingekinokyojin') ||
        title.contains('shingekikyojin')) {
      return 'attack-on-titan';
    }
    final normalizedQuery = queryAware ? normalizedTitle(query) : '';
    if (normalizedQuery.length >= 3 && title.contains(normalizedQuery)) {
      return 'query:$normalizedQuery';
    }
    var root = anime.title.toLowerCase();
    root = root.split(':').first;
    root = root.replaceAll(
      RegExp(
        r'\b(the\s+)?(final\s+)?(season|part|cour)\s*\d+\b|\b(final|second|third|fourth|fifth)\s+season\b',
      ),
      ' ',
    );
    root = root.replaceAll(
      RegExp(
        r'\b(entertainment\s+district|mugen\s+train|swordsmith\s+village|hashira\s+training|red\s+light\s+district)\s+arc\b',
      ),
      ' ',
    );
    root = root.replaceAll(
      RegExp(
        r'\b(final|second|third|fourth|fifth)\s+season\b|\bseason\s*\d+\b|\b\d+(?:st|nd|rd|th)?\s+season\b',
      ),
      ' ',
    );
    root = root.replaceAll(
      RegExp(
        r'\b(part\s*\d+|movie|film|special|ova|ona|chronicle|no\s+regrets|crimson\s+bow\s+and\s+arrow)\b',
      ),
      ' ',
    );
    root = root.replaceAll(RegExp(r'\b\d+\b'), ' ');
    final normalizedRoot = normalizedTitle(root);
    return normalizedRoot.isEmpty ? title : normalizedRoot;
  }

  String normalizedTitle(String value) => value
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  void sortBrowseTitles(List<Anime> titles) {
    switch (browseSort) {
      case 'Last updated':
        titles.sort((a, b) {
          final watched = model.lastWatched(b).compareTo(model.lastWatched(a));
          if (watched != 0) return watched;
          final year = (b.year ?? 0).compareTo(a.year ?? 0);
          if (year != 0) return year;
          return a.title.compareTo(b.title);
        });
      case 'Release date':
        titles.sort((a, b) {
          final year = (b.year ?? 0).compareTo(a.year ?? 0);
          if (year != 0) return year;
          return a.title.compareTo(b.title);
        });
      case 'Subbed first':
        titles.sort((a, b) {
          final rank = languageRank(
            a,
            'subbed',
          ).compareTo(languageRank(b, 'subbed'));
          if (rank != 0) return rank;
          return a.title.compareTo(b.title);
        });
      case 'Dubbed first':
        titles.sort((a, b) {
          final rank = languageRank(
            a,
            'dubbed',
          ).compareTo(languageRank(b, 'dubbed'));
          if (rank != 0) return rank;
          return a.title.compareTo(b.title);
        });
      default:
        titles.sort((a, b) => a.title.compareTo(b.title));
    }
  }

  int languageRank(Anime anime, String language) =>
      hasLanguage(anime, language) ? 0 : 1;

  bool matchesSearch(Anime anime) {
    if (section == 1 &&
        model.searchResults != null &&
        model.sources.any((s) => s.id == anime.sourceId)) {
      return true;
    }
    return ('${anime.title} ${anime.genres.join(' ')}').toLowerCase().contains(
      query.toLowerCase(),
    );
  }

  bool matchesBrowseFilters(Anime anime) {
    final status = anime.status.trim().isEmpty ? 'Unknown' : anime.status;
    final year = anime.year?.toString() ?? 'Unknown';
    return (source == 'All' || anime.sourceId == source) &&
        (browseGenre == 'All' || anime.genres.contains(browseGenre)) &&
        (browseStatus == 'All' || status == browseStatus) &&
        (browseYear == 'All' || year == browseYear) &&
        (browseLanguage == 'Any' || hasLanguage(anime, browseLanguage)) &&
        switch (browseAvailability) {
          'Playable now' => anime.episodes.isNotEmpty,
          'Needs details' => anime.episodes.isEmpty && anime.sourceUrl != null,
          'Direct videos' => anime.sourceId == 'direct',
          _ => true,
        };
  }

  bool hasLanguage(Anime anime, String language) => anime.episodes.any(
    (episode) => episode.streams.any(
      (stream) => stream.label.toLowerCase().contains(language.toLowerCase()),
    ),
  );

  Widget filterMenu({
    required Key key,
    required String label,
    required IconData icon,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    final menuValues = [
      for (final item in values)
        if (item.trim().isNotEmpty) item,
    ];
    if (!menuValues.contains(value)) menuValues.insert(1, value);
    return PopupMenuButton<String>(
      key: key,
      tooltip: label,
      initialValue: value,
      color: panel,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final item in menuValues)
          PopupMenuItem<String>(
            value: item,
            child: Text(
              item,
              style: TextStyle(
                color: item == value ? Colors.white : Colors.white70,
                fontWeight: item == value ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: value == 'All' ? panel : brandRed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(value == 'All' ? label : '$label: $value'),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  String progressText(Anime anime) {
    final next = model.resumeEpisode(anime);
    if (next == null) return 'Finished watching';
    final p = model.progress(anime, next);
    final remaining = p == null
        ? 0
        : ((p.durationMs - p.positionMs) / 60000).ceil();
    return '${next.title}${remaining > 0 ? ' · $remaining min left' : ' · Up next'}';
  }

  Widget animeCard(
    Anime anime, {
    String? keyPrefix,
    bool resume = false,
    bool history = false,
    int? groupedTitles,
    List<Anime>? groupedAnime,
  }) {
    final episode = model.resumeEpisode(anime);
    final progress = episode == null ? null : model.progress(anime, episode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TvButton(
            key: ValueKey('${keyPrefix ?? 'title'}-${anime.key}'),
            card: true,
            padding: const EdgeInsets.all(3),
            label: '${resume ? 'Resume' : 'Open'} ${anime.title}',
            onPressed: () => resume
                ? playTitle(anime)
                : openTitle(anime, franchiseTitles: groupedAnime),
            child: Poster(anime: anime),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
          child: Text(
            groupedTitles != null && groupedTitles > 1
                ? '$groupedTitles titles under this anime'
                : resume || history
                ? progressText(anime)
                : anime.episodes.isEmpty && anime.sourceUrl != null
                ? 'Anime series'
                : '${anime.year ?? 'Video'}  •  ${anime.episodes.length} ${anime.episodes.length == 1 ? 'episode' : 'episodes'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: muted),
          ),
        ),
        if (history)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text(
              'Last watched ${model.lastWatched(anime).toLocal().toString().substring(0, 16)}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
        if (resume || history) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
            child: LinearProgressIndicator(
              value: progress?.fraction ?? (episode == null ? 1 : 0),
              minHeight: 3,
              backgroundColor: const Color(0xFF555555),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TvButton(
                  quiet: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  onPressed: () => openTitle(anime),
                  child: const Text('Details', style: TextStyle(fontSize: 12)),
                ),
              ),
              TvButton(
                quiet: true,
                padding: const EdgeInsets.all(6),
                label: resume
                    ? 'Remove from Continue Watching'
                    : 'Remove from history',
                onPressed: () => resume
                    ? model.hideFromContinue(anime)
                    : model.clearHistory(anime: anime),
                child: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> clearHistory() async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear watch history?'),
        content: const Text(
          'This resets your episode progress and Continue Watching. My List is kept.',
        ),
        actions: [
          ActionButton(
            'Cancel',
            icon: Icons.close,
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
          ),
          ActionButton(
            'Clear history',
            icon: Icons.delete_outline,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (clear == true) await model.clearHistory();
  }

  Widget downloads() => DownloadsScreen(model: model);

  Widget settings() => ListView(
    children: [
      Text('Settings', style: Theme.of(context).textTheme.displaySmall),
      const SizedBox(height: 8),
      const Text(
        'A few things to make it yours.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 28),
      Text('Profiles', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final profile in model.profiles)
            TvButton(
              selected: model.activeProfile == profile,
              onPressed: () => model.switchProfile(profile),
              child: Text(profile),
            ),
          ActionButton(
            'Add profile',
            icon: Icons.person_add,
            onPressed: () async {
              final value = await requestFields(
                context,
                title: 'Add profile',
                fields: const [InputField('Profile name')],
              );
              if (value != null) await model.switchProfile(value.first);
            },
          ),
        ],
      ),
      const SizedBox(height: 26),
      TvButton(
        onPressed: () => model.setAutoPlay(!model.autoPlay),
        child: Row(
          children: [
            Icon(model.autoPlay ? Icons.toggle_on : Icons.toggle_off),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Play next episode automatically · ${model.autoPlay ? 'On' : 'Off'}',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final language in const ['Any', 'Subbed', 'Dubbed'])
            TvButton(
              selected: model.preferredLanguage == language,
              onPressed: () => model.setPreferredLanguage(language),
              child: Text('Prefer $language'),
            ),
        ],
      ),
      if (model.downloads != null) ...[
        const SizedBox(height: 26),
        Text('Download rules', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quality in const ['Highest', 'Smallest'])
              TvButton(
                selected: model.downloads!.quality == quality,
                onPressed: () => model.setDownloadQuality(quality),
                child: Text('$quality quality'),
              ),
            TvButton(
              selected: model.downloads!.automaticWifiOnly,
              onPressed: () => model.setWifiOnlyDownloads(
                !model.downloads!.automaticWifiOnly,
              ),
              child: Text(
                'Wi-Fi only · ${model.downloads!.automaticWifiOnly ? 'On' : 'Off'}',
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 26),
      Text('Your sources', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      for (final catalog in model.catalogs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(catalog.name),
                    Text(
                      catalog.isSample
                          ? 'Built-in playback samples'
                          : catalog.url.toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!catalog.isSample)
                ActionButton(
                  'Remove',
                  icon: Icons.remove_circle_outline,
                  onPressed: () async {
                    final remove = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Remove catalog?'),
                        content: const Text(
                          'Saved library titles and watch history will be kept.',
                        ),
                        actions: [
                          ActionButton(
                            'Cancel',
                            icon: Icons.close,
                            onPressed: () => Navigator.pop(context, false),
                          ),
                          ActionButton(
                            'Remove',
                            icon: Icons.delete_outline,
                            onPressed: () => Navigator.pop(context, true),
                          ),
                        ],
                      ),
                    );
                    if (remove == true) await model.removeCatalog(catalog);
                  },
                ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionButton('Add catalog', icon: Icons.add, onPressed: addCatalog),
            if (model.sources.isNotEmpty)
              ActionButton(
                'Check source health',
                icon: Icons.health_and_safety,
                onPressed: model.checkSourceHealth,
              ),
          ],
        ),
      ),
      if (model.sourceHealth.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final entry in model.sourceHealth.entries)
          Text(
            '${entry.key}: ${entry.value}',
            style: const TextStyle(color: muted),
          ),
      ],
      const SizedBox(height: 28),
      Text('Library backup', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      const Text(
        'Backups include catalog URLs, stream headers and viewing history. Keep them private. Apple TV storage can be cleared by the system.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          ActionButton(
            'View backup',
            icon: Icons.data_object,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Anikku JSON backup'),
                content: SizedBox(
                  width: 700,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      model.exportBackup(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                actions: [
                  ActionButton(
                    'Close',
                    icon: Icons.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          ActionButton(
            'Restore backup',
            icon: Icons.restore,
            onPressed: () async {
              final value = await requestFields(
                context,
                title: 'Restore library',
                description: 'This replaces this app’s library, history and settings with an Anikku Flutter JSON backup. Android .tachibk backups are not supported.',
                fields: const [InputField('Backup JSON', multiline: true)],
                submit: 'Replace library',
              );
              if (value != null) await model.importBackup(value.first);
            },
          ),
        ],
      ),
      const SizedBox(height: 28),
      Text(
        'Anikku · Flutter edition',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      const Text(
        'An independent port of Anikku with native AnimeGG browsing, search and playback, plus portable catalogs and direct video URLs. Android APK extensions are not executed on Apple platforms.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 12),
      ActionButton(
        'Open-source licenses',
        icon: Icons.info_outline,
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'Anikku Flutter',
          applicationVersion: '0.1.0',
          applicationLegalese: 'Based on Anikku / Aniyomi / Mihon. Apache License 2.0. Blender sample movies © Blender Foundation, CC BY 3.0.',
        ),
      ),
      const SizedBox(height: 30),
    ],
  );
}
