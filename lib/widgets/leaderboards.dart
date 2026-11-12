import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';
import '../settings_keys.dart';
import '../telegram_service.dart';

/// 排行榜列：rank（粗體前 3 名）、name、score。
Widget _rankRow({required String rank, required String name, required String score, required bool bold}) =>
    ListTile(
      dense: true,
      leading: Text(rank, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      title: Text(name),
      trailing: Text(score),
    );

String _formatDate(int yyyymmdd) {
  final y = yyyymmdd ~/ 10000;
  final m = (yyyymmdd ~/ 100) % 100;
  final d = yyyymmdd % 100;
  return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// 家庭排行榜：頻道上的所有對局，日期新→舊，同日分數高→低。名字顯示為小寫。
class FamilyLeaderboardDialog extends StatelessWidget {
  final List<TelegramGame> games;

  const FamilyLeaderboardDialog({super.key, required this.games});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = TelegramService.ranked(games);
    return AlertDialog(
      title: Text(l.telegramSection),
      content: SizedBox(
        width: 320,
        child: rows.isEmpty
            ? Text(l.noScores)
            : ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final g = rows[i];
                  return ListTile(
                    dense: true,
                    title: Text(g.player.toLowerCase()),
                    subtitle: Text('${_formatDate(g.date)} · ${g.size}×${g.size}'),
                    trailing: Text('${g.score}'),
                  );
                },
              ),
      ),
    );
  }
}

/// 本地排行榜：每格數 top N（跨玩家），高→低。
class LeaderboardDialog extends StatelessWidget {
  final List<String> players;
  final int Function(String player, int size) bestScoreFor;
  final int initialSize;

  const LeaderboardDialog({
    super.key,
    required this.players,
    required this.bestScoreFor,
    required this.initialSize,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    var size = initialSize;
    return StatefulBuilder(
      builder: (context, setState) {
        final entries = [
          for (final p in players)
            (p, bestScoreFor(p, size)),
        ].where((e) => e.$2 > 0).toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
        return AlertDialog(
          title: Text(l.leaderboard),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in PrefsDefaults.boardSizeOptions)
                      ButtonSegment<int>(
                        value: s,
                        label: Text('$s×$s', style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  selected: {size},
                  onSelectionChanged: (v) => setState(() => size = v.first),
                ),
                const Divider(),
                entries.isEmpty
                    ? Text(l.noScores)
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: entries.length > PrefsDefaults.leaderboardTopN
                            ? PrefsDefaults.leaderboardTopN
                            : entries.length,
                        itemBuilder: (context, i) {
                          final (name, score) = entries[i];
                          return _rankRow(
                            rank: '${i + 1}',
                            name: name,
                            score: '$score',
                            bold: i < 3,
                          );
                        },
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}