import 'dart:math';

import 'package:d2048/game_storage.dart';
import 'package:d2048/main.dart';
import 'package:d2048/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsModel> loadSettings() async {
    SharedPreferences.setMockInitialValues({});
    return SettingsModel.load();
  }

  Map<int, int> countValues(Iterable<int> values) {
    final m = <int, int>{};
    for (final v in values) {
      m[v] = (m[v] ?? 0) + 1;
    }
    return m;
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
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(42)));
    await tester.pumpAndSettle();

    final before = readBoard(tester, 4);
    // 參考實作：同一行依左→右排序，相鄰同值合併一次（2,2,4 走左 = 4,4，不是 8,0）。
    final rows = <int, List<int>>{};
    for (final e in before.entries) {
      rows.putIfAbsent(e.value.$2, () => []).add(e.value.$1);
    }
    final expected = <int>[]; // multiset（保留重複值）
    for (final list in rows.values) {
      final sorted = list..sort();
      var i = 0;
      while (i < sorted.length) {
        if (i + 1 < sorted.length && sorted[i] == sorted[i + 1]) {
          expected.add(sorted[i] * 2);
          i += 2;
        } else {
          expected.add(sorted[i]);
          i += 1;
        }
      }
    }
    // 合併後會多一個新方塊（2 或 4）—— 用 multiset 比較（spawn 值可能和 expected 重疊）。
    await swipe(tester, -200, 0);
    final after = readBoard(tester, 4);
    final actualCounts = countValues(after.values.map((v) => v.$1));
    final expectedCounts = countValues(expected);
    final spawnCounts = <int, int>{};
    for (final e in actualCounts.entries) {
      final diff = e.value - (expectedCounts[e.key] ?? 0);
      if (diff > 0) spawnCounts[e.key] = diff;
    }
    expect(spawnCounts.length, 1);
    expect(spawnCounts.keys.single, anyOf(2, 4));
    expect(spawnCounts.values.single, 1);
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
    await tester.tap(find.text('Redo'));
    await tester.pumpAndSettle();
    expect(readBoard(tester, 4), equals(afterMove));
  });
}