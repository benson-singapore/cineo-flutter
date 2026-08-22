import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';
import 'tmdb_cache_settings.dart';
import 'tmdb_settings.dart';

class TMDBSettingsScreen extends StatefulWidget {
  const TMDBSettingsScreen({
    super.key,
    this.settings,
    this.cacheController,
  });

  final TMDBSettings? settings;
  final TmdbCacheSettingsController? cacheController;

  @override
  State<TMDBSettingsScreen> createState() => _TMDBSettingsScreenState();
}

class _TMDBSettingsScreenState extends State<TMDBSettingsScreen> {
  late final TMDBSettings _settings;
  late final TextEditingController _tokenController;
  late final bool _ownsSettings;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _ownsSettings = widget.settings == null;
    _settings = widget.settings ?? TMDBSettings();
    _tokenController = TextEditingController();
    unawaited(_settings.initialize());
    if (widget.cacheController != null) {
      unawaited(widget.cacheController!.initialize());
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    if (_ownsSettings) _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TMDB 设置')),
      body: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          if (!_settings.initialized && _settings.isBusy) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildBody(context);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: CineoColors.primary),
            const SizedBox(width: 10),
            Text('TMDB 数据服务', style: theme.textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '配置后可为影视详情补充海报、剧集信息和每集简介。Token 仅保存在本机安全存储中。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _buildStatus(context),
        const SizedBox(height: 16),
        _buildTokenPanel(context),
        if (_settings.isBusy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_settings.errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildError(context),
        ],
        _buildCacheSection(context),
      ],
    );
  }

  Widget _buildTokenPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: CineoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CineoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('访问凭证',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            enabled: !_settings.isBusy,
            obscureText: _obscureToken,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveToken(),
            decoration: InputDecoration(
              labelText: 'TMDB API Token',
              hintText: '请输入 Token',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureToken ? '显示 Token' : '隐藏 Token',
                onPressed: _settings.isBusy
                    ? null
                    : () => setState(() => _obscureToken = !_obscureToken),
                icon: Icon(
                  _obscureToken
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _settings.isBusy ? null : _saveToken,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存配置'),
              ),
              OutlinedButton.icon(
                onPressed: _settings.isBusy || !_settings.configured
                    ? null
                    : _clearToken,
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCacheSection(BuildContext context) {
    final controller = widget.cacheController;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (controller == null) {
      return _buildCacheCard(
        context,
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.folder_off_outlined),
          title: Text('TMDB 缓存'),
          subtitle: Text('缓存服务尚未接入，接入后可在此管理图片和剧集资料。'),
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final stats = controller.stats;
        return _buildCacheCard(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                leading:
                    Icon(Icons.cached_outlined, color: colorScheme.primary),
                title: const Text('TMDB 缓存'),
                subtitle: Text(
                  '${formatTmdbCacheSize(stats.bytes)} · ${stats.fileCount} 个文件',
                ),
                trailing: controller.isBusy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: '刷新缓存统计',
                        onPressed: () => controller.initialize(force: true),
                        icon: const Icon(Icons.refresh),
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                leading: const Icon(Icons.timer_outlined),
                title: const Text('缓存保留时间'),
                subtitle: const Text('超过保留时间的缓存可手动清理'),
                trailing: TextButton(
                  onPressed: controller.isBusy
                      ? null
                      : () => _chooseRetention(context, controller),
                  child:
                      Text(tmdbCacheRetentionLabel(controller.retentionDays)),
                ),
              ),
              if (controller.isBusy) const LinearProgressIndicator(),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.errorMessage!,
                  style: TextStyle(color: colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.isBusy
                        ? null
                        : () => _cleanupExpired(controller),
                    icon: const Icon(Icons.auto_delete_outlined),
                    label: const Text('清理过期缓存'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isBusy || stats.fileCount == 0
                        ? null
                        : () => _confirmClearCache(context, controller),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('清空全部'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCacheCard(BuildContext context, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('本地缓存', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: child,
        ),
      ],
    );
  }

  Future<void> _chooseRetention(
    BuildContext context,
    TmdbCacheSettingsController controller,
  ) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择缓存保留时间')),
            for (final days in tmdbCacheRetentionPresets)
              RadioListTile<int>(
                value: days,
                groupValue: controller.retentionDays,
                title: Text(tmdbCacheRetentionLabel(days)),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected == controller.retentionDays) return;
    try {
      await controller.setRetentionDays(selected);
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
              content: Text('缓存保留时间已设为 ${tmdbCacheRetentionLabel(selected)}')),
        );
      }
    } catch (_) {
      // The controller exposes a safe, localized error message.
    }
  }

  Future<void> _cleanupExpired(TmdbCacheSettingsController controller) async {
    try {
      await controller.cleanupExpired();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('过期 TMDB 缓存已清理')),
        );
      }
    } catch (_) {
      // The controller exposes a safe, localized error message.
    }
  }

  Future<void> _confirmClearCache(
    BuildContext context,
    TmdbCacheSettingsController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空 TMDB 缓存？'),
        content: const Text('这会删除已缓存的海报、剧集资料和每集图片，之后可以再次下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('TMDB 缓存已清空')),
        );
      }
    } catch (_) {
      // The controller exposes a safe, localized error message.
    }
  }

  Widget _buildStatus(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final configured = _settings.configured;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: configured
            ? CineoColors.primaryContainer.withOpacity(.45)
            : CineoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.check_circle_outline : Icons.info_outline,
            color: configured ? CineoColors.primary : CineoColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured ? '已配置' : '未配置',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  configured ? 'TMDB Token 已安全保存' : '尚未保存 TMDB Token',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _settings.errorMessage!,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          if (_settings.initialized)
            IconButton(
              tooltip: '重试读取',
              onPressed: _settings.isBusy
                  ? null
                  : () => _settings.initialize(force: true),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }

  Future<void> _saveToken() async {
    try {
      await _settings.saveToken(_tokenController.text);
      if (!mounted) return;
      _tokenController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB 配置已保存')),
      );
    } on ArgumentError {
      // The controller exposes the localized validation message.
    } catch (_) {
      // The controller exposes a safe, non-secret error message.
    }
  }

  Future<void> _clearToken() async {
    try {
      await _settings.clearToken();
      if (!mounted) return;
      _tokenController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB 配置已清除')),
      );
    } catch (_) {
      // The controller exposes a safe, non-secret error message.
    }
  }
}
