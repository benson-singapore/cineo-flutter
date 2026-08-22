import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';

enum ContentState { loading, empty, error }

class ContentStateView extends StatelessWidget {
  const ContentStateView({
    super.key,
    required this.state,
    this.message,
    this.onRetry,
  });

  final ContentState state;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isLoading = state == ContentState.loading;
    final icon = switch (state) {
      ContentState.loading => Icons.hourglass_top_rounded,
      ContentState.empty => Icons.movie_filter_outlined,
      ContentState.error => Icons.cloud_off_rounded,
    };
    final title = switch (state) {
      ContentState.loading => '正在加载内容',
      ContentState.empty => '还没有可展示的内容',
      ContentState.error => '内容加载失败',
    };

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: CineoColors.textSecondary),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CineoColors.textSecondary,
                      ),
                ),
              ],
              if (state == ContentState.error && onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新加载'),
                ),
              ],
              if (isLoading) ...[
                const SizedBox(height: 20),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
