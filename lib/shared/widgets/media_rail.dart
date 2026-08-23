import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';
import 'media_poster_card.dart';

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.onOpenMedia,
    this.progressByMediaId = const {},
    this.showDescription = false,
    this.onSeeAll,
  });

  final String title;
  final List<MediaItem> items;
  final Future<void> Function(MediaItem) onOpenMedia;
  final Map<String, double> progressByMediaId;
  final bool showDescription;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: .1,
                            color: CineoColors.textPrimary,
                          ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      onPressed: onSeeAll,
                      tooltip: '查看全部$title',
                      icon: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 17,
                      ),
                      color: CineoColors.primaryLight,
                      disabledColor: CineoColors.textSecondary.withOpacity(.32),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              // The poster's fractional aspect ratio can round up by a pixel
              // on Android. Leave room for its text rows to avoid Flex overflow.
              height: showDescription ? 310 : 276,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final media = items[index];
                  return MediaPosterCard(
                    media: media,
                    progress: progressByMediaId[media.id],
                    showDescription: showDescription,
                    onTap: () => onOpenMedia(media),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
