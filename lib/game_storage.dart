import 'dart:convert';

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
        moves: json['moves'] as int,
        undoCount: json['undoCount'] as int,
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
        name: json['name'] as String,
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
        savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int),
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

  Future<void> saveGame(SavedGame game) =>
      _prefs.setString(Prefs.savedGame, jsonEncode(game.toJson()));

  List<BoardSnapshot> loadSnapshots() {
    final raw = _prefs.getString(Prefs.snapshots);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List<dynamic>)
          BoardSnapshot.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSnapshots(List<BoardSnapshot> list) =>
      _prefs.setString(Prefs.snapshots, jsonEncode([for (final s in list) s.toJson()]));

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
    await _prefs.setString(Prefs.bestScores, jsonEncode(map));
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

  Future<void> saveStats(GameStats stats) =>
      _prefs.setString(Prefs.stats, jsonEncode(stats.toJson()));
}