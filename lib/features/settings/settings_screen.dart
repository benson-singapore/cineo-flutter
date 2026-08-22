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

class SettingsScreen extends StatefulWidget {
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
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: widget.adultSourceSettings,
          builder: (context, _) {
            if (!widget.adultSourceSettings.initialized) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 128),
              children: [
                Text(
                  '设置',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '管理内容、隐私与本地媒体体验',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CineoColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 20),
                _SettingsSearchField(
                  controller: _searchController,
                  query: _query,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
                const SizedBox(height: 28),
                if (_matches('媒体服务 tmdb 数据增强 海报 剧集 简介')) ...[
                  const _SettingsSectionLabel(title: '媒体服务'),
                  _SettingsPanel(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                      leading: const _SettingsIcon(
                        icon: Icons.auto_awesome_rounded,
                        color: Color(0xFF5B82F5),
                      ),
                      title: const Text('TMDB 数据增强'),
                      subtitle: const Text('管理海报、剧集资料和每集简介的数据服务'),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: CineoColors.textSecondary),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TMDBSettingsScreen(
                            settings: widget.tmdbSettings,
                            cacheController: widget.tmdbCacheController,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                if (_matches('内容访问 成人 标记 视频源 显示 隐藏')) ...[
                  const _SettingsSectionLabel(title: '内容访问'),
                  _SettingsPanel(
                    child: SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                      secondary: const _SettingsIcon(
                        icon: Icons.explicit_rounded,
                        color: Color(0xFFE94865),
                      ),
                      title: const Text('显示成人标记的视频源'),
                      subtitle: const Text('关闭时仍会保存配置，但不会在来源管理中展示'),
                      value: widget.adultSourceSettings.showAdultSources,
                      onChanged: (value) =>
                          _onAdultSourcesChanged(context, value),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                if (_matches('隐私 安全 应用锁 pin 密码 宽限期 立即锁定')) ...[
                  const _SettingsSectionLabel(title: '隐私与安全'),
                  _buildLockSettings(context),
                ],
                if (!_hasMatches) const _SettingsEmptySearchState(),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _hasMatches =>
      _matches('媒体服务 tmdb 数据增强 海报 剧集 简介') ||
      _matches('内容访问 成人 标记 视频源 显示 隐藏') ||
      _matches('隐私 安全 应用锁 pin 密码 宽限期 立即锁定');

  bool _matches(String keywords) {
    if (_query.isEmpty) return true;
    return keywords.toLowerCase().contains(_query.toLowerCase());
  }

  Future<void> _onAdultSourcesChanged(
    BuildContext context,
    bool value,
  ) async {
    if (!value) {
      await widget.adultSourceSettings.setShowAdultSources(false);
      return;
    }
    final controller = widget.appLockController;
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
      await widget.adultSourceSettings.setShowAdultSources(true);
    }
  }

  Widget _buildLockSettings(BuildContext context) {
    final controller = widget.appLockController;
    if (controller == null) {
      return const _SettingsPanel(
        child: ListTile(
          leading: _SettingsIcon(
            icon: Icons.lock_rounded,
            color: Color(0xFFE94865),
          ),
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
              contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
              leading: const _SettingsIcon(
                icon: Icons.lock_rounded,
                color: Color(0xFFE94865),
              ),
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
              const _SettingsPanelDivider(),
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                leading: const _SettingsIcon(
                  icon: Icons.timer_outlined,
                  color: Color(0xFF40A7F5),
                ),
                title: const Text('后台返回后要求 PIN'),
                subtitle: Text(controller.gracePeriod.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _chooseGracePeriod(context, controller),
              ),
              const _SettingsPanelDivider(),
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                leading: const _SettingsIcon(
                  icon: Icons.lock_clock_rounded,
                  color: Color(0xFFFF9F43),
                ),
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

class _SettingsSearchField extends StatelessWidget {
  const _SettingsSearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索设置',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

class _SettingsEmptySearchState extends StatelessWidget {
  const _SettingsEmptySearchState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 34),
      child: Column(
        children: [
          Icon(Icons.manage_search_rounded,
              size: 34, color: CineoColors.textSecondary.withOpacity(.8)),
          const SizedBox(height: 10),
          const Text('没有匹配的设置项'),
          const SizedBox(height: 4),
          Text(
            '试试“应用锁”、“TMDB”或“成人标记”',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CineoColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 9),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: CineoColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
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
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }
}

class _SettingsPanelDivider extends StatelessWidget {
  const _SettingsPanelDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 68),
      child: Divider(height: 1, color: CineoColors.divider),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 24, color: Colors.white),
    );
  }
}
