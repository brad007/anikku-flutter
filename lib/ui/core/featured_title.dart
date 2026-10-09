import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import 'theme.dart';

/// Shared cinematic artwork treatment for Home and the title detail page.
class FeaturedTitle extends StatelessWidget {
  const FeaturedTitle({
    super.key,
    required this.anime,
    required this.eyebrow,
    required this.actions,
    this.footer,
    this.compact = false,
  });
  final Anime anime;
  final String eyebrow;
  final List<Widget> actions;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final inset = wide ? 64.0 : 24.0;
      return Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF302124), Color(0xFF15191C)],
                ),
              ),
            ),
          ),
          if (anime.coverUrl != null)
            Positioned.fill(
              child: Image.network(
                anime.coverUrl.toString(),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: .92),
                    Colors.black.withValues(alpha: wide ? .12 : .55),
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .55, 1],
                  colors: [Color(0x40000000), Colors.transparent, ink],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              inset,
              wide ? 74 : 46,
              inset,
              compact ? 32 : 54,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: wide ? 640 : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'A',
                        style: TextStyle(
                          color: brandRed,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          eyebrow.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    anime.title,
                    style: TextStyle(
                      fontSize: wide ? 68 : 42,
                      height: 1.02,
                      letterSpacing: -2,
                      fontWeight: FontWeight.w900,
                      shadows: const [
                        Shadow(blurRadius: 20, color: Colors.black54),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    [
                      if (anime.year != null) '${anime.year}',
                      if (anime.episodes.isNotEmpty || anime.sourceUrl == null)
                        '${anime.episodes.length} ${anime.episodes.length == 1 ? 'episode' : 'episodes'}',
                      ...anime.genres.take(2),
                    ].join('   •   '),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFFE5E5E5),
                    ),
                  ),
                  if (anime.description.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      anime.description,
                      maxLines: compact ? 5 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: wide ? 19 : 16,
                        height: 1.5,
                        color: const Color(0xFFE5E5E5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  Wrap(spacing: 12, runSpacing: 12, children: actions),
                  if (footer != null) ...[const SizedBox(height: 20), footer!],
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
