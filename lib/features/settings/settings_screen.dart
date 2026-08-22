import 'package:flutter/material.dart';

import 'adult_source_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.adultSourceSettings,
  });

  final AdultSourceSettings adultSourceSettings;

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
                  onChanged: (value) =>
                      adultSourceSettings.setShowAdultSources(value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
