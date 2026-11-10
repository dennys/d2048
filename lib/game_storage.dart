import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_keys.dart';

/// board 上的一個方塊（序列化形式）。
typedef TileData = ({int id, int value, int row, int col});

/// 自動存檔：目前遊戲狀態（不含 history）。
class SavedGame {
  final int boardSize;
  final List<TileData> tiles;
  final int score;
  final int moves;
  final int undoCount;
  final bool keepPlaying; // 過關後使用者選擇繼續

  const SavedGame({
    required this.boardSize,
    required this.tiles,
    required this.score,
    required this.moves,
    required this.undoCount,
    required this.keepPlaying,
  });

  Map<String, dynamic> toJson() => {
        'boardSize': boardSize,
        'tiles': [for (final t in tiles) {'id': t.id, 'value': t.value, 'row': t.row, 'col': t.col}],
        'score': score,
        'moves': moves,
        'undoCount': undoCount,
        'keepPlaying': keepPlaying,
      };

  factory SavedGame.fromJson(Map<String, dynamic> json) => SavedGame(
        boardSize: json['boardSize'] as int,
        tiles: [
          for (final t in json['tiles'] as List<dynamic>)
            (
              id: t['id'] as int,
              value: t['value'] as int,
              row: t['row'] as int,
              col: t['col'] as int,
            ),
        ],
        score: json['score'] as int,
        // 可選欄位給預設值：舊版 build 寫的存檔缺欄位時不要整份丟掉（靜默資料流失）。
        moves: json['moves'] as int? ?? 0,
        undoCount: json['undoCount'] as int? ?? 0,
        keepPlaying: json['keepPlaying'] as bool? ?? false,
      );
}

/// 命名快照：某個 board 狀態的 bookmark（不含 history）。
class BoardSnapshot {
  final String name;
  final int boardSize;
  final List<TileData> tiles;
  final int score;
  final DateTime savedAt;

  const BoardSnapshot({
    required this.name,
    required this.boardSize,
    required this.tiles,
    required this.score,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'boardSize': boardSize,
        'tiles': [for (final t in tiles) {'id': t.id, 'value': t.value, 'row': t.row, 'col': t.col}],
        'score': score,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory BoardSnapshot.fromJson(Map<String, dynamic> json) => BoardSnapshot(
        name: json['name'] as String? ?? '',
        boardSize: json['boardSize'] as int,
        tiles: [
          for (final t in json['tiles'] as List<dynamic>)
            (
              id: t['id'] as int,
              value: t['value'] as int,
              row: t['row'] as int,
              col: t['col'] as int,
            ),
        ],
        score: json['score'] as int? ?? 0,
        savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int? ?? 0),
      );
}

/// 累計統計。
class GameStats {
  int gamesPlayed;
  int wins;
  int maxTile;
  int totalMerges;

  GameStats({this.gamesPlayed = 0, this.wins = 0, this.maxTile = 0, this.totalMerges = 0});

  Map<String, dynamic> toJson() => {
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'maxTile': maxTile,
        'totalMerges': totalMerges,
      };

  factory GameStats.fromJson(Map<String, dynamic> json) => GameStats(
        gamesPlayed: json['gamesPlayed'] as int? ?? 0,
        wins: json['wins'] as int? ?? 0,
        maxTile: json['maxTile'] as int? ?? 0,
        totalMerges: json['totalMerges'] as int? ?? 0,
      );
}

/// 遊戲資料持久化（自動存檔／快照／最高分／統計）。
/// 使用者設定（語言、主題…）在 SettingsModel；這裡只管遊戲資料。
class GameStorage {
  GameStorage(this._prefs);
  final SharedPreferences _prefs;

  SavedGame? loadSavedGame() {
    final raw = _prefs.getString(Prefs.savedGame);
    if (raw == null) return null;
    try {
      return SavedGame.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // 損毀存檔 → 當沒有，開新遊戲
    }
  }

  Future<void> saveGame(SavedGame game) async {
    try {
      await _prefs.setString(Prefs.savedGame, jsonEncode(game.toJson()));
    } catch (e) {
      debugPrint('d2048 saveGame failed: $e');
    }
  }

  List<BoardSnapshot> loadSnapshots() {
    final raw = _prefs.getString(Prefs.snapshots);
    if (raw == null) return [];
    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return [];
    }
    // 逐個 parse：一個損毀的快照不該連累其他。
    final result = <BoardSnapshot>[];
    for (final e in decoded) {
      if (e is! Map<String, dynamic>) continue;
      try {
        result.add(BoardSnapshot.fromJson(e));
      } catch (_) {
        // 跳過損毀 entry
      }
    }
    return result;
  }

  Future<void> saveSnapshots(List<BoardSnapshot> list) async {
    try {
      await _prefs.setString(Prefs.snapshots, jsonEncode([for (final s in list) s.toJson()]));
    } catch (e) {
      debugPrint('d2048 saveSnapshots failed: $e');
    }
  }

  int bestScore(int size) {
    final raw = _prefs.getString(Prefs.bestScores);
    if (raw == null) return 0;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)[size.toString()] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setBestScore(int size, int score) async {
    final map = <String, int>{};
    final raw = _prefs.getString(Prefs.bestScores);
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) {
          map[e.key] = e.value as int;
        }
      } catch (_) {
        // 損毀 → 重頭算
      }
    }
    map[size.toString()] = score;
    try {
      await _prefs.setString(Prefs.bestScores, jsonEncode(map));
    } catch (e) {
      debugPrint('d2048 setBestScore failed: $e');
    }
  }

  GameStats loadStats() {
    final raw = _prefs.getString(Prefs.stats);
    if (raw == null) return GameStats();
    try {
      return GameStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return GameStats();
    }
  }

  Future<void> saveStats(GameStats stats) async {
    try {
      await _prefs.setString(Prefs.stats, jsonEncode(stats.toJson()));
    } catch (e) {
      debugPrint('d2048 saveStats failed: $e');
    }
  }
}