import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';

/// 首次啟動：輸入玩家名字。回傳名字（null = 取消或空）。
Future<String?> showPlayerNameDialog(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.whoIsPlaying),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l.yourName),
        onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(l.save),
        ),
      ],
    ),
  );
  controller.dispose();
  return (name == null || name.isEmpty) ? null : name;
}

/// 切換玩家：tap 現有玩家、或輸入新名字新增（[onAdd] 會把新玩家設為目前）。
/// 回傳選定的玩家名（null = 取消）。
Future<String?> showPlayerPicker(
  BuildContext context, {
  required List<String> players,
  required String current,
  required Future<void> Function(String name) onAdd,
}) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final chosen = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.players),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in players)
              ListTile(
                dense: true,
                title: Text(p),
                trailing: p == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(dialogContext, p),
              ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(labelText: l.addPlayer),
                    onSubmitted: (v) {
                      final name = v.trim();
                      if (name.isEmpty) return;
                      onAdd(name);
                      Navigator.pop(dialogContext, name);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isEmpty) return;
                    onAdd(name);
                    Navigator.pop(dialogContext, name);
                  },
                  child: Text(l.add),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
  return chosen;
}