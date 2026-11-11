import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';

/// 首次啟動：輸入玩家名字。回傳名字（null = 取消或空）。
Future<String?> showPlayerNameDialog(BuildContext context) async {
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => const _PlayerNameDialog(),
  );
  return (name == null || name.isEmpty) ? null : name;
}

/// controller 一定要在 dialog 自己的 dispose 釋放：[showDialog] 在 pop 當下就
/// resolve，退場動畫期間 TextField 還挂在樹上，此時 dispose 會用到已釋放的
/// controller（debug 直接噴 assertion）。比照 snapshots.dart 的 _SaveSnapshotDialog。
class _PlayerNameDialog extends StatefulWidget {
  const _PlayerNameDialog();

  @override
  State<_PlayerNameDialog> createState() => _PlayerNameDialogState();
}

class _PlayerNameDialogState extends State<_PlayerNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.whoIsPlaying),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l.yourName),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// 切換玩家：tap 現有玩家、或輸入新名字新增（[onAdd] 會把新玩家設為目前）。
/// 回傳選定的玩家名（null = 取消）。
Future<String?> showPlayerPicker(
  BuildContext context, {
  required List<String> players,
  required String current,
  required Future<String> Function(String name) onAdd,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _PlayerPickerDialog(players: players, current: current, onAdd: onAdd),
  );
}

class _PlayerPickerDialog extends StatefulWidget {
  final List<String> players;
  final String current;
  final Future<String> Function(String name) onAdd;

  const _PlayerPickerDialog({
    required this.players,
    required this.current,
    required this.onAdd,
  });

  @override
  State<_PlayerPickerDialog> createState() => _PlayerPickerDialogState();
}

class _PlayerPickerDialogState extends State<_PlayerPickerDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(String raw) async {
    if (raw.trim().isEmpty) return;
    // onAdd 會回傳實際玩家名（可能與敲進去的大小寫不同）→ 用回傳值 pop，
    // 否則呼叫端拿原始字串去 setCurrentPlayer，會切到不存在的 namespace。
    final name = await widget.onAdd(raw);
    if (mounted) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.players),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 玩家清單可捲：玩家一多，原本 Column 直接把下面的「新增」那列擠出對話框。
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in widget.players)
                    ListTile(
                      dense: true,
                      title: Text(p),
                      trailing: p == widget.current ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(labelText: l.addPlayer),
                    onSubmitted: _add,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _add(_controller.text),
                  child: Text(l.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
