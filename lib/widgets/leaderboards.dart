import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';
import '../game_storage.dart';
import '../settings_keys.dart';

/// 家庭每日排行榜：今天（[todaySeed]）各玩家 daily 局最高分，高→低；沒玩的排最後。
class DailyLeaderboardDialog extends StatelessWidget {
  final List<(String, GameStats)> rows; // (player, stats)
  final int todaySeed;

  const DailyLeaderboardDialog({super.key, required this.rows, required this.todaySeed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final played = rows.where((r) => r.$2.lastDailyDate == todaySeed).toList()
      ..sort((a, b) => b.$2.dailyBest.compareTo(a.$2.dailyBest));
    final rest = rows.where((r) => r.$2.lastDailyDate != todaySeed).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return AlertDialog(
      title: Text(l.dailyLeaderboard),
      content: SizedBox(
        width: 320,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: played.length + rest.length,
          itemBuilder: (context, i) {
            final (name, stats) = i < played.length ? played[i] : rest[i - played.length];
            final isPlayed = i < played.length;
            return ListTile(
              dense: true,
              leading: Text(
                isPlayed ? '${i + 1}' : '·',
                style: TextStyle(fontWeight: i < 3 ? FontWeight.bold : FontWeight.normal),
              ),
              title: Text(name),
              trailing: Text(isPlayed ? '${stats.dailyBest}' : l.notPlayed),
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
    return StatefulBuilder(
      builder: (context, setState) {
        var size = initialSize;
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
                RadioGroup<int>(
                  groupValue: size,
                  onChanged: (v) {
                    if (v != null) setState(() => size = v);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final s in PrefsDefaults.boardSizeOptions)
                        RadioListTile<int>(
                          value: s,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('$s×$s', style: const TextStyle(fontSize: 14)),
                        ),
                    ],
                  ),
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
                          return ListTile(
                            dense: true,
                            leading: Text(
                              '${i + 1}',
                              style: TextStyle(fontWeight: i < 3 ? FontWeight.bold : FontWeight.normal),
                            ),
                            title: Text(name),
                            trailing: Text('$score'),
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