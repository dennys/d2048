# d2048 CHANGELOG

已完成事项的归档区（把 TODO.md 瘦成「只剩還沒做的事」）。
**`git log` 才是權威**，這裡只是保留當時的判斷與驗收數字，方便日後回溯「為什麼现在是這樣」。
新的完成紀錄加在最上面。

---
## 2026-11-10 自動存檔、快照、最高分、過關、redo、震動、統計

- **自動存檔／接續**（`lib/game_storage.dart`）：每次狀態變更（移動／undo／redo／載入快照／新遊戲）fire-and-forget 存 `SavedGame`（boardSize/tiles/score/moves/undoCount/keepPlaying，不含 history）；`initState` 有存檔就 `_restoreSaved`（同一批 tile id、無 isNew/justMerged → 靜止渲染不播動畫），沒有才開新遊戲。
- **命名快照**（`lib/widgets/snapshots.dart`）：`BoardSnapshot{name, boardSize, tiles, score, savedAt}`；存快照對話框（預設名 M-D HH:MM）→ list 對話框（`MiniBoard` mini 格預覽 + tap 載入 + 🗑 刪除）。上限 `PrefsDefaults.snapshotLimit=50`，滿了 SnackBar 擋下。載入快照：board 原樣恢復、history/redo 清空、`keepPlaying=true`（不重播過關 overlay）。
- **最高分**：按格數分存（`bestScores` JSON map），header 顯示 `Best: N`。
- **過關偵測**：最大方塊 ≥2048 → `won=true` + overlay（You win! / Keep playing / New Game）；`keepPlaying` 後繼續玩。新過關時 `_afterMove` 把 `keepPlaying` 重置 false（載入快照的 keepPlaying=true 不會被舊值壓掉）。
- **步數**：`moves` 每次成功移動 +1，header 顯示。
- **redo**：`redoStack`；undo 把當前狀態 push 進 redo，新移動清空 redo；Undo/Redo 按鈕各自 disabled。
- **震動**（config，預設關）：`Prefs.haptics` + `SettingsModel.setHaptics` + 設定頁 SwitchListTile；合併時 `HapticFeedback.mediumImpact()`。
- **得分 +N 浮字**：`_gain`/`_gainKey`，`TweenAnimationBuilder`（key 變 → 重跑）600ms 上浮淡出。
- **統計**：`GameStats{gamesPlayed, wins, maxTile, totalMerges}`，設定頁底部顯示。
- **配色抽出**：`lib/tile_style.dart`（`tileColor`/`tileTextColor`），game board 與 MiniBoard 共用。
- l10n 新增 16 字串 ×4 語言（best/moves/redo/youWin/keepPlaying/saveSnapshot/loadSnapshot/snapshotName/noSnapshots/snapshotLimit/save/cancel/haptics/stats/gamesPlayed/wins/maxTile/totalMerges）。
- 坑：`showSaveSnapshotDialog` 若在 `showDialog` 回傳後立刻 `controller.dispose()`，pop 動畫還在用 controller → "TextEditingController was used after being disposed"。修法：對話框改 StatefulWidget，controller 由 State 持有、`dispose()` 時釋放。
- 坑：`SnapshotListDialog` 刪除時 `_items.removeAt(i)` 沒 `setState` → list 不重建。修法：`setState(() => _items.removeAt(i))`。
- 測試：`test/widget_test.dart` 8/8（原 4 個 + 自動接續、快照存/載/刪、過關 overlay、redo）。swipe helper 必須用顯式 `timeStamp:` 的 `moveTo`（tester 預設所有 event 蓋 t=0 → velocity 恆 0）；`readBoard` 從 AnimatedPositioned left/top 反推 row/col（cell 由 Stack 寬度算）。
- 驗收：`flutter analyze` No issues、`flutter test` 8/8。

---
## 2026-11-10 動畫、undo 計數、格數選擇、多國語言（比照 dHealth）

- **移動動畫**（`lib/main.dart`）：board 從 `List<List<int>>` + GridView 改成 tile 物件（`Tile`：穩定 id + row/col）+ `Stack` + `AnimatedPositioned`（150ms easeOut 滑動）+ `AnimatedScale`（新方塊 spawn 0→1、合併 pop 1→1.15→1）。邏輯狀態同步更新、動畫只追狀態，所以移動中再滑動 / undo 都只是 re-target，不會 queue。
  - 坑：`AnimatedPositioned` 沒 key 時按 index 配對 element，合併時方塊在 Stack children 裡從 live 區換到 removed 區會配錯 → 動畫從錯的位置起跳。修法：`key: ValueKey(t.id)`。
  - 坑：初始方塊 `isNew=true` 首幀 scale 0.01，若沒有 post-frame 把 flag 切回就永遠不可見 → `_initializeGame` 也要呼叫 `_resetTileFlagsAfterFrame()`。
