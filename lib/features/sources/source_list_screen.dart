import 'package:flutter/material.dart';

import '../../core/models/media_source.dart';
import '../../core/platform/adaptive_navigation.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/repositories/media_repository.dart';
import '../settings/adult_source_settings.dart';
import 'source_config_importer.dart';
import 'source_editor_screen.dart';

class SourceListScreen extends StatefulWidget {
  const SourceListScreen({
    super.key,
    required this.repository,
    required this.adultSourceSettings,
    this.onSourceTest,
  });

  final MediaRepository repository;
  final AdultSourceSettings adultSourceSettings;
  final Future<bool> Function(MediaSource source)? onSourceTest;

  @override
  State<SourceListScreen> createState() => _SourceListScreenState();
}

class _SourceListScreenState extends State<SourceListScreen> {
  List<MediaSource> _sources = const [];
  final Set<String> _testing = {};
  final _searchController = TextEditingController();
  String _query = '';
  bool _loading = true;
  Object? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _testSource(MediaSource source) {
    return widget.onSourceTest?.call(source) ??
        widget.repository.testSource(source);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources = await widget.repository.sources();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([MediaSource? source]) async {
    await Navigator.of(context).push<bool>(
      adaptivePageRoute(
        context,
        builder: (_) => SourceEditorScreen(
          initialSource: source,
          onSave: widget.repository.saveSource,
        ),
      ),
    );
    await _load();
  }

  Future<void> _toggleSource(MediaSource source, bool enabled) async {
    try {
      await widget.repository.saveSource(source.copyWith(enabled: enabled));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新视频源状态失败，请稍后重试')),
      );
    }
  }

  Future<void> _toggleFavorite(MediaSource source) async {
    try {
      await widget.repository.saveSource(
        source.copyWith(isFavorite: !source.isFavorite),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新收藏来源失败，请稍后重试')),
      );
    }
  }

  Future<void> _setDefaultSource(MediaSource source) async {
    if (!source.enabled ||
        (source.type != MediaSourceType.macCmsApi &&
            source.type != MediaSourceType.jsonApi)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅可将已启用的 API 视频源设为默认')),
      );
      return;
    }

