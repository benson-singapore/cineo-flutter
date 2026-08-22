import 'package:flutter/material.dart';

import '../app_lock/app_lock_controller.dart';
import '../app_lock/app_lock_service.dart';
import '../app_lock/pin_setup_screen.dart';
import '../app_lock/pin_verification_dialog.dart';
import 'adult_source_settings.dart';
import 'tmdb_settings.dart';
import 'tmdb_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.adultSourceSettings,
    required this.tmdbSettings,
    this.appLockController,
  });

  final AdultSourceSettings adultSourceSettings;
  final TMDBSettings tmdbSettings;
  final AppLockController? appLockController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通用设置')),
      body: AnimatedBuilder(
        animation: adultSourceSettings,
        builder: (context, _) {
          if (!adultSourceSettings.initialized) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text('内容显示', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SwitchListTile(
                  title: const Text('显示成人标记的视频源'),
                  subtitle: const Text('关闭时仍会保存配置，但不会在来源管理中展示'),
                  value: adultSourceSettings.showAdultSources,
                  onChanged: (value) => _onAdultSourcesChanged(context, value),
                ),
              ),
              const SizedBox(height: 24),
              Text('隐私与安全', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              _buildLockSettings(context),
              const SizedBox(height: 24),
              Text('数据增强', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('TMDB 数据增强'),
                  subtitle: const Text('管理海报、剧集资料和每集简介的数据服务'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TMDBSettingsScreen(settings: tmdbSettings),
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
      return const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('应用锁'),
        subtitle: Text('应用锁设置由主应用入口提供'),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
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
                leading: const Icon(Icons.timer_outlined),
                title: const Text('后台返回后要求 PIN'),
                subtitle: Text(controller.gracePeriod.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _chooseGracePeriod(context, controller),
              ),
              const Divider(height: 1),
              ListTile(
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
