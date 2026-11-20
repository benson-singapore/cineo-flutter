import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/hub/hub_sync_api.dart';

/// Shows pending TV requests only while the unlocked app is in the foreground.
class PhoneSearchAssist extends StatefulWidget {
  const PhoneSearchAssist(
      {super.key, required this.credentials, required this.child});
  final HubDeviceCredentials credentials;
  final Widget child;
  @override
  State<PhoneSearchAssist> createState() => _PhoneSearchAssistState();
}

class _PhoneSearchAssistState extends State<PhoneSearchAssist>
    with WidgetsBindingObserver {
  late final api = HubSyncApi(credentials: widget.credentials);
  Timer? timer;
  bool foreground = true;
  bool busy = false;
  bool dialogOpen = false;
  BuildContext? dialogContext;
  List<Map<String, Object?>> sessions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    timer?.cancel();
    unawaited(_poll());
    timer =
        Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (!foreground || busy) return;
    busy = true;
    try {
      if (!await widget.credentials.isBound) {
        if (mounted) setState(() => sessions = []);
        return;
      }
      final data = await api.inputSessions();
      final items = (data['sessions'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();
      if (mounted && foreground) setState(() => sessions = items);
    } catch (_) {
      if (mounted) setState(() => sessions = []);
    } finally {
      busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      _start();
    } else {
      timer?.cancel();
      final openDialog = dialogContext;
      if (openDialog != null &&
          openDialog.mounted &&
          ModalRoute.of(openDialog)?.isCurrent == true) {
        Navigator.of(openDialog).pop();
      }
      if (mounted) setState(() => sessions = []);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open() async {
    if (dialogOpen) return;
    dialogOpen = true;
    try {
      await showDialog<void>(
          context: context,
          builder: (context) {
            dialogContext = context;
            return _AssistDialog(api: api, sessions: sessions);
          });
    } finally {
      dialogContext = null;
      dialogOpen = false;
      unawaited(_poll());
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (sessions.isNotEmpty && foreground)
          Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(24),
                  child: TextButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.keyboard),
                      label: Text('电视需要输入（${sessions.length}）')))),
      ]);
}

/// Checks only sessions already created by a TV and opens the shared input flow.
Future<void> showManualPhoneSearchAssist(
        BuildContext context, HubSyncApi api) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ManualAssistDialog(api: api),
    );

class _ManualAssistDialog extends StatefulWidget {
  const _ManualAssistDialog({required this.api});
  final HubSyncApi api;

  @override
  State<_ManualAssistDialog> createState() => _ManualAssistDialogState();
}

class _ManualAssistDialogState extends State<_ManualAssistDialog> {
  bool loading = true;
  String? message;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      if (!await widget.api.credentials.isBound) {
        if (mounted) setState(() => message = '手机尚未绑定 Cineo Hub，请先在云端同步中绑定。');
        return;
      }
      final data = await widget.api.inputSessions();
      final sessions = (data['sessions'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
      if (!mounted) return;
      if (sessions.isEmpty) {
        setState(() => message = '当前没有可用的电视输入会话。请确认电视与手机绑定同一账号，并在电视上聚焦搜索框后重试。');
      } else {
        setState(() => loading = false);
        final sent = await showDialog<bool>(
          context: context,
          builder: (_) => _AssistDialog(api: widget.api, sessions: sessions),
        );
        if (!mounted) return;
        if (sent == true) {
          setState(() => message = '已发送到电视，请在电视上确认搜索。');
        } else {
          setState(() => message = '输入已取消，可重新检查电视输入会话。');
        }
      }
    } on HubApiException catch (error) {
      if (mounted) {
        setState(() => message = '检查失败：${error.safeMessage}。请检查绑定或网络后重试。');
      }
    } catch (_) {
      if (mounted) setState(() => message = '检查失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('电视协助输入'),
        content: loading
            ? const Row(children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text('正在检查电视输入会话…'))
              ])
            : Text(message ?? ''),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          if (!loading)
            FilledButton(onPressed: _check, child: const Text('重新检查')),
        ],
      );
}

class _AssistDialog extends StatefulWidget {
  const _AssistDialog({required this.api, required this.sessions});
  final HubSyncApi api;
  final List<Map<String, Object?>> sessions;
  @override
  State<_AssistDialog> createState() => _AssistDialogState();
}

class _AssistDialogState extends State<_AssistDialog> {
  final controller = TextEditingController();
  String? selected;
  bool sending = false;
  bool attempted = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.sessions.length == 1) {
      selected = widget.sessions.first['id'] as String?;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final text = controller.text.trim();
    if (selected == null || text.isEmpty || text.runes.length > 500) {
      setState(() => error = '请选择电视并输入 1–500 个字符');
      return;
    }
    setState(() {
      sending = true;
      attempted = true;
      error = null;
    });
    try {
      await widget.api.submitInput(selected!, text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => error = '发送失败，会话可能已失效或已由其他手机提交，请关闭后重试');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('协助电视搜索'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final session in widget.sessions)
            RadioListTile<String>(
                value: session['id'] as String,
                groupValue: selected,
                title: Text((session['tv_name'] as String?)?.isNotEmpty == true
                    ? session['tv_name'] as String
                    : '电视'),
                subtitle: Text(
                    '有效期至 ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch((session['expires_at'] as num).toInt())).format(context)}'),
                onChanged: sending
                    ? null
                    : (value) => setState(() => selected = value)),
          TextField(
              controller: controller,
              autofocus: true,
              enabled: !sending,
              maxLines: 1,
              decoration: const InputDecoration(labelText: '搜索内容')),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: [
          TextButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: sending || attempted ? null : submit,
              child: const Text('发送到电视'))
        ],
      );
}
