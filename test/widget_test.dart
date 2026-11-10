import 'dart:convert';
import 'dart:math';

import 'package:d2048/game_storage.dart';
import 'package:d2048/main.dart';
import 'package:d2048/settings_keys.dart';
import 'package:d2048/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsModel> loadSettings() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return SettingsModel.load(prefs);
  }

  /// 預存一份確定性存檔（app 啟動時接續），讓 board 不依賴隨機。
  Future<void> seedBoard(SharedPreferences prefs, List<({int id, int value, int row, int col})> tiles) async {
    await GameStorage(prefs).saveGame(SavedGame(
      boardSize: 4,
      tiles: tiles,
      score: 0,
      moves: 0,
      undoCount: 0,
      keepPlaying: false,
    ));
  }

  /// 目前 board 上的方塊（tile id → (value, row, col)）。
  /// 從 AnimatedPositioned 的 left/top 反推 row/col（gap=8，cell 由 Stack 寬度決定）。
  Map<int, (int, int, int)> readBoard(WidgetTester tester, int size) {
    final stackFinder = find.descendant(
      of: find.byType(AspectRatio),
      matching: find.byType(Stack),
    );
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

    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();
    await swipe(tester, -200, 0);
    await tester.pumpAndSettle();
    final board = readBoard(tester, 4);
    expect(board.length, 3);

    // 重新開 app（同一份 prefs）→ 接續上次。
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs));
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4), equals(board));
  });

  testWidgets('snapshot save, load and delete', (tester) async {
    final settings = await loadSettings();
    final prefs = await SharedPreferences.getInstance();
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
    final good = BoardSnapshot(
      name: 'good',
      boardSize: 4,
      tiles: [(id: 1, value: 2, row: 0, col: 0)],
      score: 10,
      savedAt: DateTime(2026, 11, 10),
    );
    // 一份好 + 一份缺 tiles 的損毀 entry。
    await prefs.setString(Prefs.snapshots, jsonEncode([good.toJson(), {'name': 'bad', 'boardSize': 4}]));
    final list = GameStorage(prefs).loadSnapshots();
    expect(list.length, 1);
    expect(list.single.name, 'good');
  });
}