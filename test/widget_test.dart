import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:d2048/game_storage.dart';
import 'package:d2048/main.dart';
import 'package:d2048/settings_keys.dart';
import 'package:d2048/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 寫入一律丟 exception 的 store（讀取照常）→ 模擬空間不足／落盤失敗。
/// 注意失敗发生在 `SharedPreferences` 已經改完記憶體快取**之後**，所以遊戲照玩。
class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore(super.data) : super.withData();

  int writeCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writeCalls++;
    throw PlatformException(code: 'no-space', message: 'disk full');
  }
}

/// 只在**第一次**寫入丟例外的 store（記憶體快照照改 —— 真實失敗發生在落盤那一步）。
/// 用它的測試要自己讓 `_write` 的 catch 裡丟一次例外，才能把例外送進 `_persist` 那條鏈。
class _ThrowOnceStore extends InMemorySharedPreferencesStore {
  _ThrowOnceStore(super.data) : super.withData();

  int writeCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (writeCalls++ == 0) {
      await super.setValue(valueType, key, value);
      throw PlatformException(code: 'no-space', message: 'disk full');
    }
    return super.setValue(valueType, key, value);
  }
}

/// 平台「不抛例外、直接回 false」的 store：真實 SharedPreferences 的 setString 可能這樣回報失敗。
class _FalseStore extends InMemorySharedPreferencesStore {
  _FalseStore(super.data) : super.withData();

  int writeCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writeCalls++;
    await super.setValue(valueType, key, value); // 記憶體快取照改（跟真 plugin 一樣）
    return false;
  }
}

/// 寫入全部卡在 [gate] 的 store：把「寫入還在飛、玩家已經換了」這個視窗固定住。
class _GatedStore extends InMemorySharedPreferencesStore {
  _GatedStore(super.data) : super.withData();

  final Completer<void> gate = Completer<void>();
  int writeCalls = 0;