    try {
      await widget.repository.setDefaultSource(source.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将“${source.name}”设为默认视频源')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError ? error.message : '设置默认视频源失败，请稍后重试';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _deleteSource(MediaSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除视频源？'),
        content: Text('将删除“${source.name}”的本地配置。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteSource(source.id);
    await _load();
  }

  Future<void> _runTest(MediaSource source) async {
    setState(() => _testing.add(source.id));
    bool passed = false;
    Object? error;
    try {
      passed = await _testSource(source);
    } catch (testError) {
      error = testError;
    }
    if (!mounted) return;
    setState(() => _testing.remove(source.id));
    await _load();
    if (!mounted) return;

    final refreshed =
        _sources.where((item) => item.id == source.id).firstOrNull;
    final detail = refreshed?.lastError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error != null
              ? '连通性测试失败，请检查视频源配置'
              : passed
                  ? _successMessage(refreshed)
                  : detail == null || detail.isEmpty
                      ? '连通性测试未通过，请检查视频源配置'
                      : '连通性测试未通过：$detail',
        ),
      ),
    );
  }

  String _successMessage(MediaSource? source) {
    final latency = source?.lastLatencyMs;
    return latency == null ? '连通性测试通过' : '连通性测试通过，耗时 ${latency}ms';
  }

  Future<void> _openImportDialog() async {
    final controller = TextEditingController();
    var allowInsecureHttp = true;
    try {
      final request = await showDialog<_SourceImportRequest>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('导入资源站配置'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '粘贴 MacCMS 兼容的 JSON 配置。仅导入本地配置，不会在导入时访问任何站点。',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      minLines: 8,
                      maxLines: 14,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        labelText: '配置 JSON',
                        hintText: '{"cache_time": 7200, "api_site": {...}}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许 HTTP 站点'),
                      subtitle: const Text('HTTP 可能被篡改或泄露请求信息'),
                      value: allowInsecureHttp,
                      onChanged: (value) =>
                          setDialogState(() => allowInsecureHttp = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _SourceImportRequest(
                    rawJson: controller.text,
                    allowInsecureHttp: allowInsecureHttp,
                  ),
                ),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('导入'),
              ),
            ],
          ),
        ),
      );
      if (request == null) return;
      final result = parseMacCmsSourceConfig(
        request.rawJson,
        includeAdult: true,
        allowInsecureHttp: request.allowInsecureHttp,
      );
      for (final source in result.sources) {
        await widget.repository.saveSource(source);
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final skipped = result.issues.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${result.sources.length} 个来源'
            '${skipped == 0 ? '' : '，跳过/提示 $skipped 项'}',
          ),
        ),
      );
      if (result.issues.isNotEmpty) {
        await _showImportIssues(result);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showImportIssues(SourceConfigImportResult result) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入提示'),
        content: SizedBox(
          width: 520,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: result.issues.length,
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(result.issues[index].toString()),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频源'),
        actions: [
          IconButton(
            tooltip: '导入 JSON 配置',
            onPressed: _openImportDialog,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
              tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('添加来源'),
      ),
      body: AnimatedBuilder(
        animation: widget.adultSourceSettings,
        builder: (context, _) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_error != null) {
            return Center(
              child: _SourceFeedback(
                icon: Icons.cloud_off_outlined,
                title: '视频源加载失败',
                subtitle: '请检查本地配置后重试',
                action: OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                ),
              ),
            );
          }
          final adultVisible = widget.adultSourceSettings.showAdultSources;
          final query = _query.trim().toLowerCase();
          // Keep adult sources out of the source-management data set when
          // the setting is disabled. This prevents them from leaking into
          // another tab or search result while the adult tab is hidden.
          final visibleSources = adultVisible
              ? _sources
              : _sources
                  .where((source) => !source.isAdult)
                  .toList(growable: false);
          final matchingSources = query.isEmpty
              ? visibleSources
              : visibleSources
                  .where((source) => source.name.toLowerCase().contains(query))
                  .toList(growable: false);
          final favoriteSources = matchingSources
              .where((source) => source.isFavorite)
              .toList(growable: false);
          final regularSources = matchingSources
              .where((source) => !source.isAdult)
              .toList(growable: false);
          final adultSources = matchingSources
              .where((source) => source.isAdult)
              .toList(growable: false);
          final adultTabVisible = adultVisible && adultSources.isNotEmpty;

          return DefaultTabController(
            length: adultTabVisible ? 3 : 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '按名称搜索视频源',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                Material(
                  color: CineoColors.background,
                  child: TabBar(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tabs: [
                      Tab(text: '收藏源 ${favoriteSources.length}'),
                      Tab(text: '普通源 ${regularSources.length}'),
                      if (adultTabVisible)
                        Tab(text: '成人源 ${adultSources.length}'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _SourceTabList(
                        sources: favoriteSources,
                        testing: _testing,
                        emptyState: const _SourceEmptyState(
                          title: '还没有收藏来源',
                          subtitle: '点按来源卡片上的星标，将常用站点固定在这里',
                        ),
                        onToggle: _toggleSource,
                        onToggleFavorite: _toggleFavorite,
                        onTest: _runTest,
                        onSetDefault: _setDefaultSource,
                        onEdit: _openEditor,
                        onDelete: _deleteSource,
                      ),
                      _SourceTabList(
                        sources: regularSources,
                        testing: _testing,
                        emptyState: const _SourceEmptyState(),
                        onToggle: _toggleSource,
                        onToggleFavorite: _toggleFavorite,
                        onTest: _runTest,
                        onSetDefault: _setDefaultSource,
                        onEdit: _openEditor,
                        onDelete: _deleteSource,
                      ),
                      if (adultTabVisible)
                        _SourceTabList(
                          sources: adultSources,
                          testing: _testing,
                          emptyState: const _SourceEmptyState(
                            title: '还没有成人来源',
                            subtitle: '导入的成人标记来源会单独显示在这里',
                          ),
                          onToggle: _toggleSource,
                          onToggleFavorite: _toggleFavorite,
                          onTest: _runTest,
                          onSetDefault: _setDefaultSource,
                          onEdit: _openEditor,
                          onDelete: _deleteSource,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.testing,
    required this.onToggle,
    required this.onToggleFavorite,
    required this.onTest,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final MediaSource source;
  final bool testing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTest;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (source.type) {
      MediaSourceType.direct => 'HLS / MP4',
      MediaSourceType.macCmsApi => 'MacCMS 兼容 API',
      MediaSourceType.jsonApi => 'JSON API',
      MediaSourceType.demo => '演示媒体库',
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: source.lastError != null && source.lastError!.isNotEmpty
              ? Theme.of(context).colorScheme.error.withOpacity(.55)
              : source.enabled
                  ? CineoColors.divider
                  : CineoColors.divider.withOpacity(.65),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: source.enabled
                      ? CineoColors.primaryContainer
                      : CineoColors.surfaceElevated,
                  child: Icon(
                    source.type == MediaSourceType.direct
                        ? Icons.play_circle
                        : Icons.data_object,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              source.name,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (source.isDefault) ...[
                            const SizedBox(width: 8),
                            const _DefaultSourceBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        typeLabel,
                        style: const TextStyle(
                            color: CineoColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(value: source.enabled, onChanged: onToggle),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                source.baseUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: CineoColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            _SourceHealthSummary(source: source),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                if (source.type == MediaSourceType.macCmsApi ||
                    source.type == MediaSourceType.jsonApi)
                  TextButton.icon(
                    onPressed: source.isDefault || !source.enabled
                        ? null
                        : onSetDefault,
                    icon: Icon(
                      source.isDefault
                          ? Icons.star
                          : Icons.star_border_outlined,
                    ),
                    label: Text(source.isDefault ? '默认站点' : '设为默认'),
                  ),
                IconButton(
                  tooltip: source.isFavorite ? '取消收藏来源' : '收藏来源',
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    source.isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                ),
                TextButton.icon(
                  onPressed: testing ? null : onTest,
                  icon: testing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: const Text('连通性测试 / 测速'),
                ),
                IconButton(
                    tooltip: '编辑',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined)),
                IconButton(
                  tooltip: '删除',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTabList extends StatelessWidget {
  const _SourceTabList({
    required this.sources,
    required this.testing,
    required this.emptyState,
    required this.onToggle,
    required this.onToggleFavorite,
    required this.onTest,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MediaSource> sources;
  final Set<String> testing;
  final Widget emptyState;
  final Future<void> Function(MediaSource source, bool enabled) onToggle;
  final Future<void> Function(MediaSource source) onToggleFavorite;
  final Future<void> Function(MediaSource source) onTest;
  final Future<void> Function(MediaSource source) onSetDefault;
  final Future<void> Function([MediaSource? source]) onEdit;
  final Future<void> Function(MediaSource source) onDelete;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return emptyState;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final source = sources[index];
        return _SourceCard(
          source: source,
          testing: testing.contains(source.id),
          onToggle: (enabled) => onToggle(source, enabled),
          onToggleFavorite: () => onToggleFavorite(source),
          onTest: () => onTest(source),
          onSetDefault: () => onSetDefault(source),
          onEdit: () => onEdit(source),
          onDelete: () => onDelete(source),
        );
      },
    );
  }
}

class _DefaultSourceBadge extends StatelessWidget {
  const _DefaultSourceBadge();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          '默认',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SourceHealthSummary extends StatelessWidget {
  const _SourceHealthSummary({required this.source});

  final MediaSource source;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      color: CineoColors.textSecondary,
      fontSize: 12,
    );
    final checkedAt = source.lastCheckedAt;
    final latency = source.lastLatencyMs;
    final hasError = source.lastError != null && source.lastError!.isNotEmpty;

    if (checkedAt == null && !hasError) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '尚未进行连通性测试',
          style: TextStyle(color: CineoColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final status = hasError ? '上次测试失败：${source.lastError}' : '上次测试通过';
    final latencyText = latency == null ? '' : ' · ${latency}ms';
    final checkedText =
        checkedAt == null ? '' : ' · ${_formatCheckedAt(checkedAt)}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '$status$latencyText$checkedText',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color:
              hasError ? Theme.of(context).colorScheme.error : textStyle.color,
          fontSize: textStyle.fontSize,
        ),
      ),
    );
  }

  String _formatCheckedAt(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _SourceImportRequest {
  const _SourceImportRequest({
    required this.rawJson,
    required this.allowInsecureHttp,
  });

  final String rawJson;
  final bool allowInsecureHttp;
}

class _SourceEmptyState extends StatelessWidget {
  const _SourceEmptyState({
    this.title = '还没有视频源',
    this.subtitle = '添加你有权访问的 HLS、MP4 或 JSON API 地址',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _SourceFeedback(
        icon: Icons.dns_outlined,
        title: title,
        subtitle: subtitle,
      ),
    );
  }
}

class _SourceFeedback extends StatelessWidget {
  const _SourceFeedback({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: CineoColors.primary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CineoColors.textSecondary),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}
