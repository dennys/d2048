import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';
import '../game_storage.dart';
import '../tile_style.dart';

/// mini board 預覽（快照 list 用）。
class MiniBoard extends StatelessWidget {
  final int size;
  final List<TileData> tiles;
  final double cell;

  const MiniBoard({super.key, required this.size, required this.tiles, this.cell = 10});

  @override
  Widget build(BuildContext context) {
    const gap = 1.0;
    final side = cell * size + gap * (size + 1);
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        children: [
          for (var i = 0; i < size * size; i++)
            Positioned(
              left: gap + (i % size) * (cell + gap),
              top: gap + (i ~/ size) * (cell + gap),
              width: cell,
              height: cell,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          for (final t in tiles)
            Positioned(
              left: gap + t.col * (cell + gap),
              top: gap + t.row * (cell + gap),
              width: cell,
              height: cell,
              child: Container(
                decoration: BoxDecoration(
                  color: tileColor(t.value),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 存快照對話框：輸入名字，回傳名字（null = 取消或空）。
Future<String?> showSaveSnapshotDialog(BuildContext context, String defaultName) async {
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _SaveSnapshotDialog(defaultName: defaultName),
  );
  return (name == null || name.isEmpty) ? null : name;
}

class _SaveSnapshotDialog extends StatefulWidget {
  final String defaultName;

  const _SaveSnapshotDialog({required this.defaultName});

  @override
  State<_SaveSnapshotDialog> createState() => _SaveSnapshotDialogState();
}

class _SaveSnapshotDialogState extends State<_SaveSnapshotDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.defaultName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.saveSnapshot),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l.snapshotName),
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

/// 快照 list 對話框：tap 載入、🗑 刪除（[onDelete] 收到刪除後的完整 list，由呼叫方負責持久化）。
class SnapshotListDialog extends StatefulWidget {
  final List<BoardSnapshot> snapshots;
  final void Function(BoardSnapshot snapshot) onLoad;
  final void Function(List<BoardSnapshot> remaining) onDelete;

  const SnapshotListDialog({
    super.key,
    required this.snapshots,
    required this.onLoad,
    required this.onDelete,
  });

  @override
  State<SnapshotListDialog> createState() => _SnapshotListDialogState();
}

class _SnapshotListDialogState extends State<SnapshotListDialog> {
  late final List<BoardSnapshot> _items = [...widget.snapshots];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.loadSnapshot),
      content: SizedBox(
        width: 340,
        child: _items.isEmpty
            ? Text(l.noSnapshots)
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final s = _items[i];
                  final d = s.savedAt;
                  return ListTile(
                    leading: MiniBoard(size: s.boardSize, tiles: s.tiles),
                    title: Text(s.name),
                    subtitle: Text(
                      '${s.boardSize}×${s.boardSize} · ${l.score}: ${s.score} · '
                      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        setState(() => _items.removeAt(i));
                        widget.onDelete(_items);
                      },
                    ),
                    onTap: () => widget.onLoad(s),
                  );
                },
              ),
      ),
    );
  }
}