- **undo 連按**：`_undo()` 是同步彈 snapshot（不排動畫 queue），連按 N 下 = 彈 N 個；history 空時按鈕 disabled。`test/widget_test.dart` 有連按 5 下（超過 history 深度）的測試。
- **undo 計數**：`undoCount` 每次成功 undo +1、新遊戲歸零，顯示在分數下方（`l.undoCount(n)` → "Undo ×n"）。
- **New Game 選格數**：對話框 RadioGroup 選 4×4–8×8（`PrefsDefaults.boardSizeOptions`），選完存 `settings.boardSize`（SharedPreferences）並開新遊戲；下次進 app 沿用。遊戲邏輯全部 N×N 化（`_applyLine`/`_target`/`_canMove`/`_addRandomTile`）。
- **title**：`MaterialApp.title` 與 AppBar 都改成 "2048"（原 "2048 Game"）。注意：`test/widget_test.dart` 的 `_tileCount` 因此改成只數 board（AspectRatio）內的文字，否則會把標題 "2048" 算成方塊。
- **多國語言 + 設定頁（比照 dHealth）**：`l10n.yaml` + `lib/l10n/app_{en,zh,zh_Hant,zh_Hans}.arb`（`app_zh.arb` 是 gen-l10n 要求的 base fallback，內容同 zh_Hant）→ `flutter gen-l10n` 產 `lib/generated/l10n/`（Hans/Hant 併在 `app_localizations_zh.dart`，與 dHealth 相同）。`lib/settings_keys.dart`（Prefs/PrefsDefaults）+ `lib/settings_model.dart`（`SettingsModel.load()`，language/theme/boardSize）+ `lib/widgets/settings_screen.dart`（語言、主題 dropdown，AppBar 齒輪進）。`Game2048App` 用 `ListenableBuilder` 包 `MaterialApp`，改語言/主題立刻生效。新增 deps：`flutter_localizations`、`intl ^0.20.3`、`shared_preferences ^2.5.6`（pubspec `generate: true`）。
- 驗收：`flutter analyze` No issues、`flutter test` 4/4（原 move+undo、連按 undo、合併規則對照參考實作、格數對話框）。

---
## 2026-11-10 CI signing + small cleanups (device checks still zero)

- `android/app/build.gradle.kts` already read `android/app/key.properties`, but CI never
  restored the secrets, so every CI release APK was debug-signed (new signature per build ->
  no in-place upgrade). Added the "Restore signing key" step, same shape as dNeko/dHealth
  minus their JCA preflight.
- `lib/main.dart`: one `_swipe` handler for both drag-end callbacks + `_mergeLine` shared by
  the four directions (the four copies each differed by one reversal). Net -88 lines.
  Verified `flutter analyze` clean, `flutter test` green.
- Note on a wrong review claim: a diagonal drag does NOT move twice -- the pan recognizer
  locks one direction (instrumented `_move` calls showed one per swipe), so the old
  double-handler code was correct. `test/widget_test.dart` C-1 keeps it that way.
- `pubspec.yaml`: dropped `cupertino_icons` (0 references).

---
## 2026-11-09 待辦：遷移到 Flutter Built-in Kotlin（d2048 / dNeko / dHealth 三案共同）（d2048 端已完成）
### d2048 已做（2026-11-09，hc terminal 實測）

只改了兩處：
1. `android/app/build.gradle.kts`：删掉 `id("org.jetbrains.kotlin.android")`（`kotlin { compilerOptions { jvmTarget } }` 留著，
   `settings.gradle.kts` 的 KGP 版號行也留著 —— FGP 還沒遷移的插件要用）。
2. `android/gradle.properties`：`android.builtInKotlin=false` → `true`（`android.newDsl` 維持 false，那是另一件事）。

**證明真的生效**（不能只看警告消失：警告是因為 app 自己宣告 KGP 才噴，FGP 在背後偷偷套 KGP 時它不噴）——
用 init script 探 `:app` 的 plugin 狀態：

```
builtInKotlin=true  → PROBE KGP_APPLIED=false   ← AGP 自己編 Kotlin
builtInKotlin=false → PROBE KGP_APPLIED=true    ← FGP 在背後套 KGP（逃生口）
```

本機驗过：`flutter analyze` No issues found、`flutter test` All tests passed、
`flutter build apk --debug --target-platform android-arm64` ✓ Built（73.6 MiB，與遷移前同大）。
**尚未驗**：release（AOT，本機出不了）→ 推上去讓 CI 跑，或在 Windows build 一次。

### AGP 要不要趁勢升到 9.5？（2026-11-09 決定：不升）

Flutter 3.47.9 自己的工具鏈就把範本版號硬編在 **AGP 9.1.0 / KGP 2.4.0**
（`flutter/packages/flutter_tools/lib/src/android/gradle_utils.dart:44-52`，`flutter create` 生出來的就是這兩個）。
也就是 9.1.0 是「Flutter 團隊幫你驗過」的那一版；搶先上 9.5 就是自己去當前人。
再加上 built-in Kotlin 之後 **Kotlin 編譯器是 AGP 內附的**，AGP 一動 Kotlin 就跟著動（#192167 就是这类版本錯位）。

要升的時機：① 升 Flutter 後範本改了版號；② 需要 AGP 的修正/新功能；③ Play 要求更新的 targetSdk。
升的時候：一案一案升、CI 當驗證、在有網路的機器上做（本機 gradle 快取只有 9.0.1/9.1.0）。


---

---

