import 'package:flutter/material.dart';

import '../../core/models/source_group_config.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/repositories/media_repository.dart';

/// Displays a hierarchical group configuration UI for a media source.
/// Users can enable/disable groups, with automatic parent/child sync.
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
  List<SourceGroupConfig> _configs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroupConfigs();
  }

  Future<void> _loadGroupConfigs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configs =
          await widget.repository.getSourceGroupConfigs(widget.sourceId);
      if (!mounted) return;
      setState(() {
        _configs = configs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '加载分组配置失败';
        _loading = false;
      });
    }
  }

  Future<void> _toggleGroup(SourceGroupConfig config) async {
    try {
      await widget.repository.toggleSourceGroupConfig(
        widget.sourceId,
        config.groupId,
        !config.isEnabled,
      );
      await _loadGroupConfigs();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新分组配置失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _enableAll() async {
    try {
      for (final config in _configs) {
        if (!config.isEnabled) {
          await widget.repository.toggleSourceGroupConfig(
            widget.sourceId,
            config.groupId,
            true,
          );
        }
      }
      await _loadGroupConfigs();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('启用全部失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _disableAll() async {
    try {
      for (final config in _configs) {
        if (config.isEnabled) {
          await widget.repository.toggleSourceGroupConfig(
            widget.sourceId,
            config.groupId,
            false,
          );
        }
      }
      await _loadGroupConfigs();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('禁用全部失败，请稍后重试')),
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
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: CineoColors.textSecondary,
            ),
            SizedBox(height: 16),
            Text(
              '加载分组配置失败',
              style: TextStyle(color: CineoColors.textSecondary),
            ),
            SizedBox(height: 16),
          ],
        ),
      );
    }

    if (_configs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: CineoColors.textSecondary,
            ),
            SizedBox(height: 16),
            Text(
              '暂无分组配置',
              style: TextStyle(color: CineoColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final enabledCount = _configs.where((c) => c.isEnabled).length;
    final totalCount = _configs.length;

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          color: CineoColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '已启用 $enabledCount / $totalCount 个分组',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CineoColors.textSecondary,
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: _enableAll,
                        child: const Text('全选'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _disableAll,
                        child: const Text('全不选'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _configs.length,
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
                      config.groupName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: config.isEnabled
                            ? CineoColors.textPrimary
                            : CineoColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${config.groupId}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: CineoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
