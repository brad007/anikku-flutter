import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import 'theme.dart';

class Poster extends StatelessWidget {
  const Poster({super.key, required this.anime, this.hero = false});
  final Anime anime;
  final bool hero;
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF304439),
      const Color(0xFF393650),
      const Color(0xFF29424D),
    ];
    final color =
        colors[anime.title.codeUnits.fold(0, (a, b) => a + b) % colors.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(hero ? 6 : 4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, ink],
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.play_circle_outline_rounded,
                color: muted,
                size: 60,
              ),
            ),
          ),
          if (anime.coverUrl != null)
            Image.network(
              anime.coverUrl.toString(),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xDD000000)],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            right: 12,
            child: Text(
              anime.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: hero ? 28 : 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
