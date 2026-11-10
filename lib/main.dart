import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_storage.dart';
import 'generated/l10n/app_localizations.dart';
import 'settings_keys.dart';
import 'settings_model.dart';
import 'tile_style.dart';
import 'widgets/leaderboards.dart';
import 'widgets/players.dart';
import 'widgets/settings_screen.dart';
import 'widgets/snapshots.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = await SettingsModel.load(prefs); // 載入完成才 runApp：首幀就是正確的設定值
  runApp(Game2048App(settings: settings, prefs: prefs));
}

class Game2048App extends StatelessWidget {
  final SettingsModel settings;
  final SharedPreferences prefs;
  final Random? random; // 測試注入用；null = 真隨機

  const Game2048App({super.key, required this.settings, required this.prefs, this.random});

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder：語言/主題改完，MaterialApp 立刻重建（locale/themeMode 生效）。
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: '2048',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
          ),
          themeMode: settings.getThemeMode(),
          locale: settings.getLocale(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(settings: settings, prefs: prefs, random: random),
        );
      },
    );
  }
}

class GameScreen extends StatefulWidget {
  final SettingsModel settings;
  final SharedPreferences prefs;
  final Random? random; // 測試注入用；null = 真隨機

  const GameScreen({super.key, required this.settings, required this.prefs, this.random});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _animDuration = Duration(milliseconds: 150);

  late final GameStorage storage;

  int size = 4;
  final List<Tile> tiles = [];
  final List<_Snapshot> history = [];
  final List<_Snapshot> redoStack = [];
  int score = 0;
  int moves = 0;
  int undoCount = 0;
  int best = 0;
  bool won = false;
  bool keepPlaying = false;
  bool gameOver = false;
  GameStats stats = GameStats();
  int _gain = 0; // 上一手得到的分數（+N 浮字）
  int _gainKey = 0; // 浮字動畫重開的 key
  late final Random random = widget.random ?? Random();
  int _nextId = 1;

  GameMode mode = GameMode.normal;
  int? _seed; // daily 局的 seed
  Random? _dailyRng; // daily 局用 seeded RNG（同 seed → 同開局）
  int _gameMaxTile = 0; // 本局最大方塊（里程碑偵測用）
  int _celebrateTile = 0; // 正在慶祝的方塊值（0 = 無）
  int _celebrateKey = 0; // 慶祝動畫重開的 key
  bool _awaitingPlayer = false; // 首次啟動：等輸入玩家名字
  final GlobalKey _boardBoundaryKey = GlobalKey(); // board 截圖用
  static const _milestones = [1024, 2048, 4096];

