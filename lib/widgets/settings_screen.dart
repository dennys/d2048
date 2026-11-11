import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';
import '../game_storage.dart';
import '../settings_model.dart';
import '../telegram_service.dart';

/// Telegram 家庭排行榜設定：頻道（必填才啟用）、bot token（選填）、測試按鈕。
class _TelegramSection extends StatefulWidget {
  final SettingsModel settings;

  const _TelegramSection({required this.settings});

  @override
  State<_TelegramSection> createState() => _TelegramSectionState();
}

class _TelegramSectionState extends State<_TelegramSection> {
  late final TextEditingController _channel =
      TextEditingController(text: widget.settings.telegramChannel);
  late final TextEditingController _token =
      TextEditingController(text: widget.settings.telegramToken);
  bool _busy = false;

  @override
  void dispose() {
    _channel.dispose();
    _token.dispose();
    super.dispose();
  }

  /// 把欄位寫回設定；頻道格式錯誤時回傳 false 並留在原地。
  Future<bool> _commit() async {
    final l = AppLocalizations.of(context)!;
    final channel = TelegramService.normalizeChannel(_channel.text);
    if (channel == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.telegramInvalidChannel)));
      return false;
    }
    _channel.text = channel;
    await widget.settings.setTelegramChannel(channel);
    await widget.settings.setTelegramToken(_token.text.trim());
    return true;
  }

  Future<void> _test() async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _commit() || !mounted) return;
    if (widget.settings.telegramChannel.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.telegramInvalidChannel)));
      return;
    }
    setState(() => _busy = true);
    String message;
    try {
      final token = widget.settings.telegramToken;
      final channel = widget.settings.telegramChannel;
      if (token.isNotEmpty) await TelegramService.getMeUsername(token);
      if (channel.isNotEmpty) await TelegramService.fetchScores(channel);
      message = l.telegramTestOk;
    } on TelegramException catch (e) {
      message = '${l.telegramTestFail}: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l.telegramSection,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _channel,
                decoration: InputDecoration(labelText: l.telegramChannel, hintText: '@d2048_family'),
                onSubmitted: (_) => _commit(),
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _token,
                obscureText: true,
                decoration: InputDecoration(labelText: l.telegramToken),
                onSubmitted: (_) => _commit(),
                onTapOutside: (_) => _commit(),
              ),
              const SizedBox(height: 4),
              Text(l.telegramHelp, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _test,
                  child: Text(l.telegramTest),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }
}

/// 設定頁（比照 dHealth 的 SetupScreen）：語言、主題、震動、Telegram、統計。
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
          const Divider(),
          _TelegramSection(settings: settings),
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