import 'package:flutter/material.dart';

import '../../core/theme/cineo_theme.dart';
import '../app_lock/app_lock_controller.dart';
import '../app_lock/app_lock_service.dart';
import '../app_lock/pin_setup_screen.dart';
import '../app_lock/pin_verification_dialog.dart';
import 'adult_source_settings.dart';
import 'tmdb_settings.dart';
import 'tmdb_disk_cache_controller.dart';
import 'tmdb_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.adultSourceSettings,
    required this.tmdbSettings,
    required this.tmdbCacheController,
    this.appLockController,
  });

  final AdultSourceSettings adultSourceSettings;
  final TMDBSettings tmdbSettings;
  final TmdbDiskCacheController tmdbCacheController;
  final AppLockController? appLockController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通用设置')),
      body: AnimatedBuilder(
        animation: adultSourceSettings,
        builder: (context, _) {
          if (!adultSourceSettings.initialized) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const _SettingsSectionLabel(
                icon: Icons.visibility_outlined,
                title: '内容显示',
              ),
              _SettingsPanel(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  secondary: const Icon(Icons.explicit_outlined,
                      color: CineoColors.primaryLight),
                  title: const Text('显示成人标记的视频源'),
                  subtitle: const Text('关闭时仍会保存配置，但不会在来源管理中展示'),
                  value: adultSourceSettings.showAdultSources,
                  onChanged: (value) => _onAdultSourcesChanged(context, value),
                ),
              ),
              const SizedBox(height: 28),
              const _SettingsSectionLabel(
                icon: Icons.shield_outlined,
                title: '隐私与安全',
              ),
              _buildLockSettings(context),
              const SizedBox(height: 28),
              const _SettingsSectionLabel(
                icon: Icons.auto_awesome_outlined,
                title: '数据增强',
              ),
              _SettingsPanel(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('TMDB 数据增强'),
                  subtitle: const Text('管理海报、剧集资料和每集简介的数据服务'),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: CineoColors.textSecondary),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TMDBSettingsScreen(
                        settings: tmdbSettings,
                        cacheController: tmdbCacheController,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onAdultSourcesChanged(
    BuildContext context,
    bool value,
  ) async {
    if (!value) {
      await adultSourceSettings.setShowAdultSources(false);
      return;
    }
    final controller = appLockController;
    if (controller == null) {
      _showMessage(context, '应用锁尚未接入，请先设置应用锁');
      return;
    }
    if (!controller.hasPin) {
      _showMessage(context, '请先设置 PIN，再启用成人标记');
      return;
    }
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) => PinVerificationDialog(controller: controller),
    );
    if (verified == true) {
      await adultSourceSettings.setShowAdultSources(true);
    }
  }

  Widget _buildLockSettings(BuildContext context) {
    final controller = appLockController;
    if (controller == null) {
      return const _SettingsPanel(
        child: ListTile(
          leading: Icon(Icons.lock_outline, color: CineoColors.primaryLight),
          title: Text('应用锁'),
          subtitle: Text('应用锁设置由主应用入口提供'),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _SettingsPanel(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              leading: const Icon(Icons.lock_outline,
                  color: CineoColors.primaryLight),
              title: Text(controller.hasPin ? '修改应用锁 PIN' : '设置应用锁 PIN'),
              subtitle: Text(
                controller.hasPin ? 'PIN 已设置，保存在本机安全存储中' : '保护本机数据与成人内容设置',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PinSetupScreen(
                    controller: controller,
                    requireCurrentPin: controller.hasPin,
                  ),
                ),
              ),
            ),
            if (controller.hasPin) ...[
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                leading: const Icon(Icons.timer_outlined),
                title: const Text('后台返回后要求 PIN'),
                subtitle: Text(controller.gracePeriod.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _chooseGracePeriod(context, controller),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                leading: const Icon(Icons.lock_clock_outlined),
                title: const Text('立即锁定'),
                onTap: () => controller.lock(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _chooseGracePeriod(
    BuildContext context,
    AppLockController controller,
  ) async {
    final selected = await showModalBottomSheet<AppLockGracePeriod>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择 PIN 宽限期')),
            for (final period in AppLockGracePeriod.values)
              RadioListTile<AppLockGracePeriod>(
                value: period,
                groupValue: controller.gracePeriod,
                title: Text(period.label),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await controller.setGracePeriod(selected);
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CineoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CineoColors.divider),
      ),
      child: child,
    );
  }
}
