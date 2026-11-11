import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/hub/hub_sync_engine.dart';
import '../../data/repositories/local_media_repository.dart';

class HubSyncSettingsScreen extends StatefulWidget {
  const HubSyncSettingsScreen(
      {super.key, required this.engine, required this.repository});
  final HubSyncEngine engine;
  final LocalMediaRepository repository;
  @override
  State<HubSyncSettingsScreen> createState() => _HubSyncSettingsScreenState();
}

class _HubSyncSettingsScreenState extends State<HubSyncSettingsScreen> {
  final _url = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _bound = false;
  bool _revoked = false;
  bool _resyncPending = false;
  int _staleOutboxCount = 0;
  String? _lastSync;
  String? _error;
  int _progressInterval = 10;
  int _pushSent = 0;
  int _pushTotal = 0;
  String? _pushSummary;
  String? _pullSummary;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('hub_progress_push_interval') ?? 10;
    _url.text = await widget.engine.api.credentials.hubUrl ?? '';
    _bound = await widget.engine.api.credentials.isBound;
    final db = await widget.repository.hubDatabase;
    final rows = await db.query('hub_sync_state');
    final state = {for (final row in rows) row['state_key']: row['value']};
    final time = int.tryParse(state['last_sync_at'] as String? ?? '');
    final staleOutboxCount = await widget.engine.staleOutboxCount;
    if (mounted) {
      setState(() {
        _progressInterval =
            const [5, 10, 15, 30, 60].contains(interval) ? interval : 10;
        _revoked = state['revoked'] == 'true';
        _resyncPending = state['resync_pending'] == 'true';
        _staleOutboxCount = staleOutboxCount;
        _lastSync = time == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(time)
                .toLocal()
                .toString()
                .substring(0, 16);
        _error = state['last_error'] as String?;
      });
    }
  }

  Future<void> _bind() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.engine
          .bind(hubUrl: _url.text, pin: _pin.text, deviceName: 'Cineo Flutter');
      _pin.clear();
      await widget.engine.sync();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.engine.pushOutbox(trigger: 'full_push');
      await widget.engine.pullAndApply(trigger: 'manual_pull');
      if (mounted) setState(() => _pullSummary = '推送并拉取完成');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        await _load();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pullNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.engine.pullAndApply(trigger: 'manual_pull');
      if (mounted) {
        setState(() => _pullSummary = '拉取成功 · ${DateTime.now().toLocal()}');
      }
    } catch (error) {
      if (mounted) setState(() => _pullSummary = '拉取失败：$error');
    } finally {
      if (mounted) {
        await _load();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pushAll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _pushSent = 0;
      _pushTotal = 0;
    });
    try {
      final result = await widget.engine.pushAll(onProgress: (sent, total) {
        if (mounted) {
          setState(() {
            _pushSent = sent;
            _pushTotal = total;
          });
        }
      });
      if (mounted) {
        setState(() => _pushSummary =
            '成功 ${result['accepted']} 条 · 忽略 ${result['ignored']} 条 · 失败 ${result['failed']} 条'
                '${result['error'] == null ? '' : ' · ${result['error']}'}');
      }
    } catch (error) {
      if (mounted) setState(() => _pushSummary = '推送失败：$error');
    } finally {
      if (mounted) {
        await _load();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setInterval(int value) async {
    if (!const [5, 10, 15, 30, 60].contains(value)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hub_progress_push_interval', value);
    if (mounted) setState(() => _progressInterval = value);
  }

  Future<void> _resolveResync() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新建立待同步数据？'),
        content: Text(
            'Hub 已要求从云端重建。$_staleOutboxCount 条旧待同步操作会被丢弃，再从当前本机记录生成新的同步队列。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留并稍后处理')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重建并同步')),
        ],
      ),
    );
    if (accepted != true) return;
    await widget.engine.discardStaleOutboxAndRebuildFromLocal();
    await _sync();
  }

  Future<void> _unbind() async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('解除本机绑定？'),
              content:
                  const Text('这只会从本机移除绑定信息，不会吊销 Hub 上的设备。请到 Hub 管理页手动吊销设备。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('解除绑定'))
              ],
            ));
    if (accepted != true) return;
    await widget.engine.unbindLocally();
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('云端同步')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Hub 地址', hintText: 'https://hub.example.com')),
          const SizedBox(height: 16),
          if (_revoked) ...[
            TextButton(
              onPressed: _busy ? null : _unbind,
              child: const Text('移除已吊销绑定并重新绑定'),
            ),
          ] else if (!_bound) ...[
            TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(labelText: '8 位 PIN')),
            FilledButton(
                onPressed: _busy || _pin.text.length != 8 ? null : _bind,
                child: const Text('绑定设备')),
          ] else ...[
            ListTile(
                leading: Icon(_revoked ? Icons.link_off : Icons.cloud_done),
                title: Text(_revoked ? '设备已解绑，请重新绑定' : '已绑定'),
                subtitle: Text(_lastSync == null ? '尚未同步' : '最近同步：$_lastSync')),
            if (_resyncPending)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('云端状态已重建，旧待同步操作已隔离。'),
                      const SizedBox(height: 8),
                      Text('待处理操作：$_staleOutboxCount'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _busy ? null : _resolveResync,
                        child: const Text('从当前本机记录重新生成并同步'),
                      ),
                    ],
                  ),
                ),
              ),
            Text('进度推送间隔', style: Theme.of(context).textTheme.titleMedium),
            const Text('仅保存在本机，不同步到云端'),
            DropdownButton<int>(
              value: _progressInterval,
              items: const [5, 10, 15, 30, 60]
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text('$value 秒')))
                  .toList(),
              onChanged: _busy || _pushTotal > 0
                  ? null
                  : (value) {
                      if (value != null) _setInterval(value);
                    },
            ),
            const SizedBox(height: 12),
            const Text('推送全部按较新的数据为准。'),
            FilledButton(
                onPressed: _busy ? null : _pushAll, child: const Text('推送全部')),
            if (_pushTotal > 0) ...[
              LinearProgressIndicator(
                  value: _pushTotal == 0 ? null : _pushSent / _pushTotal),
              Text('已推送 $_pushSent/$_pushTotal'),
            ],
            if (_pushSummary != null) Text('最近推送：$_pushSummary'),
            FilledButton.tonal(
                onPressed: _busy ? null : _pullNow, child: const Text('立即拉取')),
            if (_pullSummary != null) Text('最近拉取：$_pullSummary'),
            OutlinedButton(
                onPressed: _busy ? null : _sync, child: const Text('推送并拉取')),
            TextButton(
                onPressed: _busy ? null : _unbind, child: const Text('解除本机绑定')),
          ],
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null && _error!.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      );
}
