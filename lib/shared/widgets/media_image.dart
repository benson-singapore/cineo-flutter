import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';

class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.borderRadius = BorderRadius.zero,
    this.placeholderIcon = Icons.movie_outlined,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final BorderRadius borderRadius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: url.trim().isEmpty
          ? _fallback()
          : Image.network(
              url,
              fit: fit,
              alignment: alignment,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                assert(() {
                  final uri = Uri.tryParse(url);
                  final safeUrl = uri == null
                      ? '<invalid-url>'
                      : uri.replace(query: '', fragment: '').toString();
                  debugPrint(
                    '[Cineo][Image] phase=load_failed url=$safeUrl '
                    'error=${error.runtimeType}: $error',
                  );
                  return true;
                }());
                return _fallback();
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _fallback(),
                    Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: loadingProgress.expectedTotalBytes == null
                              ? null
                              : loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!,
                          color: CineoColors.primary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _fallback() {
    return ColoredBox(
      color: CineoColors.surfaceElevated,
      child: Center(
        child: Icon(
          placeholderIcon,
          color: CineoColors.textSecondary,
          size: 32,
        ),
      ),
    );
  }
}
