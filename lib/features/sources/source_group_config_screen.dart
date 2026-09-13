import 'package:flutter/material.dart';

import '../../core/models/media_source.dart';
import '../../core/models/source_group_config.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/repositories/media_repository.dart';

/// Configures native categories and cover layout for one media source.
class SourceGroupConfigScreen extends StatefulWidget {
  const SourceGroupConfigScreen({
    super.key,
    required this.sourceId,
    required this.sourceName,
    required this.repository,
  });

  final String sourceId;
  final String sourceName;
  final MediaRepository repository;

  @override
  State<SourceGroupConfigScreen> createState() =>
      _SourceGroupConfigScreenState();
}

class _SourceGroupConfigScreenState extends State<SourceGroupConfigScreen> {
  List<SourceGroupConfig> _configs = const [];
  MediaCoverMode _coverMode = MediaCoverMode.portrait;
  bool _loading = true;
  String? _error;
  String? _syncError;
  Object? _syncException;

  @override
  void initState() {
    super.initState();
    _loadGroupConfigs();
  }

  Future<void> _loadGroupConfigs() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _syncError = null;
        _syncException = null;
      });
    }

    List<SourceGroupConfig> localConfigs = const [];
    try {
      localConfigs =
          await widget.repository.getSourceGroupConfigs(widget.sourceId);
    } catch (_) {
      // A missing/empty local table must not prevent a remote refresh.
    }

    var coverMode = MediaCoverMode.portrait;
    try {
      coverMode = await widget.repository.getSourceCoverMode(widget.sourceId);
    } catch (_) {
      // Older repository implementations use the default portrait mode.
    }

    if (mounted) {
      setState(() {
        _configs = localConfigs;
        _coverMode = coverMode;
      });
    }

    try {
      final remoteConfigs =
          await widget.repository.refreshSourceGroupConfigs(widget.sourceId);
      if (!mounted) return;
      setState(() {
        _configs = remoteConfigs;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncException = error;
        _syncError = '分类同步失败，当前显示本地配置';
        _error = localConfigs.isEmpty ? '加载分组配置失败' : null;
      });
    }
  }

  Future<void> _setCoverMode(MediaCoverMode mode) async {
    if (mode == _coverMode) return;
    final previous = _coverMode;
    setState(() => _coverMode = mode);
    try {
      await widget.repository.setSourceCoverMode(widget.sourceId, mode);
    } catch (_) {
      if (!mounted) return;
      setState(() => _coverMode = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存封面比例失败，请稍后重试')),
      );
    }
  }

  Future<void> _toggleGroup(SourceGroupConfig config) async {
    try {
      await widget.repository.toggleSourceGroupConfig(
        widget.sourceId,
        config.categoryId,
        !config.isEnabled,
      );
      await _loadGroupConfigs();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新分类配置失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _setAll(bool enabled) async {
    try {
      for (final config in _configs) {
        if (config.isEnabled != enabled) {
          await widget.repository.toggleSourceGroupConfig(
            widget.sourceId,
            config.categoryId,
            enabled,
          );
        }
      }
      await _loadGroupConfigs();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '启用全部分类失败，请稍后重试' : '关闭全部分类失败，请稍后重试'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CineoColors.background,
      appBar: AppBar(
        title: Text('${widget.sourceName} - 分组配置'),
        backgroundColor: CineoColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '刷新分类',
            onPressed: _loading ? null : _loadGroupConfigs,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _configs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _configs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: CineoColors.textSecondary,
              ),
              const SizedBox(height: 16),
              const Text(
                '加载分组配置失败',
                style: TextStyle(color: CineoColors.textSecondary),
              ),
              const SizedBox(height: 8),
              const Text(
                '请检查当前视频源是否可访问，或稍后重试。',
                textAlign: TextAlign.center,
                style: TextStyle(color: CineoColors.textSecondary),
              ),
              if (_syncException != null) ...[
                const SizedBox(height: 8),
                Text(
                  _syncException.toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: CineoColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadGroupConfigs,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }

    if (_configs.isEmpty) {
      return Column(
        children: [
          _buildCoverModeSetting(),
          if (_syncError != null) _buildSyncBanner(),
          const Expanded(
            child: Center(
              child: Text(
                '当前来源没有返回分类',
                style: TextStyle(color: CineoColors.textSecondary),
              ),
            ),
          ),
        ],
      );
    }

    final enabledCount = _configs.where((config) => config.isEnabled).length;
    return Column(
      children: [
        _buildCoverModeSetting(),
        if (_syncError != null) _buildSyncBanner(),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          color: CineoColors.surface,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已启用 $enabledCount / ${_configs.length} 个分类',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CineoColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _setAll(true),
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: () => _setAll(false),
                child: const Text('全不选'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _configs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final config = _configs[index];
              return _GroupConfigTile(
                config: config,
                onToggle: () => _toggleGroup(config),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSyncBanner() {
    return MaterialBanner(
      content: Text(
        _syncException == null
            ? _syncError!
            : '${_syncError!}：${_syncException.toString()}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      leading: const Icon(Icons.cloud_off_outlined),
      actions: [
        TextButton(
          onPressed: _loading ? null : _loadGroupConfigs,
          child: const Text('重试'),
        ),
      ],
    );
  }

  Widget _buildCoverModeSetting() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: CineoColors.surface,
      child: Row(
        children: [
          const Icon(Icons.photo_size_select_actual_outlined),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('片库封面比例', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 3),
                Text(
                  '默认使用竖屏，也可以按当前来源切换为横屏',
                  style: TextStyle(
                    fontSize: 12,
                    color: CineoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SegmentedButton<MediaCoverMode>(
            segments: const [
              ButtonSegment(
                value: MediaCoverMode.portrait,
                label: Text('竖屏'),
                icon: Icon(Icons.crop_portrait),
              ),
              ButtonSegment(
                value: MediaCoverMode.landscape,
                label: Text('横屏'),
                icon: Icon(Icons.crop_landscape),
              ),
            ],
            selected: {_coverMode},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) _setCoverMode(selection.first);
            },
          ),
        ],
      ),
    );
  }
}

class _GroupConfigTile extends StatelessWidget {
  const _GroupConfigTile({
    required this.config,
    required this.onToggle,
  });

  final SourceGroupConfig config;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CineoColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  config.isEnabled ? CineoColors.primary : CineoColors.divider,
              width: config.isEnabled ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: config.isEnabled,
                onChanged: (_) => onToggle(),
                fillColor: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.selected)) {
                    return CineoColors.primary;
                  }
                  return CineoColors.surface;
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      config.categoryName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: config.isEnabled
                            ? CineoColors.textPrimary
                            : CineoColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${config.categoryId}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: CineoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: config.isEnabled, onChanged: (_) => onToggle()),
            ],
          ),
        ),
      ),
    );
  }
}
