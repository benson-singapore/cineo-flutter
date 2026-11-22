import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/models/media_source.dart';
import '../../core/theme/cineo_theme.dart';
import 'media_image.dart';

class MediaPosterCard extends StatefulWidget {
  const MediaPosterCard({
    super.key,
    required this.media,
    required this.onTap,
    this.progress,
    this.width = 142,
    this.showDescription = false,
    this.imageAspectRatio,
    this.coverMode = MediaCoverMode.portrait,
  });

  final MediaItem media;
  final Future<void> Function() onTap;
  final double width;
  final double? progress;
  final bool showDescription;
  final double? imageAspectRatio;
  final MediaCoverMode coverMode;

  @override
  State<MediaPosterCard> createState() => _MediaPosterCardState();
}

class _MediaPosterCardState extends State<MediaPosterCard> {
  var _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedProgress = widget.progress?.clamp(0.0, 1.0);
    final typeBadge = _typeBadgeFor(widget.media);

    return SizedBox(
      width: widget.width,
      child: Semantics(
        button: true,
        enabled: !_opening,
        label: '打开 ${widget.media.title}',
        child: InkWell(
          onTap: _opening ? null : _open,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: widget.imageAspectRatio ??
                      widget.coverMode.posterAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaImage(
                        url: widget.media.posterUrl,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(.34),
                            ],
                          ),
                        ),
                      ),
                      if (widget.media.rating.isFinite &&
                          widget.media.rating > 0 &&
                          widget.media.rating <= 10)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _RatingBadge(rating: widget.media.rating),
                        ),
                      if (typeBadge != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _TypeBadge(
                              label: typeBadge.$1, color: typeBadge.$2),
                        ),
                      if (widget.media.coverStatus.isNotEmpty)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: normalizedProgress == null ? 8 : 18,
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(.72),
                                  borderRadius: BorderRadius.circular(5)),
                              child: Text(widget.media.coverStatus,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      if (normalizedProgress != null)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: _ProgressBar(value: normalizedProgress),
                        ),
                      if (_opening)
                        Positioned.fill(
                          child: DecoratedBox(
                            key: ValueKey(
                              'media-card-loading-${widget.media.id}',
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.56),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: CineoColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.showDescription
                      ? widget.media.description
                      : [
                          if (widget.media.year > 0) '${widget.media.year}',
                          ...widget.media.genres.take(2)
                        ].join('  ·  '),
                  maxLines: widget.showDescription ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: CineoColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.72),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFC857)),
            const SizedBox(width: 3),
            Text(
              rating.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

(String, Color)? _typeBadgeFor(MediaItem media) {
  final category = (media.category ?? '').trim().toLowerCase();
  if (RegExp(r'短剧|短劇|微短剧|微短劇').hasMatch(category)) {
    return ('短剧', const Color(0xFFAD3862));
  }
  if (RegExp(r'电影|電影|影片|movie|film').hasMatch(category)) {
    return ('电影', const Color(0xFF286AA0));
  }
  if (RegExp(r'动漫|動漫|动画|動畫|番剧|番劇|anime|cartoon').hasMatch(category)) {
    return ('动漫', const Color(0xFF7252B3));
  }
  if (RegExp(r'综艺|綜藝|variety').hasMatch(category)) {
    return ('综艺', const Color(0xFF267F75));
  }
  if (RegExp(
          r'电视剧|電視劇|剧集|劇集|连续剧|連續劇|国剧|国产剧|港剧|台剧|韩剧|美剧|日剧|泰剧|series|television')
      .hasMatch(category)) {
    return ('剧集', const Color(0xFFAA591C));
  }
  // Remote sources may omit or use ambiguous category names; their kind is
  // guessed from that same text, so it cannot safely identify the type.
  if (media.sourceId != null) return null;
  return media.kind == MediaKind.series
      ? ('剧集', const Color(0xFFAA591C))
      : ('电影', const Color(0xFF286AA0));
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        backgroundColor: Colors.white.withOpacity(.3),
        color: CineoColors.primary,
      ),
    );
  }
}
