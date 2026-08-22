import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';
import 'm3u8_filter_settings.dart';

class M3u8FilterSettingsScreen extends StatelessWidget {
  const M3u8FilterSettingsScreen({required this.settings, super.key});

  final M3u8FilterSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('M3U8 广告过滤')),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加配置',
        onPressed: () => _editConfig(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          if (!settings.initialized) {
            return const Center(child: CircularProgressIndicator());
          }
          if (settings.configs.isEmpty) {
            return _EmptyState(onAdd: () => _editConfig(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            itemCount: settings.configs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final config = settings.configs[index];
              return _ConfigTile(
                config: config,
                onChanged: (enabled) => settings.setEnabled(config.id, enabled),
                onEdit: () => _editConfig(context, config: config),
                onDelete: () => _confirmDelete(context, config),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editConfig(
    BuildContext context, {
    M3u8FilterConfig? config,
  }) async {
    final result = await showModalBottomSheet<_M3u8FilterDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: CineoColors.surface,
      builder: (_) => _ConfigEditor(config: config),
    );
    if (result == null) return;
    try {
      if (config == null) {
        await settings.addConfig(
          name: result.name,
          template: result.template,
          enabled: result.enabled,
        );
      } else {
        await settings.updateConfig(
          id: config.id,
          name: result.name,
          template: result.template,
        );
        if (result.enabled != config.enabled) {
          await settings.setEnabled(config.id, result.enabled);
        }
      }
    } on ArgumentError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message?.toString() ?? '配置无效')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    M3u8FilterConfig config,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除过滤配置？'),
        content: Text('将删除“${config.name}”，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await settings.deleteConfig(config.id);
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({
    required this.config,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final M3u8FilterConfig config;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CineoColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    config.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Switch.adaptive(value: config.enabled, onChanged: onChanged),
                PopupMenuButton<String>(
                  tooltip: '配置操作',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            Text(
              config.enabled ? '已启用，播放 HLS 视频时生效' : '未启用',
              style: const TextStyle(
                color: CineoColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              config.template,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CineoColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_alt_outlined,
                size: 48, color: CineoColors.textSecondary),
            const SizedBox(height: 14),
            const Text('还没有过滤配置'),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加配置'),
            ),
          ],
        ),
      ),
    );
  }
}

class _M3u8FilterDraft {
  const _M3u8FilterDraft({
    required this.name,
    required this.template,
    required this.enabled,
  });

  final String name;
  final String template;
  final bool enabled;
}

class _ConfigEditor extends StatefulWidget {
  const _ConfigEditor({this.config});

  final M3u8FilterConfig? config;

  @override
  State<_ConfigEditor> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends State<_ConfigEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _templateController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _nameController = TextEditingController(text: config?.name ?? '');
    _templateController = TextEditingController(
      text: config?.template ??
          'https://m3u8-filter-api.benson.in.net/api/proxy?rule=auto_full&url=$m3u8FilterUrlPlaceholder',
    );
    _enabled = config?.enabled ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.config == null ? '添加过滤配置' : '编辑过滤配置',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: '配置名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _templateController,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '代理地址模板',
              helperText: r'必须包含 ${YOUR_M3U8_URL}',
              helperMaxLines: 2,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用此配置'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _M3u8FilterDraft(
                name: _nameController.text,
                template: _templateController.text,
                enabled: _enabled,
              ),
            ),
            child: const Text('保存配置'),
          ),
        ],
      ),
    );
  }
}
