import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_keys.dart';

/// 遊戲模式：normal = 普通局；daily = 家庭每日局（同 seed 開局）。
enum GameMode { normal, daily }

/// 每日 seed：本地日期 → int（如 2026-11-10 → 20261110）。
int dailySeedFor(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// board 上的一個方塊（序列化形式）。
typedef TileData = ({int id, int value, int row, int col});

/// TileData list → JSON map list（SavedGame／BoardSnapshot 共用，避免各寫一份）。
List<Map<String, dynamic>> _tilesToJson(List<TileData> tiles) =>
    [for (final t in tiles) {'id': t.id, 'value': t.value, 'row': t.row, 'col': t.col}];

/// JSON list → TileData list（SavedGame／BoardSnapshot 共用）。
List<TileData> _tilesFromJson(List<dynamic> json) => [
      for (final t in json)
        (
          id: t['id'] as int,
          value: t['value'] as int,
          row: t['row'] as int,
          col: t['col'] as int,
        ),
    ];

/// 自動存檔：目前遊戲狀態（不含 history）。
class SavedGame {
  final int boardSize;
  final List<TileData> tiles;
  final int score;
  final int moves;
  final int undoCount;
  final bool keepPlaying; // 過關後使用者選擇繼續
  final int? seed; // daily 局的 seed（normal 為 null）

  const SavedGame({
    required this.boardSize,
    required this.tiles,
    required this.score,
    required this.moves,
    required this.undoCount,
    required this.keepPlaying,
    this.seed,
  });

  Map<String, dynamic> toJson() => {
        'boardSize': boardSize,
        'tiles': _tilesToJson(tiles),
        'score': score,
        'moves': moves,
        'undoCount': undoCount,
        'keepPlaying': keepPlaying,
        if (seed != null) 'seed': seed,
      };

  factory SavedGame.fromJson(Map<String, dynamic> json) => SavedGame(
        boardSize: json['boardSize'] as int,
        tiles: _tilesFromJson(json['tiles'] as List<dynamic>),
        score: json['score'] as int,
        // 可選欄位給預設值：舊版 build 寫的存檔缺欄位時不要整份丟掉（靜默資料流失）。
        moves: json['moves'] as int? ?? 0,
        undoCount: json['undoCount'] as int? ?? 0,
        keepPlaying: json['keepPlaying'] as bool? ?? false,
        seed: json['seed'] as int?,
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
        'tiles': _tilesToJson(tiles),
        'score': score,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory BoardSnapshot.fromJson(Map<String, dynamic> json) => BoardSnapshot(
        name: json['name'] as String? ?? '',
        boardSize: json['boardSize'] as int,
        tiles: _tilesFromJson(json['tiles'] as List<dynamic>),
        score: json['score'] as int? ?? 0,
        savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int? ?? 0),
      );
}

/// 累計統計（per-player）。
class GameStats {
  int gamesPlayed;
  int wins;
  int maxTile;
  int totalMerges;
  int dailyBest; // 今天 daily 局的最高分
  int lastDailyDate; // 0 = 沒玩過；否則 = 該 dailyBest 對應的日期 seed（如 20261110）

  GameStats({
    this.gamesPlayed = 0,
    this.wins = 0,
    this.maxTile = 0,
    this.totalMerges = 0,
    this.dailyBest = 0,
    this.lastDailyDate = 0,
  });

  Map<String, dynamic> toJson() => {
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'maxTile': maxTile,
        'totalMerges': totalMerges,
        'dailyBest': dailyBest,
        'lastDailyDate': lastDailyDate,
      };

  factory GameStats.fromJson(Map<String, dynamic> json) => GameStats(
        gamesPlayed: json['gamesPlayed'] as int? ?? 0,
        wins: json['wins'] as int? ?? 0,
        maxTile: json['maxTile'] as int? ?? 0,
        totalMerges: json['totalMerges'] as int? ?? 0,
        dailyBest: json['dailyBest'] as int? ?? 0,
        lastDailyDate: json['lastDailyDate'] as int? ?? 0,
      );
}

/// 遊戲資料持久化（自動存檔／快照／最高分／統計／玩家）。
/// 使用者設定（語言、主題…）在 SettingsModel；這裡只管遊戲資料。
///
/// 所有遊戲資料按玩家 namespace（`<base>/<player>`）；[currentPlayer] 是
/// 目前玩家，切換玩家後 load/save 自動跟到新 namespace。
class GameStorage {
  GameStorage(this._prefs) {
    _migrateIfNeeded();
    currentPlayer = _prefs.getString(Prefs.currentPlayer) ?? '';
  }
  final SharedPreferences _prefs;
  String currentPlayer = '';

  /// 舊版（無 per-player）全域資料搬進預設玩家，只跑一次。
  void _migrateIfNeeded() {
    if (_prefs.containsKey(Prefs.players)) return;
    final oldKeys = [Prefs.savedGame, Prefs.snapshots, Prefs.bestScores, Prefs.stats];
    final players = <String>[];
    if (oldKeys.any(_prefs.containsKey)) {
      players.add(PrefsDefaults.defaultPlayer);
      for (final k in oldKeys) {
        final raw = _prefs.getString(k);
        if (raw != null) {
          _prefs.setString('$k/${PrefsDefaults.defaultPlayer}', raw);
          _prefs.remove(k);
        }
      }
    }
    _prefs.setString(Prefs.players, jsonEncode(players));
    if (players.isNotEmpty) _prefs.setString(Prefs.currentPlayer, players.first);
  }

  List<String> loadPlayers() {
    final raw = _prefs.getString(Prefs.players);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  /// 新增玩家（已存在則只切換）並設為目前玩家。
  Future<void> addPlayer(String name) async {
    final players = loadPlayers();
    if (!players.contains(name)) {
      players.add(name);
      await _prefs.setString(Prefs.players, jsonEncode(players));
    }
    await setCurrentPlayer(name);
  }

  Future<void> setCurrentPlayer(String name) async {
    currentPlayer = name;
    await _prefs.setString(Prefs.currentPlayer, name);
  }

  String _key(String base, [String? player]) => '$base/${player ?? currentPlayer}';

  SavedGame? loadSavedGame(GameMode mode) {
    final raw = _prefs.getString(_key(mode == GameMode.daily ? Prefs.savedGameDaily : Prefs.savedGame));
    if (raw == null) return null;
    try {
      return SavedGame.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('d2048 saveGame undecodable: $e'); // 損毀存檔 → 當沒有，開新遊戲
      return null;
    }
  }

  Future<void> saveGame(SavedGame game, GameMode mode) async {
    try {
      await _prefs.setString(_key(mode == GameMode.daily ? Prefs.savedGameDaily : Prefs.savedGame), jsonEncode(game.toJson()));
    } catch (e) {
      debugPrint('d2048 saveGame failed: $e');
    }
  }

  List<BoardSnapshot> loadSnapshots() {
    final raw = _prefs.getString(_key(Prefs.snapshots));
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
      await _prefs.setString(_key(Prefs.snapshots), jsonEncode([for (final s in list) s.toJson()]));
    } catch (e) {
      debugPrint('d2048 saveSnapshots failed: $e');
    }
  }

  int bestScore(int size) => bestScoreFor(currentPlayer, size);

  int bestScoreFor(String player, int size) {
    final raw = _prefs.getString(_key(Prefs.bestScores, player));
    if (raw == null) return 0;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)[size.toString()] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setBestScore(int size, int score) async {
    final key = _key(Prefs.bestScores);
    final map = <String, int>{};
    final raw = _prefs.getString(key);
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
      await _prefs.setString(key, jsonEncode(map));
    } catch (e) {
      debugPrint('d2048 setBestScore failed: $e');
    }
  }

  GameStats loadStats() => loadStatsFor(currentPlayer);

  GameStats loadStatsFor(String player) {
    final raw = _prefs.getString(_key(Prefs.stats, player));
    if (raw == null) return GameStats();
    try {
      return GameStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return GameStats();
    }
  }

  Future<void> saveStats(GameStats stats) async {
    try {
      await _prefs.setString(_key(Prefs.stats), jsonEncode(stats.toJson()));
    } catch (e) {
      debugPrint('d2048 saveStats failed: $e');
    }
  }
}