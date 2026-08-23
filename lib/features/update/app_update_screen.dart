import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/cineo_theme.dart';
import 'app_update_service.dart';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({
    required this.updateService,
    this.launchUrlCallback = launchUrl,
    super.key,
  });

  final AppUpdateService updateService;
  final Future<bool> Function(Uri uri, {LaunchMode mode}) launchUrlCallback;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  bool _openingDownload = false;
  bool _showFullNotes = false;

  @override
  void initState() {
    super.initState();
    if (widget.updateService.latestVersion == null) {
      widget.updateService.checkForUpdates();
    }
  }

  Future<void> _downloadLatest() async {
    final uri = widget.updateService.latestDownloadUri ??
        widget.updateService.latestReleaseUri ??
        AppUpdateService.releasesUri;
    setState(() => _openingDownload = true);
    try {
      final launched = await widget.launchUrlCallback(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开版本下载页面')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingDownload = false);
    }
  }

  Future<void> _openReleaseNoteLink(String? href) async {
    if (href == null || href.trim().isEmpty) return;
    final uri = Uri.tryParse(href.trim());
    if (uri == null || !uri.hasScheme) return;
    await widget.launchUrlCallback(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('版本更新')),
        body: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: widget.updateService,
            builder: (context, _) {
              final service = widget.updateService;
              final latest =
                  service.latestVersion?.replaceFirst(RegExp(r'^[vV]'), '');
              final notes = service.releaseNotes?.trim() ?? '';
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                children: [
                  Center(
                    child: Container(
                      width: 112,
                      height: 112,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Image.asset('assets/branding/cineo_mark.png'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Cineo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '当前版本 v${service.currentVersion}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: CineoColors.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  _UpdatePanel(
                    child: ListTile(
                      leading: const Icon(Icons.system_update_rounded,
                          color: CineoColors.primary),
                      title: Text(service.hasUpdate
                          ? '发现新版本 v$latest'
                          : latest == null
                              ? '正在检查更新'
                              : '已是最新版本'),
                      subtitle: Text(service.hasUpdate
                          ? '已为你准备好最新版本'
                          : latest == null
                              ? '正在连接版本服务'
                              : '最新版本 v$latest'),
                      trailing: service.isChecking
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: '检查更新',
                              onPressed: service.checkForUpdates,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('更新日志',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                  const SizedBox(height: 10),
                  _UpdatePanel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: notes.isEmpty
                          ? const Text('暂无可用更新日志，检查更新后会在这里显示。',
                              style:
                                  TextStyle(color: CineoColors.textSecondary))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ReleaseNotesMarkdown(
                                  data: notes,
                                  expanded: _showFullNotes,
                                  onTapLink: _openReleaseNoteLink,
                                ),
                                if (notes.length > 360)
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _showFullNotes = !_showFullNotes,
                                    ),
                                    child: Text(
                                      _showFullNotes ? '收起' : '查看全部',
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _openingDownload ? null : _downloadLatest,
                    icon: _openingDownload
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(service.hasUpdate ? '下载最新版本' : '打开版本下载页'),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: CineoColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}

class _ReleaseNotesMarkdown extends StatelessWidget {
  const _ReleaseNotesMarkdown({
    required this.data,
    required this.expanded,
    required this.onTapLink,
  });

  static const _collapsedHeight = 240.0;

  final String data;
  final bool expanded;
  final Future<void> Function(String? href) onTapLink;

  @override
  Widget build(BuildContext context) {
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(
        color: CineoColors.textSecondary,
        height: 1.55,
      ),
      h1: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(fontWeight: FontWeight.w800),
      h2: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
      h3: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w800),
      a: const TextStyle(
        color: CineoColors.primaryLight,
        decoration: TextDecoration.underline,
      ),
      listBullet: const TextStyle(color: CineoColors.primaryLight),
      code: const TextStyle(
        color: CineoColors.textPrimary,
        backgroundColor: CineoColors.surfaceElevated,
      ),
      blockquote: const TextStyle(
        color: CineoColors.textSecondary,
        height: 1.55,
      ),
    );
    final markdown = MarkdownBody(
      data: data,
      onTapLink: (text, href, title) => onTapLink(href),
      styleSheet: styleSheet,
    );

    if (expanded) return markdown;
    return SizedBox(
      height: _collapsedHeight,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          child: markdown,
        ),
      ),
    );
  }
}
