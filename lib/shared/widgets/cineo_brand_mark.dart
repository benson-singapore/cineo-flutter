import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';

class CineoBrandMark extends StatelessWidget {
  const CineoBrandMark({
    super.key,
    this.size = 30,
    this.showWordmark = true,
    this.wordmarkSize = 19,
  });

  final double size;
  final bool showWordmark;
  final double wordmarkSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cineo',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/cineo_mark.png',
            width: size,
            height: size,
            filterQuality: FilterQuality.high,
          ),
          if (showWordmark) ...[
            SizedBox(width: size * .32),
            Text(
              'CINEO',
              style: TextStyle(
                color: CineoColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: wordmarkSize,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
