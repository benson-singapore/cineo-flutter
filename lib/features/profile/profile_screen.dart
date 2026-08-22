import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _ProfileHeader(lockEnabled: lockEnabled),
          const SizedBox(height: 28),
          _Section(
            title: '本地内容',
            icon: Icons.video_library_outlined,
            children: [
              _ProfileTile(
                  icon: Icons.bookmark_outline,
                  title: '我的收藏',
                  onTap: onOpenLibrary),
              _ProfileTile(
                  icon: Icons.history, title: '播放历史', onTap: onOpenLibrary),
            ],
          ),
          const SizedBox(height: 24),
          _Section(
            title: '应用设置',
            icon: Icons.tune_outlined,
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
            child: Text(
              'Cineo · 本地优先媒体中心',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CineoColors.textSecondary,
                  ),
            ),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      decoration: BoxDecoration(
        color: CineoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CineoColors.divider),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: CineoColors.primaryContainer,
            child: Icon(Icons.person_outline,
                color: CineoColors.primaryLight, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本地用户', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(lockEnabled ? '应用锁已开启' : '数据保存在本机',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CineoColors.textSecondary,
                        )),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: CineoColors.textSecondary),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: CineoColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: CineoColors.primaryLight,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CineoColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: CineoColors.divider),
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
      minVerticalPadding: 12,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: CineoColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: CineoColors.primaryLight, size: 20),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right,
          size: 20, color: CineoColors.textSecondary),
      onTap: onTap,
    );
  }
}
