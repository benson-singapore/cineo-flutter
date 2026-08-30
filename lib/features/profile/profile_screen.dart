import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';
import '../app_lock/app_lock_controller.dart';
import '../update/app_update_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    this.onOpenFavorites,
    this.onOpenHistory,
    this.onOpenDownloads,
    this.onOpenSources,
    this.onOpenSettings,
    this.onOpenAppLock,
    this.onLockNow,
    this.appLockController,
    this.updateService,
    this.onOpenUpdates,
    super.key,
  });

  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenDownloads;
  final VoidCallback? onOpenSources;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenAppLock;
  final VoidCallback? onLockNow;
  final AppLockController? appLockController;
  final AppUpdateService? updateService;
  final VoidCallback? onOpenUpdates;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: appLockController ?? Listenable.merge(const []),
        builder: (context, _) {
          final lockEnabled = appLockController?.enabled ?? false;
          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 116),
              children: [
                Text(
                  '我的',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 14),
                _ProfileHeader(lockEnabled: lockEnabled),
                const SizedBox(height: 20),
                _Section(
                  title: '本地内容',
                  children: [
                    _ProfileTile(
                        icon: Icons.bookmark_outline,
                        color: const Color(0xFFFF9F43),
                        title: '我的收藏',
                        onTap: onOpenFavorites),
                    _ProfileTile(
                        icon: Icons.history,
                        color: const Color(0xFF5B82F5),
                        title: '播放历史',
                        onTap: onOpenHistory),
                    _ProfileTile(
                        icon: Icons.download_for_offline_outlined,
                        color: const Color(0xFF2AA889),
                        title: '缓存下载',
                        subtitle: '管理已缓存的视频和下载任务',
                        onTap: onOpenDownloads),
                  ],
                ),
                const SizedBox(height: 18),
                _Section(
                  title: '应用设置',
                  children: [
                    _ProfileTile(
                        icon: Icons.link,
                        color: const Color(0xFF35B885),
                        title: '视频源管理',
                        onTap: onOpenSources),
                    _ProfileTile(
                        icon: Icons.lock_outline,
                        color: const Color(0xFFE94865),
                        title: '应用锁',
                        subtitle: lockEnabled ? '已启用' : '未启用',
                        onTap: onOpenAppLock),
                    _ProfileTile(
                        icon: Icons.settings_outlined,
                        color: const Color(0xFF8087F4),
                        title: '通用设置',
                        onTap: onOpenSettings),
                    if (updateService != null)
                      AnimatedBuilder(
                        animation: updateService!,
                        builder: (context, _) => _ProfileTile(
                          icon: Icons.system_update_outlined,
                          color: const Color(0xFF3AA8FF),
                          title: updateService!.hasUpdate ? '发现新版本' : '版本更新',
                          subtitle: updateService!.hasUpdate
                              ? '最新版本 v${updateService!.latestVersion!.replaceFirst(RegExp(r'^[vV]'), '')}'
                              : '当前已是最新版本',
                          showBadge: updateService!.hasUpdate,
                          onTap: onOpenUpdates,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                AnimatedBuilder(
                  animation: updateService ?? Listenable.merge(const []),
                  builder: (context, _) => Column(
                    children: [
                      Text(
                        '当前版本 v${updateService?.currentVersion ?? '1.0.3'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: CineoColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cineo · 本地优先媒体中心',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: CineoColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        color: CineoColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: CineoColors.primaryContainer,
            child: Icon(Icons.person_outline,
                color: CineoColors.primaryLight, size: 30),
          ),
          const SizedBox(width: 14),
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
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: CineoColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CineoColors.surface,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const _ProfilePanelDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfilePanelDivider extends StatelessWidget {
  const _ProfilePanelDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 68),
      child: Divider(height: 1, color: CineoColors.divider),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.color,
    required this.title,
    this.onTap,
    this.subtitle,
    this.showBadge = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback? onTap;
  final String? subtitle;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      minVerticalPadding: 6,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                color: CineoColors.textSecondary,
                fontSize: 12,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBadge)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFF4D67),
                shape: BoxShape.circle,
              ),
            ),
          const Icon(Icons.chevron_right,
              size: 20, color: CineoColors.textSecondary),
        ],
      ),
      onTap: onTap,
    );
  }
}
