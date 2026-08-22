import 'package:flutter/material.dart';

import '../app_lock/app_lock_controller.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    this.onOpenLibrary,
    this.onOpenSources,
    this.onOpenSettings,
    this.onOpenAppLock,
    this.onLockNow,
    this.appLockController,
    super.key,
  });

  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenSources;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenAppLock;
  final VoidCallback? onLockNow;
  final AppLockController? appLockController;

  @override
  Widget build(BuildContext context) {
    final lockEnabled = appLockController?.hasPin ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _ProfileHeader(lockEnabled: lockEnabled),
          const SizedBox(height: 24),
          _Section(
            title: '本地内容',
            children: [
              _ProfileTile(
                  icon: Icons.bookmark_outline,
                  title: '我的收藏',
                  onTap: onOpenLibrary),
              _ProfileTile(
                  icon: Icons.history, title: '播放历史', onTap: onOpenLibrary),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: '应用设置',
            children: [
              _ProfileTile(
                  icon: Icons.link, title: '视频源管理', onTap: onOpenSources),
              _ProfileTile(
                  icon: Icons.lock_outline,
                  title: lockEnabled ? '修改应用锁' : '设置应用锁',
                  onTap: onOpenAppLock),
              if (lockEnabled)
                _ProfileTile(
                    icon: Icons.lock_clock, title: '立即锁定', onTap: onLockNow),
              _ProfileTile(
                  icon: Icons.settings_outlined,
                  title: '通用设置',
                  onTap: onOpenSettings),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Cineo · 本地优先媒体中心',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.lockEnabled});

  final bool lockEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child:
                const Icon(Icons.person_outline, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本地用户', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(lockEnabled ? '应用锁已开启' : '数据保存在本机',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}