  void release() => gate.complete();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writeCalls++;
    await gate.future;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsModel> loadSettings() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return SettingsModel.load(prefs);
  }

  /// 建立一個玩家（per-player 後，app 啟動前必須有玩家）。
  Future<void> seedPlayer(SharedPreferences prefs, [String name = 'Player']) async {
    await GameStorage(prefs).addPlayer(name);
  }

  /// 預存一份確定性存檔（app 啟動時接續），讓 board 不依賴隨機。
  Future<void> seedBoard(SharedPreferences prefs, List<({int id, int value, int row, int col})> tiles) async {
    final storage = GameStorage(prefs);
    await storage.saveGame(SavedGame(
      boardSize: 4,
      tiles: tiles,
      score: 0,
      moves: 0,
      undoCount: 0,
      keepPlaying: false,
    ), GameMode.normal, storage.currentPlayer);
  }

  /// 目前 board 上的方塊（tile id → (value, row, col)）。
  /// 從 AnimatedPositioned 的 left/top 反推 row/col（gap=8，cell 由 Stack 寬度決定）。
  Map<int, (int, int, int)> readBoard(WidgetTester tester, int size) {
    // 棋盤外面還有一層放遮罩的 Stack → 取最內層（尺寸才是 side，cell 算式才對得上）。
    final stackFinder =
        find.descendant(of: find.byType(AspectRatio), matching: find.byType(Stack)).last;
    const gap = 8.0;
    final cell = (tester.getSize(stackFinder).width - gap * (size + 1)) / size;
    final result = <int, (int, int, int)>{};
    for (final ap in tester.widgetList<AnimatedPositioned>(
      find.descendant(of: stackFinder, matching: find.byType(AnimatedPositioned)),
    )) {
      final col = ((ap.left! - gap) / (cell + gap)).round();
      final row = ((ap.top! - gap) / (cell + gap)).round();
      final text = tester.widget<Text>(
        find.descendant(of: find.byWidget(ap), matching: find.byType(Text)),
      );
      result[(ap.key as ValueKey<int>).value] = (int.parse(text.data!), row, col);
    }
    return result;
  }

    // tester 預設把每個 event 蓋 t=0 → velocity 恆為 0；
  // 用顯式 timeStamp 的 moveTo 才估得出 fling 速度。
  Future<void> swipe(WidgetTester tester, double dx, double dy) async {
    final center = tester.getCenter(find.byType(AspectRatio));
    final gesture = await tester.startGesture(center);
    for (var i = 1; i <= 5; i++) {
      await gesture.moveTo(
        center + Offset(dx, dy) * (i / 5),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 96));
    await tester.pumpAndSettle();
  }

  testWidgets('moves add tiles and undo restores the board', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    final before = readBoard(tester, 4);
    expect(before.length, 2);

    await swipe(tester, -200, 0); // left
    final after = readBoard(tester, 4);
    expect(after.length, 3); // 2 個原方塊 + 1 個新方塊

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4), equals(before));
  });

  testWidgets('rapid undo taps do not queue', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    await swipe(tester, -200, 0); // left（成功）
    await swipe(tester, 0, -200); // up（成功：col 0 的兩個 2 合併）
    await tester.pumpAndSettle();

    // 連按 5 下 undo（history 只有 2 個）：多按的落空，不 queue。
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Undo'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(readBoard(tester, 4).length, 2); // 回到初始
    expect(find.textContaining('Undo ×2'), findsOneWidget);
  });

  testWidgets('left move follows the merge rule (one merge per pair)', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await seedBoard(prefs, [
      (id: 1, value: 2, row: 0, col: 0),
      (id: 2, value: 2, row: 0, col: 1),
      (id: 3, value: 4, row: 0, col: 2),
    ]);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    // 2,2,4 走左 → 4,4（每對只合併一次，不是 8,0）
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    final board = readBoard(tester, 4);
    expect(board[1], (4, 0, 0)); // 2+2 合併
    expect(board[3], (4, 0, 1));
    expect(board[2], (2, 0, 0)); // 被合併殘骸（蓋住，下一手才清）
    expect(board.length, 4); // +1 新方塊（id 4，不撞已存在的 1..3）
    expect(board[4]?.$1, anyOf(2, 4));
  });

  testWidgets('right move follows the merge rule', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await seedBoard(prefs, [
      (id: 1, value: 2, row: 0, col: 0),
      (id: 2, value: 4, row: 0, col: 1),
      (id: 3, value: 4, row: 0, col: 2),
    ]);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    // 2,4,4 走右 → 2,8（兩個 4 在右邊合併，2 停在旁邊；方塊不能互相穿越）
    await swipe(tester, 200, 0);
    await tester.pumpAndSettle();
    final board = readBoard(tester, 4);
    expect(board[3], (8, 0, 3));
    expect(board[1], (2, 0, 2));
    expect(board[2], (4, 0, 3)); // 殘骸
    expect(board.length, 4);
    expect(board[4]?.$1, anyOf(2, 4));
  });

  testWidgets('down move follows the merge rule', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await seedBoard(prefs, [
      (id: 1, value: 2, row: 0, col: 0),
      (id: 2, value: 4, row: 1, col: 0),
      (id: 3, value: 4, row: 2, col: 0),
    ]);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    // 2,4,4 走下 → 2,8（兩個 4 在底邊合併）
    await swipe(tester, 0, 200);
    await tester.pumpAndSettle();
    final board = readBoard(tester, 4);
    expect(board[3], (8, 3, 0));
    expect(board[1], (2, 2, 0));
    expect(board[2], (4, 3, 0)); // 殘骸
    expect(board.length, 4);
    expect(board[4]?.$1, anyOf(2, 4));
  });

  testWidgets('new game dialog picks board size', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5×5'));
    await tester.pumpAndSettle();

    expect(settings.boardSize, 5);
    expect(readBoard(tester, 5).length, 2);
  });

  testWidgets('game auto-resumes from saved state', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);

    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    final board = readBoard(tester, 4);
    expect(board.length, 3);

    // 重新開 app（先 pump 空 widget 銷毀 State，模擬真重啟）→ 接續上次。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4), equals(board));
  });

  testWidgets('snapshot save, load and delete', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    final board = readBoard(tester, 4);

    // 存快照
    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // list 裡有它
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    expect(find.text('test'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop(); // 關掉 list
    await tester.pumpAndSettle();

    // 先滑一下（board 改變），再載入快照 → 恢復
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4).length, 3);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('test'));
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4), equals(board));

    // 刪除
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('test'), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('reaching 2048 shows win overlay and keep playing', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    // 預存一個快照：兩個 1024 相鄰 → 滑一下就 2048。
    await GameStorage(prefs).saveSnapshots([
      BoardSnapshot(
        name: 'win',
        boardSize: 4,
        tiles: [
          (id: 1, value: 1024, row: 0, col: 0),
          (id: 2, value: 1024, row: 0, col: 1),
        ],
        score: 100,
        savedAt: DateTime(2026, 11, 10),
      ),
    ]);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    // 載入快照
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('win'));
    await tester.pumpAndSettle();

    // 滑左 → 2048 → 過關 overlay
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    expect(find.text('You win!'), findsOneWidget);

    // 繼續玩 → overlay 消失
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(find.text('You win!'), findsNothing);

    // undo 過關那手 → overlay 消失、board 回到兩個 1024、moves 回滾、可以继续滑
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('You win!'), findsNothing);
    final undone = readBoard(tester, 4);
    expect(undone.length, 2);
    expect(undone.values.every((v) => v.$1 == 1024), isTrue);
    expect(find.textContaining('Moves: 0'), findsOneWidget);
    // 再滑一下 → 又 2048 → overlay 回來
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    expect(find.text('You win!'), findsOneWidget);
  });

  testWidgets('redo restores the undone move', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    final afterMove = readBoard(tester, 4);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Undo ×1'), findsOneWidget);
    await tester.tap(find.text('Redo'));
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4), equals(afterMove));
    expect(find.textContaining('Undo ×0'), findsOneWidget); // redo 回滾 undoCount
  });

  test('loadSnapshots skips corrupted entries', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    final good = BoardSnapshot(
      name: 'good',
      boardSize: 4,
      tiles: [(id: 1, value: 2, row: 0, col: 0)],
      score: 10,
      savedAt: DateTime(2026, 11, 10),
    );
    // 一份好 + 一份缺 tiles 的損毀 entry。
    await prefs.setString('${Prefs.snapshots}/Player', jsonEncode([good.toJson(), {'name': 'bad', 'boardSize': 4}]));
    final list = GameStorage(prefs).loadSnapshots();
    expect(list.length, 1);
    expect(list.single.name, 'good');
  });

  test('old global data migrates to the default player', () async {
    SharedPreferences.setMockInitialValues({
      Prefs.savedGame: jsonEncode(SavedGame(
        boardSize: 4,
        tiles: [(id: 1, value: 2, row: 0, col: 0)],
        score: 5,
        moves: 1,
        undoCount: 0,
        keepPlaying: false,
      ).toJson()),
      Prefs.stats: jsonEncode(GameStats(gamesPlayed: 3).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = GameStorage(prefs);
    expect(storage.loadPlayers(), ['Player']);
    expect(storage.currentPlayer, 'Player');
    expect(storage.loadSavedGame(GameMode.normal)?.score, 5);
    expect(storage.loadStats().gamesPlayed, 3);
    // 舊 key 已搬走
    expect(prefs.containsKey(Prefs.savedGame), isFalse);
    expect(prefs.containsKey(Prefs.stats), isFalse);
  });

  test('addPlayer normalizes names (trim / 20 字上限 / 大小寫去重)', () async {
    // 這組行為（trim → runes.take(20) 限長 → 大小寫不分去重 → 全空白不建玩家）之先零測試。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = GameStorage(prefs);
    expect(await storage.addPlayer('Amy'), 'Amy');

    // 同名（大小寫不同 + 前後空白）→ 合併成既有的 Amy，不另開一位
    expect(await storage.addPlayer('  amy  '), 'Amy');
    expect(storage.currentPlayer, 'Amy');
    expect(storage.loadPlayers(), ['Amy']);
    expect(prefs.getString(Prefs.currentPlayer), 'Amy');

    // 名字限長（AppBar 標題與排行榜才不會被超長名字撐爆）
    final long = await storage.addPlayer('x' * 30);
    expect(long, 'x' * PrefsDefaults.playerNameLimit);
    expect(storage.loadPlayers(), ['Amy', 'x' * PrefsDefaults.playerNameLimit]);

    // 全空白 → 不建玩家、也不換人（回傳原本的 currentPlayer）
    expect(await storage.addPlayer('   '), 'x' * PrefsDefaults.playerNameLimit);
    expect(storage.currentPlayer, 'x' * PrefsDefaults.playerNameLimit);
    expect(storage.loadPlayers(), ['Amy', 'x' * PrefsDefaults.playerNameLimit]);
  });

  test('empty current_player falls back to the first player', () async {
    // players 還在、current_player 卻不見（被清掉／備份還原到一半）：修之前所有讀寫都落在
    // `saved_game/`（尾巴一個 /）→ Amy 的舊資料永遠讀不到，AppBar 也只剩空白。
    SharedPreferences.setMockInitialValues({
      Prefs.players: jsonEncode(['Amy', 'Bob']),
      '${Prefs.savedGame}/Amy': jsonEncode(SavedGame(
        boardSize: 4,
        tiles: [(id: 1, value: 2, row: 0, col: 0)],
        score: 7,
        moves: 2,
        undoCount: 0,
        keepPlaying: false,
      ).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = GameStorage(prefs);
    expect(storage.currentPlayer, 'Amy');
    expect(storage.loadSavedGame(GameMode.normal)?.score, 7);

    await storage.saveGame(
      SavedGame(
        boardSize: 4,
        tiles: [(id: 1, value: 4, row: 0, col: 0)],
        score: 9,
        moves: 3,
        undoCount: 0,
        keepPlaying: false,
      ),
      GameMode.normal,
      storage.currentPlayer,
    );
    expect(prefs.getString('${Prefs.savedGame}/Amy'), contains('"moves":3'));
    expect(prefs.containsKey('${Prefs.savedGame}/'), isFalse); // 不能另開一個孤兒 key
  });

  test('player data is namespaced per player', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = GameStorage(prefs);
    await storage.addPlayer('A');
    await storage.setBestScore(4, 100);
    await storage.saveStats(GameStats(gamesPlayed: 7), storage.currentPlayer);
    await storage.addPlayer('B');
    expect(storage.currentPlayer, 'B');
    expect(storage.bestScore(4), 0);
    expect(storage.loadStats().gamesPlayed, 0);
    expect(storage.bestScoreFor('A', 4), 100);
    expect(storage.loadStatsFor('A').gamesPlayed, 7);
  });

  test('daily seed is the local date', () {
    expect(dailySeedFor(DateTime(2026, 11, 10)), 20261110);
  });

  testWidgets('daily game resumes the same day', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    final board = readBoard(tester, 4);
    expect(board.length, 2);

    // 重新開 app（先 pump 空 widget 銷毀 State，模擬真重啟）→ 再按 Daily → 接續同一局（不是開新局）
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4), equals(board));
  });

  testWidgets('reaching 1024 shows the milestone celebration', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await seedBoard(prefs, [
      (id: 1, value: 512, row: 0, col: 0),
      (id: 2, value: 512, row: 0, col: 1),
    ]);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    // 512+512 → 1024（不用 swipe helper：它的 pumpAndSettle 會把慶祝 timer 跑完）
    final center = tester.getCenter(find.byType(AspectRatio));
    final gesture = await tester.startGesture(center);
    for (var i = 1; i <= 5; i++) {
      await gesture.moveTo(
        center + const Offset(-200, 0) * (i / 5),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 96));
    await tester.pump();
    expect(find.text('1024!'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('1024!'), findsNothing); // 自動消失
  });

  testWidgets('daily leaderboard lists players by today score', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs, 'A');
    final storage = GameStorage(prefs);
    final today = dailySeedFor(DateTime.now());
    await storage.saveStats(GameStats(dailyBest: 500, lastDailyDate: today), storage.currentPlayer); // A（目前玩家）
    await storage.addPlayer('B'); // current → B
    await storage.saveStats(GameStats(dailyBest: 900, lastDailyDate: today), storage.currentPlayer); // B
    await storage.setCurrentPlayer('A');

    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.emoji_events_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Daily leaderboard'), findsOneWidget);
    // B（900）排第一、A（500）排第二
    final items = tester.widgetList<ListTile>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ListTile))).toList();
    expect(items.length, 2);
    final firstTexts = tester.widgetList<Text>(find.descendant(of: find.byWidget(items.first), matching: find.byType(Text))).map((t) => t.data).toList();
    expect(firstTexts, contains('B'));
    expect(firstTexts, contains('900'));
    final secondTexts = tester.widgetList<Text>(find.descendant(of: find.byWidget(items[1]), matching: find.byType(Text))).map((t) => t.data).toList();
    expect(secondTexts, contains('A'));
    expect(secondTexts, contains('500'));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('leaderboard dialog shows the picked board size', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs, 'A');
    final storage = GameStorage(prefs);
    await storage.setBestScore(4, 100);
    await storage.setBestScore(6, 7);

    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    // 開排行榜（finding 1：以前 layout 會 throw）
    await tester.tap(find.byIcon(Icons.leaderboard));
    await tester.pumpAndSettle();
    expect(find.text('Leaderboard'), findsOneWidget);
    // 預設 4×4 欄：A 100
    expect(find.text('100'), findsOneWidget);

    // 點 6×6 → list 切到 6×6 欄（finding 2：picker 以前不 stick）
    await tester.tap(find.text('6×6'));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('100'), findsNothing);
  });

  testWidgets('board tiles stay inside the board frame', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await seedBoard(prefs, [(id: 1, value: 2, row: 3, col: 3)]);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();

    final frame = tester.getRect(find.byType(AspectRatio));
    final tiles = find.byType(AnimatedPositioned);
    expect(tiles, findsWidgets);
    for (var i = 0; i < tiles.evaluate().length; i++) {
      final rect = tester.getRect(tiles.at(i));
      expect(frame.contains(rect.topLeft), isTrue);
      expect(frame.contains(rect.bottomRight), isTrue);
    }
  });

  /// 兩位玩家、各带一份可辨識的存檔：A = 分數 11（id 1,2）、B = 分數 99（id 7,8）。
  Future<SharedPreferences> seedTwoPlayers() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = GameStorage(prefs);
    await storage.addPlayer('A');
    await storage.saveGame(
        SavedGame(
          boardSize: 4,
          tiles: [(id: 1, value: 2, row: 0, col: 0), (id: 2, value: 4, row: 3, col: 3)],
          score: 11,
          moves: 3,
          undoCount: 0,
          keepPlaying: false,
        ),
        GameMode.normal, storage.currentPlayer);
    await storage.addPlayer('B');
    await storage.saveGame(
        SavedGame(
          boardSize: 4,
          tiles: [(id: 7, value: 8, row: 1, col: 1), (id: 8, value: 16, row: 2, col: 2)],
          score: 99,
          moves: 5,
          undoCount: 0,
          keepPlaying: false,
        ),
        GameMode.normal, storage.currentPlayer);
    await storage.setCurrentPlayer('A');
    return prefs;
  }

  testWidgets('switching player from the list loads that player\u0027s board', (tester) async {
    final prefs = await seedTwoPlayers();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Score: 11'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('A')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Score: 99'), findsOneWidget);
    expect(readBoard(tester, 4).keys, containsAll(<int>[7, 8]));
  });

  testWidgets('typing an existing name in the Add field switches player too', (tester) async {
    // 原本 onAdd 已把 currentPlayer 改掉，_switchPlayer 却拿活值比對而 early-return
    // → 畫面還是 A 的盤，下一手就把 A 的棋盤寫進 B 的存檔（B 的進度消失）。
    final prefs = await seedTwoPlayers();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('A')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'B');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Score: 99'), findsOneWidget);

    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    final bSave = GameStorage(prefs);
    await bSave.setCurrentPlayer('B');
    expect(bSave.loadSavedGame(GameMode.normal)!.tiles.map((t) => t.id), containsAll(<int>[7, 8]));
  });

  testWidgets('a save queued before a player switch stays in the old player namespace', (tester) async {
    // saveGame／saveStats 早期用 currentPlayer 的「活值」：第一筆寫入卡在 gate 裡時，
    // 第二筆的回呼要等到寫入才執行 —— 那時候 addPlayer 早已把 currentPlayer 翻成 B，
    // 於是 A 的盤落盤到 saved_game/B，把 B 的進度盖掉（`await _pending` 保不到它）。
    await seedTwoPlayers();
    final seeded = await SharedPreferencesStorePlatform.instance.getAll();
    final store = _GatedStore(seeded);
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
      SharedPreferences.resetStatic();
    });

    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    await swipe(tester, -200, 0); // seed 是 moves:3 → 兩步後 A 應該到 5
    await swipe(tester, 0, -200); // 兩筆寫入都還卡在 gate 裡
    expect(find.textContaining('Moves: 5'), findsOneWidget);

    // 在飛的寫入還沒落盤就換人（Add 欄敲既有名字 → onAdd → addPlayer 同步翻 currentPlayer）
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('A')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'B');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pump();

    store.release();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final all = await store.getAll();
    final forB = jsonDecode(all['flutter.saved_game/B']! as String) as Map<String, dynamic>;
    final forA = jsonDecode(all['flutter.saved_game/A']! as String) as Map<String, dynamic>;
    // 寫錯人時 B 會被塞進 A 的盤（id 1,2,…）、A 则停在 seed 的 3 步。
    expect([for (final t in forB['tiles'] as List<dynamic>) t['id']], <int>[7, 8]);
    expect(forA['moves'], 5);
  });

  testWidgets('player dialogs do not use a disposed controller', (tester) async {
    // 對白框的 controller 如果在 showDialog resolve 當下就 dispose，退場動畫期間
    // TextField 會用到已釋放的 controller（debug 噴 assertion，畫面直接坏）。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Daddy'); // 首次啟動的「誰在玩」
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(GameStorage(prefs).currentPlayer, 'Daddy');

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Daddy')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mum');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(GameStorage(prefs).currentPlayer, 'Mum');
  });

  testWidgets('a corrupt players list is not treated as "no players"', (tester) async {
    // loadPlayers() 原本 `catch (_) => []` → 「壞掉」看起来像「沒玩家」→ 出「誰在玩」→
    // 下一次 addPlayer 把清單盖成只有一人，Amy 的舊資料全部變孤兒。
    const broken = '{this is not a list';
    SharedPreferences.setMockInitialValues({
      Prefs.players: broken,
      Prefs.currentPlayer: 'Amy',
      '${Prefs.savedGame}/Amy': jsonEncode(SavedGame(
        boardSize: 4,
        tiles: [(id: 1, value: 2, row: 0, col: 0), (id: 2, value: 4, row: 3, col: 3)],
        score: 11,
        moves: 3,
        undoCount: 0,
        keepPlaying: false,
      ).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    // 不進「誰在玩」流程，而是照常接續 Amy 的局，並提示一次
    expect(find.text("Who's playing?"), findsNothing);
    expect(find.textContaining('Score: 11'), findsOneWidget);
    expect(find.textContaining("Couldn't read the player list"), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 壞掉的東西一律留著：滑一下（觸發自動存檔）再多一位玩家，都不能把原字串盖掉
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    await GameStorage(prefs).addPlayer('Mum');
    expect(prefs.getString(Prefs.players), broken);
    expect(prefs.getString('${Prefs.savedGame}/Amy'), isNotNull); // Amy 的存檔還在
  });

  testWidgets('win overlay covers the board without shrinking it', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await GameStorage(prefs).saveSnapshots([
      BoardSnapshot(
        name: 'win',
        boardSize: 4,
        tiles: [(id: 1, value: 1024, row: 0, col: 0), (id: 2, value: 1024, row: 0, col: 1)],
        score: 100,
        savedAt: DateTime(2026, 11, 10),
      ),
    ]);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('win'));
    await tester.pumpAndSettle();

    final boardBefore = tester.getRect(find.byType(AspectRatio));
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    expect(find.text('You win!'), findsOneWidget);

    final boardAfter = tester.getRect(find.byType(AspectRatio));
    expect(boardAfter, boardBefore); // overlay 是蓋在棋盤上面，不是挤成另一列
    final scrim = tester.getRect(
      find.ancestor(of: find.text('You win!'), matching: find.byType(ColoredBox)).first,
    );
    expect(scrim.contains(boardAfter.center), isTrue);

    // 遮罩只蓋棋盤、不蓋整個 body → 遮罩外的 Undo 仍能按（破局後的出路）。
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('You win!'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily game is always 4x4 whatever the last board size was', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8×8'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();

    // 背景格 = size²（方塊用 AnimatedPositioned，不會被這個 predicate 抵到）
    final cells = find.byWidgetPredicate(
      (w) => w is Container && (w.decoration as BoxDecoration?)?.color == Colors.grey[300],
    );
    expect(cells, findsNWidgets(16)); // 沿用 8×8 就會变 64，家庭每日排行就不可比
  });

  testWidgets('Play Again after a daily game over goes back to the normal board size', (tester) async {
    // 遮罩的 Play Again 之前直接 setState(_initializeGame)：mode 預設 normal、size 沿用
    // daily 的 4 → 原本玩 8×8 的人破局後拿到一局普通的 4×4，最高分也改成看 4×4 那欄。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs);
    // 塞一局已破局的 daily（封盤、無相鄰同值）→ 按 Daily 就會直接看到破局遮罩。
    final dead = [
      for (var r = 0; r < 4; r++)
        for (var c = 0; c < 4; c++) (id: r * 4 + c + 1, value: (r + c) % 2 == 0 ? 2 : 4, row: r, col: c),
    ];
    await GameStorage(prefs).saveGame(
      SavedGame(
        boardSize: 4,
        tiles: dead,
        score: 400,
        moves: 30,
        undoCount: 0,
        keepPlaying: false,
        seed: dailySeedFor(DateTime.now()),
      ),
      GameMode.daily,
      'Player',
    );
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8×8'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(find.text('Game Over!'), findsOneWidget);

    await tester.tap(find.text('Play Again'));
    await tester.pumpAndSettle();

    expect(find.text('Game Over!'), findsNothing);
    expect(find.text('Normal'), findsNothing); // 已回到普通局（按鈕才顯示「Daily」）
    final cells = find.byWidgetPredicate(
      (w) => w is Container && (w.decoration as BoxDecoration?)?.color == Colors.grey[300],
    );
    expect(cells, findsNWidgets(64)); // 沿用 daily 的 4×4 就是 16
    expect(readBoard(tester, 8).length, 2);
  });

  testWidgets('player picker stays usable with many players', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = GameStorage(prefs);
    for (var i = 0; i < 15; i++) {
      await storage.addPlayer('P$i');
    }
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('P14')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(ElevatedButton, 'Add'), findsOneWidget); // 「新增」那列還在
  });

  testWidgets('a failing save warns once and the game keeps playing', (tester) async {
    // SharedPreferences 是先改記憶體快取、再非同步落盤 → 落盤失敗時遊戲要能繼續玩，
    // 但必須讓使用者知道「這一局可能不會被存起來」（而且同一場失敗只噴一次）。
    SharedPreferences.setMockInitialValues({});
    final seedPrefs = await SharedPreferences.getInstance();
    await seedPlayer(seedPrefs);
    await seedBoard(seedPrefs, [
      (id: 1, value: 2, row: 0, col: 0),
      (id: 2, value: 4, row: 3, col: 3),
    ]);
    final seeded = await SharedPreferencesStorePlatform.instance.getAll();
    final store = _FailingStore(seeded);
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
      SharedPreferences.resetStatic();
    });

    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    await swipe(tester, 0, -200);
    await tester.pumpAndSettle();

    // 失敗了：寫入-call 有發生，但 store 裡仍是 seed 時那份（0 步）——真的沒落盤。
    expect(store.writeCalls, greaterThan(0));
    final stored = jsonDecode((await store.getAll())['flutter.saved_game/Player']! as String);
    expect(stored['moves'], 0);
    // 但遊戲照玩（失敗發生在改完記憶體快取之後）：UI 已經走到第 2 步、沒崩
    expect(find.textContaining('Moves: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 兩步都失敗 → 只提示一次
    expect(find.textContaining("Couldn't save"), findsOneWidget);
  });

  testWidgets('one throw inside the persist chain does not disable later saves', (tester) async {
    // Dart 的 then 對已失敗的 Future 會跳回呼、原樣把錯傳下去：鏈上拋一次，之後每次
    // _persist() 的回呼永不執行 —— 整個 session 不再自動存檔，而且靜默。
    // 這裡讓第一次寫入失敗、且 _write 的 catch（debugPrint）再丟一次例外，
    // 之後的滑動仍要落盤（修之前：store 永遠停在第一次的 moves）。
    SharedPreferences.setMockInitialValues({});
    final seedPrefs = await SharedPreferences.getInstance();
    await seedPlayer(seedPrefs);
    await seedBoard(seedPrefs, [
      (id: 1, value: 2, row: 0, col: 0),
      (id: 2, value: 4, row: 3, col: 3),
    ]);
    final seeded = await SharedPreferencesStorePlatform.instance.getAll();
    final store = _ThrowOnceStore(seeded);
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
      SharedPreferences.resetStatic();
    });

    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      // 模擬「鏈上冒出一支例外」（今天 _write 吞了它，但 _notifySaveFailure 同在那條鏈上）。
      if (message != null && message.startsWith('d2048 write ')) throw StateError('logger exploded');
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };

    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    await swipe(tester, -200, 0); // 這一下的寫入失敗 + 鏈上拋例外
    await tester.pumpAndSettle();
    await swipe(tester, 0, -200); // 這一下必須照常落盤，不能因為鏈已毒死而被永久跳過
    await tester.pumpAndSettle();
    debugPrint = originalDebugPrint; // binding 會查 foundation vars，要在 test body 內交回

    expect(find.textContaining('Moves: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final stored = jsonDecode((await store.getAll())['flutter.saved_game/Player']! as String);
    expect(stored['moves'], 2); // 毒死時會停在第一次那筆（1）
    expect(store.writeCalls, greaterThan(2));
  });

  testWidgets('a failing snapshot save warns instead of pretending it worked', (tester) async {
    // 1159a01 只做了一半：UI 提示只掛在 _persist。存快照失敗只有 debugPrint →
    // 使用者以為存到了，重開 app 才發現什麼都沒有。
    SharedPreferences.setMockInitialValues({});
    final seedPrefs = await SharedPreferences.getInstance();
    await seedPlayer(seedPrefs);
    await seedBoard(seedPrefs, [
      (id: 1, value: 2, row: 0, col: 0),
      (id: 2, value: 4, row: 3, col: 3),
    ]);
    final seeded = await SharedPreferencesStorePlatform.instance.getAll();
    final store = _FailingStore(seeded);
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
      SharedPreferences.resetStatic();
    });

    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.writeCalls, greaterThan(0)); // 快照那筆真的嘗試落盤（且失敗）
    expect(find.textContaining("Couldn't save"), findsOneWidget); // 修之前：只有 debugPrint，半句提示都沒有
    expect(tester.takeException(), isNull);
  });

  testWidgets('setString returning false counts as a failed save', (tester) async {
    // SharedPreferences.setString 可能不抛、直接回 false（平台回報失敗）→
    // 之前被當成寫入成功，lastError 仍是 null → 使用者永遠不會被告知。
    SharedPreferences.setMockInitialValues({});
    final seedPrefs = await SharedPreferences.getInstance();
    await seedPlayer(seedPrefs);
    await seedBoard(seedPrefs, [
      (id: 1, value: 2, row: 0, col: 0),
      (id: 2, value: 4, row: 3, col: 3),
    ]);
    final seeded = await SharedPreferencesStorePlatform.instance.getAll();
    final store = _FalseStore(seeded);
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
      SharedPreferences.resetStatic();
    });

    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();

    expect(store.writeCalls, greaterThan(0));
    expect(find.textContaining("Couldn't save"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout survives a narrow phone with large system text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await seedPlayer(prefs, 'Christopher Alexander');
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // 按鈕那排與 AppBar 玩家名都不能溢出
  });
}