  @override
  void initState() {
    super.initState();
    storage = GameStorage(widget.prefs);
    if (storage.loadPlayers().isEmpty) {
      _awaitingPlayer = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askPlayerName();
      });
    } else {
      _loadForCurrentPlayer();
    }
  }

  /// 載入目前玩家的資料（統計 + 普通局自動存檔）。
  void _loadForCurrentPlayer() {
    stats = storage.loadStats();
    final saved = storage.loadSavedGame(GameMode.normal);
    if (saved != null) {
      _restoreSaved(saved, GameMode.normal); // 接續上次：靜止渲染，不播動畫
    } else {
      size = widget.settings.boardSize;
      _initializeGame();
    }
  }

  /// 首次啟動：輸入玩家名字。
  Future<void> _askPlayerName() async {
    final name = await showPlayerNameDialog(context);
    if (name == null || !mounted) return;
    await storage.addPlayer(name);
    setState(() {
      _awaitingPlayer = false;
      _loadForCurrentPlayer();
    });
  }

  /// AppBar 玩家名 tap → 切換／新增玩家。
  Future<void> _switchPlayer() async {
    final chosen = await showPlayerPicker(
      context,
      players: storage.loadPlayers(),
      current: storage.currentPlayer,
      onAdd: storage.addPlayer,
    );
    if (chosen == null || !mounted || chosen == storage.currentPlayer) return;
    await storage.setCurrentPlayer(chosen);
    setState(_loadForCurrentPlayer);
  }

  void _initializeGame({GameMode mode = GameMode.normal, int? seed}) {
    this.mode = mode;
    _seed = seed;
    _dailyRng = (mode == GameMode.daily && seed != null) ? Random(seed) : null;
    tiles.clear();
    history.clear();
    redoStack.clear();
    score = 0;
    moves = 0;
    undoCount = 0;
    best = storage.bestScore(size);
    won = false;
    keepPlaying = false;
    gameOver = false;
    _gain = 0;
    _gameMaxTile = 0;
    _addRandomTile();
    _addRandomTile();
    stats.gamesPlayed++;
    _persist();
    _resetTileFlagsAfterFrame(); // 初始方塊也要走 spawn 動畫（isNew 首幀 0.01 → 1.0）
  }

  /// 從自動存檔接續：同一批 id、沒有 isNew/justMerged → 不播動畫。
  void _restoreSaved(SavedGame saved, GameMode mode) {
    size = saved.boardSize;
    this.mode = mode;
    _seed = saved.seed;
    _dailyRng = (mode == GameMode.daily && saved.seed != null) ? Random(saved.seed) : null;
    tiles
      ..clear()
      ..addAll([for (final t in saved.tiles) Tile(id: t.id, value: t.value, row: t.row, col: t.col)]);
    score = saved.score;
    moves = saved.moves;
    undoCount = saved.undoCount;
    best = storage.bestScore(size);
    won = tiles.any((t) => t.value >= 2048);
    keepPlaying = saved.keepPlaying;
    gameOver = !_canMove();
    _gameMaxTile = tiles.fold(0, (m, t) => t.value > m ? t.value : m);
    _syncNextId();
  }

  /// 還原 board 後同步 _nextId，避免新方塊 id 撞已存在的 tile（ValueKey 重複）。
  void _syncNextId() => _nextId = tiles.fold(1, (m, t) => t.id > m ? t.id : m) + 1;

  void _addRandomTile() {
    final rng = _dailyRng ?? random;
    final occupied = <int>{for (final t in tiles) if (!t.removed) t.row * size + t.col};
    final empty = <int>[for (var i = 0; i < size * size; i++) if (!occupied.contains(i)) i];
    if (empty.isEmpty) return;
    final p = empty[rng.nextInt(empty.length)];
    tiles.add(Tile(
      id: _nextId++,
      value: rng.nextDouble() < 0.9 ? 2 : 4,
      row: p ~/ size,
      col: p % size,
      isNew: true,
    ));
  }

  bool _canMove() {
    final b = List.generate(size, (_) => List.filled(size, 0));
    for (final t in tiles) {
      if (!t.removed) b[t.row][t.col] = t.value;
    }
    for (var i = 0; i < size; i++) {
      for (var j = 0; j < size; j++) {
        if (b[i][j] == 0) return true;
        if (j + 1 < size && b[i][j] == b[i][j + 1]) return true;
        if (i + 1 < size && b[i][j] == b[i + 1][j]) return true;
      }
    }
    return false;
  }

  bool _move(Direction direction) {
    tiles.removeWhere((t) => t.removed); // 清掉上一回合的合併殘骸
    final before = <int, (int, int, int)>{
      for (final t in tiles) t.id: (t.row, t.col, t.value),
    };
    history.add(_takeSnapshot());

    final scoreBefore = score;
    var merges = 0;
    final at = <int, Tile>{for (final t in tiles) t.row * size + t.col: t};
    // right/down 從目標邊收線：tile 順序才和 _applyLine 的打包方向一致（否則方塊互相穿越）。
    final fromEdge = direction == Direction.right || direction == Direction.down;
    for (var i = 0; i < size; i++) {
      final line = <Tile>[];
      for (var j = 0; j < size; j++) {
        final k = fromEdge ? size - 1 - j : j;
        final r = (direction == Direction.up || direction == Direction.down) ? k : i;
        final c = (direction == Direction.up || direction == Direction.down) ? i : k;
        final t = at[r * size + c];
        if (t != null) line.add(t);
      }
      merges += _applyLine(line, i, direction);
    }

    var moved = false;
    for (final t in tiles) {
      if (t.removed) continue;
      final b = before[t.id]!;
      if (b.$1 != t.row || b.$2 != t.col || b.$3 != t.value) moved = true;
    }
    if (!moved) {
      history.removeLast();
      return false;
    }

    redoStack.clear(); // 新移動作廢 redo stack
    moves++;
    _addRandomTile();
    if (!_canMove()) gameOver = true;
    _afterMove(merges, score - scoreBefore);
    _resetTileFlagsAfterFrame();
    return true;
  }

  /// 移動後記帳：震動／統計／過關偵測／最高分／自動存檔。
  void _afterMove(int merges, int gain) {
    if (merges > 0) {
      stats.totalMerges += merges;
      if (widget.settings.haptics) HapticFeedback.mediumImpact();
    }
    if (gain > 0) {
      _gain = gain;
      _gainKey++;
    }
    var maxTile = 0;
    for (final t in tiles) {
      if (!t.removed && t.value > maxTile) maxTile = t.value;
    }
    if (maxTile > _gameMaxTile) {
      _gameMaxTile = maxTile;
      if (_milestones.contains(maxTile)) {
        _celebrateTile = maxTile;
        _celebrateKey++;
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _celebrateTile = 0);
        });
      }
    }
    if (maxTile > stats.maxTile) stats.maxTile = maxTile;
    if (!won && maxTile >= 2048) {
      won = true;
      keepPlaying = false; // 新過關 → 顯示 overlay（載入快照時 keepPlaying=true 不重播）
      stats.wins++;
    }
    if (mode == GameMode.daily && score > stats.dailyBest) stats.dailyBest = score;
    if (mode == GameMode.normal && score > best) {
      best = score;
      storage.setBestScore(size, best);
    }
    _persist();
  }

  /// 一條線（[line] 已依移動方向排好序）：滑動 + 每對只合併一次（2,2,4 走左 = 4,4，不是 8,0）。
  /// 回傳這條線的合併次數。
  int _applyLine(List<Tile> line, int index, Direction direction) {
    var slot = 0;
    var i = 0;
    var merges = 0;
    while (i < line.length) {
      final t = line[i];
      if (i + 1 < line.length && line[i + 1].value == t.value) {
        final other = line[i + 1];
        final (r, c) = _target(index, slot, direction);
        t.row = r;
        t.col = c;
        t.value *= 2;
        score += t.value;
        t.justMerged = true;
        other.row = r;
        other.col = c;
        other.removed = true; // 滑到同一格、被合併方塊蓋住，下次狀態變更時清掉
        i += 2;
        merges++;
      } else {
        final (r, c) = _target(index, slot, direction);
        t.row = r;
        t.col = c;
        i += 1;
      }
      slot++;
    }
    return merges;
  }

  (int, int) _target(int index, int slot, Direction direction) {
    switch (direction) {
      case Direction.left:
        return (index, slot);
      case Direction.right:
        return (index, size - 1 - slot);
      case Direction.up:
        return (slot, index);
      case Direction.down:
        return (size - 1 - slot, index);
    }
  }

  _Snapshot _takeSnapshot() => _Snapshot(
        _tileData(),
        score,
        moves,
        won,
        keepPlaying,
        stats.totalMerges,
        stats.wins,
      );

  void _restoreSnapshot(_Snapshot snapshot) {
    tiles
      ..clear()
      ..addAll([for (final t in snapshot.tiles) Tile(id: t.id, value: t.value, row: t.row, col: t.col)]);
    score = snapshot.score;
    moves = snapshot.moves;
    won = snapshot.won;
    keepPlaying = snapshot.keepPlaying;
    stats.totalMerges = snapshot.totalMerges;
    stats.wins = snapshot.wins;
    _gain = 0; // undo/redo 清掉上一手的 +N 浮字
    gameOver = false;
  }

  /// 復原：同步還原狀態，不排動畫 queue —— 連按 N 下就是彈 N 個 snapshot，
  /// 動畫只是追著最新狀態跑（AnimatedPositioned 自動 re-target），不會堆積。
  void _undo() {
    if (history.isEmpty) return;
    final snapshot = history.removeLast();
    redoStack.add(_takeSnapshot());
    _restoreSnapshot(snapshot);
    undoCount++;
    _persist();
  }

  void _redo() {
    if (redoStack.isEmpty) return;
    final snapshot = redoStack.removeLast();
    history.add(_takeSnapshot());
    _restoreSnapshot(snapshot);
    if (undoCount > 0) undoCount--; // redo 回滾淨 undo 數
    _persist();
  }

  /// 自動存檔 + 統計：串接寫入（依序落盤，避免並發覆蓋）；每次狀態變更後呼叫。
  Future<void> _pending = Future.value();

  void _persist() {
    final game = SavedGame(
      boardSize: size,
      tiles: _tileData(),
      score: score,
      moves: moves,
      undoCount: undoCount,
      keepPlaying: keepPlaying,
      seed: _seed,
    );
    final mode = this.mode;
    _pending = _pending.then((_) async {
      await storage.saveGame(game, mode);
      await storage.saveStats(stats);
    });
  }

  /// 目前 board 的 TileData（不含已移除的合併殘骸）。
  List<TileData> _tileData() =>
      [for (final t in tiles) if (!t.removed) (id: t.id, value: t.value, row: t.row, col: t.col)];

  /// Daily／普通局切換：切走前先把目前局存盤，再載入另一格。
  void _toggleDaily() {
    _persist(); // 存目前局（切走前）
    if (mode == GameMode.daily) {
      _restoreNormal();
      return;
    }
    final seed = dailySeedFor(DateTime.now());
    final saved = storage.loadSavedGame(GameMode.daily);
    if (saved != null && saved.seed == seed) {
      setState(() => _restoreSaved(saved, GameMode.daily));
      return;
    }
    if (stats.lastDailyDate != seed) {
      stats.lastDailyDate = seed;
      stats.dailyBest = 0; // 新的一天 → 重算今日最高
    }
    setState(() => _initializeGame(mode: GameMode.daily, seed: seed));
  }

  /// 回到普通局：有存檔就接續，沒有就開新局。
  void _restoreNormal() {
    final saved = storage.loadSavedGame(GameMode.normal);
    if (saved != null) {
      setState(() => _restoreSaved(saved, GameMode.normal));
    } else {
      setState(() => _initializeGame());
    }
  }

  /// 家庭每日排行榜。
  Future<void> _showDailyLeaderboard() async {
    final rows = [
      for (final p in storage.loadPlayers()) (p, storage.loadStatsFor(p)),
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          DailyLeaderboardDialog(rows: rows, todaySeed: dailySeedFor(DateTime.now())),
    );
  }

  /// 本地排行榜（每格數 top N，跨玩家）。
  Future<void> _showLeaderboard() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => LeaderboardDialog(
        players: storage.loadPlayers(),
        bestScoreFor: storage.bestScoreFor,
        initialSize: size,
      ),
    );
  }

  /// 分享：文字或 board 截圖。
  Future<void> _showShareDialog() async {
    final l = AppLocalizations.of(context)!;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.share),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'text'),
              child: Text(l.shareText),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'image'),
              child: Text(l.shareScreenshot),
            ),
          ],
        ),
      ),
    );
    if (choice == 'text') {
      await _shareText();
    } else if (choice == 'image') {
      await _shareScreenshot();
    }
  }

  Future<void> _shareText() async {
    final l = AppLocalizations.of(context)!;
    final maxTile = tiles.where((t) => !t.removed).fold(0, (m, t) => t.value > m ? t.value : m);
    await SharePlus.instance.share(ShareParams(
      text:
          'd2048 — ${storage.currentPlayer}\n'
          '${l.score}: $score\n'
          '${l.best}: $best\n'
          '${l.moves}: $moves\n'
          '${l.maxTile}: $maxTile',
    ));
  }

  Future<void> _shareScreenshot() async {
    if (kIsWeb) return; // dart:io File 在 web 不可用
    final boundary = _boardBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final file = File('${Directory.systemTemp.path}/d2048_share.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  /// 存快照：命名對話框 → 加入 list（上限 [PrefsDefaults.snapshotLimit]）。
  Future<void> _saveSnapshot() async {
    final l = AppLocalizations.of(context)!;
    final snapshots = storage.loadSnapshots();
    if (snapshots.length >= PrefsDefaults.snapshotLimit) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.snapshotLimit(PrefsDefaults.snapshotLimit))));
      return;
    }
    final now = DateTime.now();
    final defaultName =
        '${now.month}-${now.day} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final name = await showSaveSnapshotDialog(context, defaultName);
    if (name == null || !mounted) return;
    snapshots.add(BoardSnapshot(
      name: name,
      boardSize: size,
      tiles: _tileData(),
      score: score,
      savedAt: now,
    ));
    await storage.saveSnapshots(snapshots);
  }

  /// 快照 list：tap 載入、🗑 刪除。
  Future<void> _showSnapshots() async {
    final snapshots = storage.loadSnapshots();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SnapshotListDialog(
        snapshots: snapshots,
        onLoad: (s) {
          Navigator.pop(dialogContext);
          _loadSnapshot(s);
        },
        onDelete: (remaining) {
          storage.saveSnapshots(remaining);
        },
      ),
    );
  }

  /// 載入快照：board 原樣恢復、靜止渲染；history/redo 清空，不重播過關 overlay。
  void _loadSnapshot(BoardSnapshot s) {
    setState(() {
      size = s.boardSize;
      mode = GameMode.normal;
      _seed = null;
      _dailyRng = null;
      tiles
        ..clear()
        ..addAll([for (final t in s.tiles) Tile(id: t.id, value: t.value, row: t.row, col: t.col)]);
      score = s.score;
      moves = 0;
      undoCount = 0;
      history.clear();
      redoStack.clear();
      won = tiles.any((t) => t.value >= 2048);
      keepPlaying = true;
      gameOver = !_canMove();
      best = storage.bestScore(size);
      _gain = 0;
      _gameMaxTile = tiles.fold(0, (m, t) => t.value > m ? t.value : m);
      _persist();
      _syncNextId();
    });
  }

  /// 新方塊 spawn（scale 0→1）與合併 pop（1→1.15→1）：首幀畫完後再切 flag，
  /// AnimatedScale 才有「從舊值到新值」可動畫。
  void _resetTileFlagsAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        for (final t in tiles) {
          t.isNew = false;
          t.justMerged = false;
        }
      });
    });
  }

  /// One handler for both axes: the pan recognizer fires BOTH drag-end
  /// callbacks when a gesture has speed on both axes, so pick the dominant
  /// axis here and let a drag with no speed at all do nothing.
  void _swipe(Velocity velocity) {
    if (gameOver || (won && !keepPlaying)) return;
    final dx = velocity.pixelsPerSecond.dx;
    final dy = velocity.pixelsPerSecond.dy;
    if (dx == 0 && dy == 0) return;
    setState(() => _move(dx.abs() >= dy.abs()
        ? (dx < 0 ? Direction.left : Direction.right)
        : (dy < 0 ? Direction.up : Direction.down)));
  }

  Future<void> _newGame() async {
    final l = AppLocalizations.of(context)!;
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.selectBoardSize),
        content: RadioGroup<int>(
          groupValue: null,
          onChanged: (v) => Navigator.pop(dialogContext, v),
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in PrefsDefaults.boardSizeOptions)
                  RadioListTile<int>(
                    value: s,
                    dense: true,
                    title: Text('$s×$s'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen == null) return;
    if (!mounted) return;
    if (chosen != size) {
      await widget.settings.setBoardSize(chosen);
      size = chosen;
    }
    if (!mounted) return;
    setState(_initializeGame);
  }

  Widget _tile(Tile t, double cell, double gap) {
    return AnimatedPositioned(
      // key 綁 tile id：合併時方塊在 Stack 的 children 裡換位置（live→removed 區），
      // 沒有 key 會按 index 配對到錯的 element，滑動動畫從錯的位置起跳。
      key: ValueKey(t.id),
      duration: _animDuration,
      curve: Curves.easeOut,
      left: gap + t.col * (cell + gap),
      top: gap + t.row * (cell + gap),
      width: cell,
      height: cell,
      child: AnimatedScale(
        duration: _animDuration,
        curve: Curves.easeOut,
        scale: t.isNew ? 0.01 : (t.justMerged ? 1.15 : 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: tileColor(t.value),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Center(
            child: Text(
              t.value.toString(),
              style: TextStyle(
                color: tileTextColor(t.value),
                fontSize: cell * (t.value >= 1024 ? 0.22 : t.value >= 128 ? 0.28 : 0.36),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final gap = 8.0;
        final cell = (side - gap * (size + 1)) / size;
        return Container(
          margin: const EdgeInsets.all(8.0),
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.grey[400],
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Stack(
            children: [
              // 背景格
              for (var i = 0; i < size * size; i++)
                Positioned(
                  left: gap + (i % size) * (cell + gap),
                  top: gap + (i ~/ size) * (cell + gap),
                  width: cell,
                  height: cell,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                ),
              // 方塊：先畫已消失的（被合併方塊蓋住），再畫活方塊
              for (final t in tiles.where((t) => t.removed)) _tile(t, cell, gap),
              for (final t in tiles.where((t) => !t.removed)) _tile(t, cell, gap),
            ],
          ),
        );
      },
    );
  }

  /// +N 浮字：每次有得分的移動重開一次（key 變 → TweenAnimationBuilder 重跑）。
  Widget _gainPopup() {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_gainKey),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -24 * t),
        child: Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: child),
      ),
      child: Text(
        '+$_gain',
        style: TextStyle(
          color: Colors.green[700],
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_awaitingPlayer) {
      return Scaffold(
        appBar: AppBar(title: const Text('2048')),
        body: Center(
          child: ElevatedButton(
            onPressed: _askPlayerName,
            child: Text(l.whoIsPlaying),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('2048'),
            const SizedBox(width: 8),
            // 目前玩家：tap 切換／新增
            InkWell(
              onTap: _switchPlayer,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: 4),
                  Text(storage.currentPlayer),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: l.dailyLeaderboard,
            onPressed: _showDailyLeaderboard,
          ),
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: l.leaderboard,
            onPressed: _showLeaderboard,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l.share,
            onPressed: _showShareDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(settings: widget.settings, stats: storage.loadStats()),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            // Score / best / moves / undo count + snapshot buttons
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${l.score}: $score',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              Text('${l.best}: $best', style: TextStyle(color: Colors.grey[700])),
                              Text(
                                '${l.moves}: $moves  ${l.undoCount(undoCount)}',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ],
                          ),
                          if (_gain > 0)
                            Positioned(right: 0, top: 0, child: _gainPopup()),
                        ],
                      ),
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.bookmark_add_outlined),
                            tooltip: l.saveSnapshot,
                            onPressed: _saveSnapshot,
                          ),
                          IconButton(
                            icon: const Icon(Icons.folder_outlined),
                            tooltip: l.loadSnapshot,
                            onPressed: _showSnapshots,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: history.isEmpty ? null : () => setState(_undo),
                        child: Text(l.undo),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: redoStack.isEmpty ? null : () => setState(_redo),
                        child: Text(l.redo),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _newGame(),
                        child: Text(l.newGame),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _toggleDaily,
                        child: Text(mode == GameMode.daily ? l.normal : l.daily),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Game board
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: GestureDetector(
                    onVerticalDragEnd: (details) => _swipe(details.velocity),
                    onHorizontalDragEnd: (details) => _swipe(details.velocity),
                    child: RepaintBoundary(key: _boardBoundaryKey, child: _buildBoard()),
                  ),
                ),
              ),
            ),

            // Win overlay（過關但選擇繼續前）
            if (won && !keepPlaying)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                color: Colors.black54,
                child: Column(
                  children: [
                    Text(
                      l.youWin,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {
                        keepPlaying = true;
                        _persist();
                      }),
                      child: Text(l.keepPlaying),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _newGame,
                      child: Text(l.newGame),
                    ),
                  ],
                ),
              )
            // Game over overlay
            else if (gameOver)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                color: Colors.black54,
                child: Column(
                  children: [
                    Text(
                      l.gameOver,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(_initializeGame),
                      child: Text(l.playAgain),
                    ),
                  ],
                ),
              ),

            // Swipe instructions
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l.swipeHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
          ],
        ),
          ),
        // 里程碑慶祝（1024/2048/4096）：全屏動畫，1.6 秒後自動消失
        if (_celebrateTile > 0)
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_celebrateKey),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1500),
              builder: (context, t, child) {
                final scale = t < 0.2 ? 0.5 + t / 0.2 * 0.5 : 1.0;
                final opacity = t > 0.7 ? (1 - t) / 0.3 : 1.0;
                return Center(
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(scale: scale, child: child),
                  ),
                );
              },
              child: Text(
                '$_celebrateTile!',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum Direction { up, down, left, right }

/// 一個方塊：id 穩定（undo 還原同一批 id，動畫才能滑回去），
/// [isNew]/[justMerged] 只影響 scale 動畫，[removed] 的方塊滑到合併格後消失。
class Tile {
  final int id;
  int value;
  int row;
  int col;
  bool isNew;
  bool justMerged;
  bool removed;

  Tile({
    required this.id,
    required this.value,
    required this.row,
    required this.col,
    this.isNew = false,
    this.justMerged = false,
    this.removed = false,
  });
}

class _Snapshot {
  final List<({int id, int value, int row, int col})> tiles;
  final int score;
  final int moves;
  final bool won;
  final bool keepPlaying;
  final int totalMerges;
  final int wins;

  _Snapshot(this.tiles, this.score, this.moves, this.won, this.keepPlaying, this.totalMerges, this.wins);
}