import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/download_manager.dart';
import '../../data/library_model.dart';
import '../../domain/catalog.dart';
import '../core/featured_title.dart';
import '../core/poster.dart';
import '../core/theme.dart';
import '../core/tv_button.dart';
import 'input_dialog.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.model,
    required this.anime,
    this.franchiseTitles = const [],
  });
  final LibraryModel model;
  final Anime anime;
  final List<Anime> franchiseTitles;
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  LibraryModel get model => widget.model;
  Anime get anime => widget.anime;
  bool loading = false;
  String? loadError;
  int visibleEpisodes = 50;
  int? selectedSeason;
  bool franchiseExpanded = true;
  @override
  void initState() {
    super.initState();
    loadDetails();
  }

  Future<void> loadDetails() async {
    if (model.current(anime).episodes.isNotEmpty) return;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      await model.ensureDetails(anime);
    } catch (e) {
      if (mounted) loadError = 'Could not load episodes: $e';
    }
    if (mounted) setState(() => loading = false);
  }

  void play(BuildContext context, Anime current, Episode episode) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PlayerScreen(model: model, anime: current, episode: episode),
        ),
      );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final current = model.current(anime);
      final next = model.resumeEpisode(current) ?? current.episodes.firstOrNull;
      final seasons = current.episodes.map((e) => e.season).toSet().toList()
        ..sort();
      final activeSeason = seasons.contains(selectedSeason)
          ? selectedSeason!
          : next != null && seasons.contains(next.season)
          ? next.season
          : seasons.firstOrNull ?? 1;
      final seasonEpisodes = current.episodes
          .where((e) => e.season == activeSeason)
          .toList();
      final related = model.relatedTo(current);
      final groupedTitles = releaseOrderedFranchiseTitles(
        widget.franchiseTitles.map(model.current),
      );
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.maybePop(context),
          const SingleActivator(LogicalKeyboardKey.goBack): () =>
              Navigator.maybePop(context),
        },
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 900;
                final inset = wide ? 64.0 : 24.0;
                return ListView(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(inset, 20, inset, 0),
                      child: Row(
                        children: [
                          ActionButton(
                            'Back',
                            icon: Icons.arrow_back,
                            autofocus: true,
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          const Text(
                            'ANIKKU',
                            style: TextStyle(
                              color: brandRed,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (loading) const LinearProgressIndicator(),
                    if (loadError != null)
                      Padding(
                        padding: EdgeInsets.all(inset),
                        child: Column(
                          children: [
                            Text(loadError!),
                            ActionButton(
                              'Retry',
                              icon: Icons.refresh,
                              onPressed: loadDetails,
                            ),
                          ],
                        ),
                      ),
                    FeaturedTitle(
                      anime: current,
                      eyebrow: model.sourceName(current),
                      compact: true,
                      actions: [
                        if (next != null)
                          ActionButton(
                            (model.progress(current, next)?.positionMs ?? 0) >
                                        0 &&
                                    !(model.progress(current, next)?.watched ??
                                        false)
                                ? 'Resume'
                                : 'Watch now',
                            icon: Icons.play_arrow,
                            primary: true,
                            onPressed: () => play(context, current, next),
                          ),
                        ActionButton(
                          model.isFavorite(current)
                              ? 'In My List'
                              : 'Add to My List',
                          icon: model.isFavorite(current)
                              ? Icons.check
                              : Icons.add,
                          onPressed: () => model.toggleFavorite(current),
                        ),
                        if (model.isFavorite(current))
                          ActionButton(
                            model.watchStatus(current),
                            icon: Icons.bookmark_outline,
                            onPressed: () => chooseWatchStatus(current),
                          ),
                        if (model.isFavorite(current))
                          ActionButton(
                            model.category(current).isEmpty
                                ? 'Set category'
                                : model.category(current),
                            icon: Icons.folder_outlined,
                            onPressed: () async {
                              final value = await requestFields(
                                context,
                                title: 'Organize My List',
                                description: 'Use the same category name to group titles. Leave blank to clear.',
                                fields: [
                                  InputField(
                                    'Category',
                                    initial: model.category(current),
                                  ),
                                ],
                              );
                              if (value != null) {
                                await model.setCategory(current, value.first);
                              }
                            },
                          ),
                        ActionButton(
                          'Skip times',
                          icon: Icons.low_priority,
                          onPressed: () => setSkipTimes(current),
                        ),
                        if (model.downloads != null &&
                            current.episodes.isNotEmpty)
                          ActionButton(
                            'Download all',
                            icon: Icons.download_for_offline,
                            onPressed: model.busy
                                ? null
                                : () => model.downloadEpisodes(
                                    current,
                                    current.episodes,
                                  ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (groupedTitles.length > 1) ...[
                            Text(
                              'MORE DETAILS',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFFFF6D1A),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .8,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Container(height: 1, color: Colors.white24),
                            const SizedBox(height: 28),
                            TvButton(
                              key: const Key('franchise-toggle'),
                              quiet: true,
                              padding: EdgeInsets.zero,
                              label: franchiseExpanded
                                  ? 'Collapse franchise titles'
                                  : 'Expand franchise titles',
                              onPressed: () => setState(
                                () => franchiseExpanded = !franchiseExpanded,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    franchiseExpanded
                                        ? Icons.arrow_drop_down
                                        : Icons.arrow_right,
                                    color: const Color(0xFF25D4CF),
                                    size: 34,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      current.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF25D4CF),
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (franchiseExpanded)
                              Container(
                                key: const Key('franchise-titles'),
                                constraints: const BoxConstraints(
                                  maxWidth: 780,
                                ),
                                color: const Color(0xFF242424),
                                child: Column(
                                  children: [
                                    for (final title in groupedTitles)
                                      franchiseTitleRow(
                                        context,
                                        current,
                                        title,
                                        selected: title.key == current.key,
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 34),
                          ],
                          Row(
                            children: [
                              Text(
                                seasons.length > 1
                                    ? seasonLabel(activeSeason)
                                    : 'Episodes',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const Spacer(),
                              if (seasons.length > 1) ...[
                                PopupMenuButton<int>(
                                  key: const Key('season-dropdown'),
                                  tooltip: 'Choose season',
                                  color: panel,
                                  initialValue: activeSeason,
                                  onSelected: (value) => setState(() {
                                    selectedSeason = value;
                                    visibleEpisodes = 50;
                                  }),
                                  itemBuilder: (context) => [
                                    for (final season in seasons)
                                      PopupMenuItem<int>(
                                        value: season,
                                        child: Text(seasonLabel(season)),
                                      ),
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: panel,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(seasonLabel(activeSeason)),
                                        const Icon(Icons.arrow_drop_down),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                              ],
                              Text(
                                seasons.length > 1
                                    ? '${seasonEpisodes.length} in season'
                                    : '${current.episodes.length} available',
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (current.episodes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ActionButton(
                                    'Mark season watched',
                                    icon: Icons.done_all,
                                    onPressed: () => model.markSeasonWatched(
                                      current,
                                      activeSeason,
                                      true,
                                    ),
                                  ),
                                  ActionButton(
                                    'Start season over',
                                    icon: Icons.restart_alt,
                                    onPressed: () => model.clearSeasonProgress(
                                      current,
                                      activeSeason,
                                    ),
                                  ),
                                  if (model.downloads != null &&
                                      seasons.length > 1)
                                    ActionButton(
                                      'Download season',
                                      icon: Icons.download_for_offline,
                                      onPressed: model.busy
                                          ? null
                                          : () => model.downloadEpisodes(
                                              current,
                                              seasonEpisodes,
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          if (current.episodes.isEmpty)
                            const Text(
                              'No episodes in this catalog yet.',
                              style: TextStyle(color: muted),
                            ),
                          for (final episode in seasonEpisodes.take(
                            visibleEpisodes,
                          ))
                            episodeRow(
                              context,
                              current,
                              episode,
                              wide,
                              seasons.length > 1,
                            ),
                          if (seasonEpisodes.length > visibleEpisodes)
                            ActionButton(
                              'Show more episodes',
                              icon: Icons.expand_more,
                              onPressed: () =>
                                  setState(() => visibleEpisodes += 50),
                            ),
                          if (related.isNotEmpty) ...[
                            const SizedBox(height: 30),
                            Text(
                              'More like this',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 185,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: related.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, i) => SizedBox(
                                  width: 290,
                                  child: TvButton(
                                    card: true,
                                    padding: const EdgeInsets.all(3),
                                    label: 'Open ${related[i].title}',
                                    onPressed: () => Navigator.push<void>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DetailScreen(
                                          model: model,
                                          anime: related[i],
                                        ),
                                      ),
                                    ),
                                    child: Poster(anime: related[i]),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 44),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );

  List<Anime> releaseOrderedFranchiseTitles(Iterable<Anime> titles) {
    final unique = <String, Anime>{};
    for (final title in titles) {
      unique[title.key] = title;
    }
    final ordered = unique.values.toList()
      ..sort((a, b) {
        final year = (a.year ?? 0).compareTo(b.year ?? 0);
        if (a.year != null && b.year != null && year != 0) return year;
        final rank = releaseOrderRank(a).compareTo(releaseOrderRank(b));
        if (rank != 0) return rank;
        if (a.year != null && b.year == null) return -1;
        if (a.year == null && b.year != null) return 1;
        return a.title.compareTo(b.title);
      });
    return ordered;
  }

  int releaseOrderRank(Anime anime) {
    final title = anime.title.toLowerCase();
    final normalized = title.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (normalized == 'attackontitan' || normalized == 'shingekinokyojin') {
      return 1000;
    }
    if (normalized.contains('special')) return 1050;
    if (normalized.contains('oad') || normalized.contains('ova')) return 1060;
    if (normalized.contains('crimsonbowandarrow')) return 1100;
    if (normalized.contains('noregrets')) return 1150;
    if (normalized.contains('jiyuunotsubasa') ||
        normalized.contains('wingsoffreedom')) {
      return 1200;
    }
    if (normalized.contains('chuugakkou') ||
        normalized.contains('juniorhigh')) {
      return 1250;
    }
    if (normalized.contains('season2') ||
        RegExp(r'shingekinokyojin2$').hasMatch(normalized)) {
      return 2000;
    }
    if (normalized.contains('roarofawakening')) return 2100;
    if (normalized.contains('season3part2') ||
        normalized.contains('shingekinokyojin3part2')) {
      return 3100;
    }
    if (normalized.contains('season3') ||
        RegExp(r'shingekinokyojin3$').hasMatch(normalized)) {
      return 3000;
    }
    if (normalized.contains('chronicle')) return 3500;
    if (normalized.contains('finalseasonpart2')) return 4100;
    if (normalized.contains('finalseason')) return 4000;
    if (normalized.contains('lastattack') ||
        normalized.contains('finalchapters')) {
      return 4300;
    }
    final seasonMatch = RegExp(r'season(\d+)').firstMatch(normalized);
    if (seasonMatch != null) {
      return (int.tryParse(seasonMatch.group(1)!) ?? 99) * 1000;
    }
    if (normalized.contains('movie')) return 1500;
    return 9000;
  }

  Widget franchiseTitleRow(
    BuildContext context,
    Anime current,
    Anime title, {
    bool selected = false,
  }) {
    final episodeCount = title.episodes.length;
    final episodeLabel = episodeCount == 1
        ? '1 Episode'
        : '$episodeCount Episodes';
    return TvButton(
      key: ValueKey('franchise-title-${title.key}'),
      quiet: true,
      selected: selected,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      label: selected ? 'Current ${title.title}' : 'Open ${title.title}',
      onPressed: selected
          ? null
          : () => Navigator.pushReplacement<void, void>(
              context,
              MaterialPageRoute(
                builder: (_) => DetailScreen(
                  model: model,
                  anime: title,
                  franchiseTitles: widget.franchiseTitles,
                ),
              ),
            ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 22,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Text(
            episodeCount == 0 ? 'Details needed' : episodeLabel,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 18,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> chooseWatchStatus(Anime current) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Watchlist status'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in const [
              'Watching',
              'Plan to watch',
              'Completed',
              'On hold',
              'Dropped',
            ])
              ActionButton(
                status,
                icon: model.watchStatus(current) == status
                    ? Icons.check
                    : Icons.bookmark_outline,
                onPressed: () => Navigator.pop(context, status),
              ),
          ],
        ),
      ),
    );
    if (value != null) await model.setWatchStatus(current, value);
  }

  Future<void> setSkipTimes(Anime current) async {
    final value = await requestFields(
      context,
      title: 'Skip intro and recap',
      description: 'Set manual skip buttons for this title, in seconds.',
      fields: [
        InputField(
          'Intro seconds',
          initial: '${model.skipIntroSeconds(current)}',
        ),
        InputField(
          'Recap seconds',
          initial: '${model.skipRecapSeconds(current)}',
        ),
      ],
    );
    if (value == null) return;
    await model.setSkipTimes(
      current,
      int.tryParse(value[0]) ?? 0,
      int.tryParse(value[1]) ?? 0,
    );
  }

  Widget episodeRow(
    BuildContext context,
    Anime current,
    Episode episode,
    bool wide,
    bool showSeason,
  ) {
    final progress = model.progress(current, episode);
    final download = model.downloads?.entry(current, episode);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvButton(
            quiet: true,
            label: 'Play ${episode.title}',
            onPressed: () => play(context, current, episode),
            child: Row(
              children: [
                Text(
                  episodeNumberLabel(episode, includeSeason: showSeason),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 20),
                if (wide) ...[
                  SizedBox(
                    width: 170,
                    height: 96,
                    child: Poster(anime: current),
                  ),
                  const SizedBox(width: 24),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (model.isNew(current, episode)) 'NEW',
                          if (progress?.watched ?? false)
                            'Watched'
                          else if (progress != null && progress.positionMs > 0)
                            '${((progress.durationMs - progress.positionMs) / 60000).ceil()} min left',
                          if (download?.status == DownloadStatus.complete)
                            'Downloaded',
                          if (progress == null) 'Ready to play',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (progress != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(
                            value: progress.fraction,
                            minHeight: 3,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.play_circle_outline, size: 32),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionButton(
                  progress?.watched ?? false
                      ? 'Mark unwatched'
                      : 'Mark watched',
                  icon: progress?.watched ?? false
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  onPressed: () => model.markWatched(
                    current,
                    episode,
                    !(progress?.watched ?? false),
                  ),
                ),
                if (model.downloads != null &&
                    (DownloadManager.downloadable(episode) != null ||
                        episode.sourceUrl != null))
                  ActionButton(
                    switch (download?.status) {
                      DownloadStatus.complete => 'Downloaded',
                      DownloadStatus.queued => 'Queued',
                      DownloadStatus.downloading => 'Downloading',
                      DownloadStatus.failed => 'Retry download',
                      null => 'Download',
                    },
                    icon: download?.status == DownloadStatus.complete
                        ? Icons.download_done
                        : Icons.download_outlined,
                    onPressed:
                        download != null &&
                            download.status != DownloadStatus.failed
                        ? null
                        : () => model.downloadEpisode(current, episode),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String seasonLabel(int season) => season == 0 ? 'Specials' : 'Season $season';

String episodeNumberLabel(Episode episode, {required bool includeSeason}) {
  final number = episode.number.toString().replaceFirst(RegExp(r'\.0$'), '');
  return includeSeason ? 'S${episode.season}:E$number' : number;
}
