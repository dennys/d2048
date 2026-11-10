import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';
import '../game_storage.dart';
import '../settings_model.dart';

/// 設定頁（比照 dHealth 的 SetupScreen）：語言、主題、震動、統計。
class SettingsScreen extends StatelessWidget {
  final SettingsModel settings;
  final GameStats? stats;

  const SettingsScreen({super.key, required this.settings, this.stats});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              l.language,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            dense: true,
            title: Text(l.language),
            subtitle: DropdownButton<String>(
              value: settings.language,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 'system', child: Text(l.followSystem)),
                DropdownMenuItem(value: 'en', child: Text(l.english)),
                DropdownMenuItem(value: 'zh_Hant', child: Text(l.traditionalChinese)),
                DropdownMenuItem(value: 'zh_Hans', child: Text(l.simplifiedChinese)),
              ],
              onChanged: (value) => value != null ? settings.setLanguage(value) : null,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              l.theme,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            dense: true,
            title: Text(l.theme),
            subtitle: DropdownButton<String>(
              value: settings.theme,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 'system', child: Text(l.system)),
                DropdownMenuItem(value: 'light', child: Text(l.light)),
                DropdownMenuItem(value: 'dark', child: Text(l.dark)),
              ],
              onChanged: (value) => value != null ? settings.setTheme(value) : null,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              l.haptics,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            dense: true,
            title: Text(l.haptics),
            value: settings.haptics,
            onChanged: settings.setHaptics,
          ),
          if (stats != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l.stats,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(dense: true, title: Text(l.gamesPlayed), trailing: Text('${stats!.gamesPlayed}')),
            ListTile(dense: true, title: Text(l.wins), trailing: Text('${stats!.wins}')),
            ListTile(dense: true, title: Text(l.maxTile), trailing: Text('${stats!.maxTile}')),
            ListTile(dense: true, title: Text(l.totalMerges), trailing: Text('${stats!.totalMerges}')),
          ],
        ],
      ),
    );
  }
}