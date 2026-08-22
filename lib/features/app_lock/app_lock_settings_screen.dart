import 'package:flutter/material.dart';

import '../../core/platform/adaptive_navigation.dart';
import '../../core/theme/cineo_theme.dart';
import 'app_lock_controller.dart';
import 'app_lock_service.dart';
import 'pin_setup_screen.dart';

class AppLockSettingsScreen extends StatelessWidget {
  const AppLockSettingsScreen({required this.controller, super.key});

  final AppLockController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('应用锁设置')),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              Text(
                '保护 Cineo',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                controller.enabled
                    ? '应用打开或从后台恢复时将根据宽限期验证 PIN。'
                    : '应用锁当前未启用；设置 PIN 不会自动开启应用锁。',
                style: const TextStyle(
                  color: CineoColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                    secondary: const _LockIcon(
                      icon: Icons.lock_rounded,
                      color: Color(0xFFE94865),
                    ),
                    title: const Text('启用应用锁'),
                    subtitle: Text(
                      controller.hasPin ? '使用 6 位 PIN 保护应用' : '请先设置 6 位 PIN',
                    ),
                    value: controller.enabled,
                    onChanged: controller.hasPin
                        ? (enabled) => controller.setEnabled(enabled)
                        : null,
                  ),
                  const _GroupDivider(),
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                    leading: const _LockIcon(
                      icon: Icons.pin_outlined,
                      color: Color(0xFF5B82F5),
                    ),
                    title: Text(controller.hasPin ? '修改应用锁' : '设置应用锁'),
                    subtitle: Text(
                      controller.hasPin ? '更新当前的 6 位 PIN' : '设置后可手动启用应用锁',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push<void>(
                      adaptivePageRoute(
                        context,
                        builder: (_) => PinSetupScreen(
                          controller: controller,
                          requireCurrentPin: controller.hasPin,
                        ),
                      ),
                    ),
                  ),
                  if (controller.hasPin) ...[
                    const _GroupDivider(),
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                      leading: const _LockIcon(
                        icon: Icons.timer_outlined,
                        color: Color(0xFF40A7F5),
                      ),
                      title: const Text('后台返回后要求 PIN'),
                      subtitle: Text(controller.gracePeriod.label),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _chooseGracePeriod(context),
                    ),
                  ],
                ],
              ),
              if (controller.enabled) ...[
                const SizedBox(height: 24),
                _SettingsGroup(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                      leading: const _LockIcon(
                        icon: Icons.lock_clock_rounded,
                        color: Color(0xFFFF9F43),
                      ),
                      title: const Text('立即锁定'),
                      subtitle: const Text('下次打开需要输入 PIN'),
                      onTap: () async {
                        await controller.lock();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseGracePeriod(BuildContext context) async {
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
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CineoColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(children: children),
      );
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 68),
        child: Divider(height: 1, color: CineoColors.divider),
      );
}

class _LockIcon extends StatelessWidget {
  const _LockIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white),
      );
}
