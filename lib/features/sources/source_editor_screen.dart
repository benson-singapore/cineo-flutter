import 'package:flutter/material.dart';

import '../../core/models/media_source.dart';

class SourceEditorScreen extends StatefulWidget {
  const SourceEditorScreen({
    super.key,
    required this.onSave,
    this.initialSource,
  });

  final MediaSource? initialSource;
  final Future<void> Function(MediaSource source) onSave;

  @override
  State<SourceEditorScreen> createState() => _SourceEditorScreenState();
}

class _SourceEditorScreenState extends State<SourceEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late MediaSourceType _type;
  bool _saving = false;

  bool get _editing => widget.initialSource != null;

  @override
  void initState() {
    super.initState();
    final source = widget.initialSource;
    _nameController = TextEditingController(text: source?.name ?? '');
    _urlController = TextEditingController(text: source?.baseUrl ?? '');
    _type = source?.type == MediaSourceType.demo
        ? MediaSourceType.direct
        : source?.type ?? MediaSourceType.direct;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final existing = widget.initialSource;
    final source = MediaSource(
      id: existing?.id ?? 'source-${DateTime.now().microsecondsSinceEpoch}',
      name: _nameController.text.trim(),
      type: _type,
      baseUrl: _urlController.text.trim(),
      enabled: existing?.enabled ?? true,
      lastCheckedAt: existing?.lastCheckedAt,
      lastError: existing?.lastError,
      externalId: existing?.externalId,
      detailUrl: existing?.detailUrl,
      isAdult: existing?.isAdult ?? false,
      cacheTtlSeconds: existing?.cacheTtlSeconds,
      isDefault: existing?.isDefault ?? false,
      lastLatencyMs: existing?.lastLatencyMs,
    );
    try {
      await widget.onSave(source);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '编辑视频源' : '添加视频源')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：家庭媒体库',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<MediaSourceType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: '类型',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: MediaSourceType.direct,
                  child: Text('直链 HLS / MP4'),
                ),
                DropdownMenuItem(
                  value: MediaSourceType.macCmsApi,
                  child: Text('MacCMS 兼容 API'),
                ),
                DropdownMenuItem(
                  value: MediaSourceType.jsonApi,
                  child: Text('JSON API'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText:
                    _type == MediaSourceType.direct ? 'HLS / MP4 地址' : 'API 地址',
                hintText: _type == MediaSourceType.direct
                    ? 'https://example.com/video.m3u8'
                    : 'https://example.com/api',
                prefixIcon: const Icon(Icons.link),
              ),
              validator: (value) {
                final uri = Uri.tryParse(value?.trim() ?? '');
                if (uri == null ||
                    !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
                  return '请输入 http 或 https 地址';
                }
                if (_type == MediaSourceType.direct &&
                    !(uri.path.toLowerCase().endsWith('.m3u8') ||
                        uri.path.toLowerCase().endsWith('.mp4'))) {
                  return '直链地址需要以 .m3u8 或 .mp4 结尾';
                }
                return null;
              },
            ),
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '保存中...' : '保存视频源'),
            ),
          ],
        ),
      ),
    );
  }
}
