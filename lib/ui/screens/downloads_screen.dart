import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/download_manager.dart';
import '../../data/library_model.dart';
import '../../domain/catalog.dart';
import '../core/poster.dart';
import '../core/theme.dart';
import '../core/tv_button.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.model});
  final LibraryModel model;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  String? selectedGroup;
  LibraryModel get model => widget.model;
  String size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  List<_DownloadGroup> groups(DownloadManager manager) {
    final grouped = <String, _DownloadGroup>{};
    for (final download in manager.entries) {
      final found = match(download);
      final groupKey = found?.anime.key ?? download.title;
      final anime =
          found?.anime ??
          Anime(
            id: groupKey,
            sourceId: 'downloaded',
            title: download.title,
            genres: const ['Anime series'],
            episodes: const [],
          );
      grouped
          .putIfAbsent(
            groupKey,
            () => _DownloadGroup(key: groupKey, anime: anime),
          )
          .downloads
          .add(download);
    }
    final values = grouped.values.toList()
      ..sort((a, b) => a.anime.title.compareTo(b.anime.title));
    return values;
  }

  ({Anime anime, Episode episode})? match(EpisodeDownload download) {
    for (final anime in model.titles) {
      for (final episode in anime.episodes) {
        if (anime.episodeKey(episode) == download.key) {
          return (anime: anime, episode: episode);
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final manager = model.downloads;
    final downloadGroups = manager == null
        ? <_DownloadGroup>[]
        : groups(manager);
    final selected = selectedGroup == null
        ? null
        : downloadGroups
              .where((group) => group.key == selectedGroup)
              .firstOrNull;
    if (selectedGroup != null && selected == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => selectedGroup = null);
      });
    }
    return ListView(
      children: [
        Row(
          children: [
            if (selected != null) ...[
              ActionButton(
                'Downloads',
                icon: Icons.arrow_back,
                onPressed: () => setState(() => selectedGroup = null),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                selected?.anime.title ?? 'Downloads',
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          selected == null
              ? Platform.operatingSystem == 'tvos'
                    ? 'Downloaded anime series. Apple TV may clear cached videos to free storage.'
                    : 'Downloaded anime series, ready to watch offline.'
              : '${selected.downloads.length} downloaded ${selected.downloads.length == 1 ? 'episode' : 'episodes'}',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 26),
        if (selected == null) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ActionButton(
                'Automatic downloads · ${manager?.automatic == true ? 'On' : 'Off'}',
                icon: manager?.automatic == true
                    ? Icons.toggle_on
                    : Icons.toggle_off,
                onPressed: manager?.ready == true
                    ? () => model.setAutomaticDownloads(!manager!.automatic)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Downloads continue while the app remains active in the background, and queued or interrupted jobs resume on the next launch.',
            style: TextStyle(color: muted, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            '${size(manager?.usedBytes ?? 0)} used',
            style: const TextStyle(color: muted),
          ),
          if (manager?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(manager!.error!),
            ),
          const SizedBox(height: 28),
          if (manager == null || manager.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.download_for_offline_outlined,
                    size: 48,
                    color: muted,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'A little planning. A lot more watching.',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Save a title to My List and enable automatic downloads, or download an episode, season or full title from its details.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                final cardWidth = width >= 1100
                    ? (width - 52) / 2
                    : width >= 700
                    ? (width - 24) / 2
                    : width;
                return Wrap(
                  spacing: 24,
                  runSpacing: 30,
                  children: [
                    for (final group in downloadGroups)
                      SizedBox(
                        width: cardWidth,
                        child: _DownloadAnimeCard(
                          group: group,
                          size: size,
                          onPressed: () =>
                              setState(() => selectedGroup = group.key),
                        ),
                      ),
                  ],
                );
              },
            ),
        ] else ...[
          const SizedBox(height: 4),
          _DownloadedEpisodes(
            group: selected,
            manager: manager!,
            model: model,
            match: match,
            size: size,
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _DownloadGroup {
  _DownloadGroup({required this.key, required this.anime});
  final String key;
  final Anime anime;
  final List<EpisodeDownload> downloads = [];

  int get completed =>
      downloads.where((d) => d.status == DownloadStatus.complete).length;
  int get active => downloads
      .where(
        (d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued,
      )
      .length;
  int get failed =>
      downloads.where((d) => d.status == DownloadStatus.failed).length;
  int get bytes => downloads.fold(0, (sum, d) => sum + d.bytes);
}

class _DownloadAnimeCard extends StatelessWidget {
  const _DownloadAnimeCard({
    required this.group,
    required this.size,
    required this.onPressed,
  });

  final _DownloadGroup group;
  final String Function(int bytes) size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TvButton(
    card: true,
    label: group.anime.title,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Poster(anime: group.anime, hero: true),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xEA000000)],
                  ),
                ),
              ),
              Positioned(
                left: 22,
                right: 22,
                bottom: 20,
                child: Text(
                  group.anime.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 12)],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Anime series',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .7),
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            '${group.completed}/${group.downloads.length} ready',
            if (group.active > 0) '${group.active} downloading',
            if (group.failed > 0) '${group.failed} failed',
            size(group.bytes),
          ].join(' · '),
          style: const TextStyle(color: muted, fontSize: 13),
        ),
      ],
    ),
  );
}

class _DownloadedEpisodes extends StatelessWidget {
  const _DownloadedEpisodes({
    required this.group,
    required this.manager,
    required this.model,
    required this.match,
    required this.size,
  });

  final _DownloadGroup group;
  final DownloadManager manager;
  final LibraryModel model;
  final ({Anime anime, Episode episode})? Function(EpisodeDownload download)
  match;
  final String Function(int bytes) size;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final download in group.downloads)
        _DownloadEpisodeRow(
          download: download,
          match: match(download),
          manager: manager,
          model: model,
          size: size,
        ),
    ],
  );
}

class _DownloadEpisodeRow extends StatelessWidget {
  const _DownloadEpisodeRow({
    required this.download,
    required this.match,
    required this.manager,
    required this.model,
    required this.size,
  });

  final EpisodeDownload download;
  final ({Anime anime, Episode episode})? match;
  final DownloadManager manager;
  final LibraryModel model;
  final String Function(int bytes) size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  download.episodeTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(switch (download.status) {
                DownloadStatus.complete => 'Ready · ${size(download.bytes)}',
                DownloadStatus.queued => 'Queued',
                DownloadStatus.downloading =>
                  'Downloading · ${size(download.bytes)}${download.total == null ? '' : ' / ${size(download.total!)}'}',
                DownloadStatus.failed => download.error ?? 'Download failed',
              }, style: const TextStyle(color: muted, fontSize: 13)),
            ],
          ),
          if (download.status == DownloadStatus.downloading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(
                value: download.total == null
                    ? null
                    : (download.bytes / download.total!).clamp(0, 1),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (match != null && download.status == DownloadStatus.complete)
                ActionButton(
                  'Play offline',
                  icon: Icons.play_arrow,
                  primary: true,
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        model: model,
                        anime: match!.anime,
                        episode: match!.episode,
                      ),
                    ),
                  ),
                ),
              if (match != null && download.status == DownloadStatus.failed)
                ActionButton(
                  'Retry',
                  icon: Icons.refresh,
                  onPressed: () =>
                      model.downloadEpisode(match!.anime, match!.episode),
                ),
              ActionButton(
                download.status == DownloadStatus.complete
                    ? 'Remove download'
                    : 'Cancel',
                icon: Icons.close,
                onPressed: () => manager.remove(download),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
