import 'package:flutter/material.dart';

import 'tmdb_settings.dart';

class TMDBSettingsScreen extends StatefulWidget {
  const TMDBSettingsScreen({
    super.key,
    this.settings,
  });

  final TMDBSettings? settings;

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
    _settings.initialize();
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Text('TMDB 数据服务', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '配置后可为影视详情补充海报、剧集信息和每集简介。Token 仅保存在本机安全存储中。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _buildStatus(context),
        const SizedBox(height: 16),
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
            border: const OutlineInputBorder(),
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
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _settings.isBusy ? null : _saveToken,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存配置'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _settings.isBusy || !_settings.configured
                  ? null
                  : _clearToken,
              icon: const Icon(Icons.delete_outline),
              label: const Text('清除'),
            ),
          ],
        ),
        if (_settings.isBusy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_settings.errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildError(context),
        ],
      ],
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final configured = _settings.configured;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.check_circle_outline : Icons.info_outline,
            color:
                configured ? colorScheme.primary : colorScheme.onSurfaceVariant,
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
