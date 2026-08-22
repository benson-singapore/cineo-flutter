import 'package:flutter/material.dart';

import '../../core/platform/adaptive_navigation.dart';
import '../../core/theme/cineo_theme.dart';
import '../app_lock/app_lock_controller.dart';
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
      appBar: AppBar(
        title: const Text('通用设置'),
        leading: const BackButton(),
      ),
      body: SafeArea(
        top: false,
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
                  '管理内容、隐私与本地媒体体验',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CineoColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 16),
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
                        adaptivePageRoute(
                          context,
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
                if (_matches('内容访问 成人 标记 视频源 显示 隐藏 播放历史')) ...[
                  const _SettingsSectionLabel(title: '内容访问'),
                  _SettingsPanel(
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 9, 12, 9),
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
                        if (widget.adultSourceSettings.showAdultSources)
                          SwitchListTile.adaptive(
                            contentPadding:
                                const EdgeInsets.fromLTRB(16, 0, 12, 9),
                            secondary: const _SettingsIcon(
                              icon: Icons.history_toggle_off_rounded,
                              color: Color(0xFFB38CFF),
                            ),
                            title: const Text('隐藏成人源播放历史'),
                            subtitle: const Text('开启时不会在首页和播放历史中展示成人源记录'),
                            value: widget.adultSourceSettings.hideAdultHistory,
                            onChanged:
                                widget.adultSourceSettings.setHideAdultHistory,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
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
      _matches('内容访问 成人 标记 视频源 显示 隐藏 播放历史');

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
            '试试“TMDB”或“成人标记”',
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
