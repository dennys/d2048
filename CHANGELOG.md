# d2048 CHANGELOG

已完成事项的归档区（把 TODO.md 瘦成「只剩還沒做的事」）。
**`git log` 才是權威**，這裡只是保留當時的判斷與驗收數字，方便日後回溯「為什麼现在是這樣」。
新的完成紀錄加在最上面。

---
## 2026-11-11 Code review 修正（read-only review 15 項 → 修 13、驳回了 2）

第二輪 read-only review（報告未留檔，結論直接併入本檔）。**先記教訓**：review 用 `flutter test` 量到的「按鈕排溢出 184px／AppBar 標題溢出」是**假發現**——測試環境的字體是 Ahem（每個字元 14×14 方塊，比真機 Roboto 寬一倍），真機 Pixel 5 / Poco F5 實測不爆。排版類結論**只能用真機，或至少註明是測試字體測的**。

- **Must fix（資料遺失／崩潰）**
  - 玩家選單的「新增玩家」欄打**既有**名字 → `onAdd`（`addPlayer`）已同步把 `currentPlayer` 改掉，`_switchPlayer` 卻拿活值比對而 early-return → 畫面還是上一位的盤，下一手把 A 的棋盤寫進 `saved_game/B`（**B 的進度消失**）。實測重現：`saved_game/B` 被覆寫成 `ids 1,2 / score 11 / moves 4`。→ `_switchPlayer` 改與「開選單前的人」比對。
  - `players.dart` 兩個對白框的 `TextEditingController` 在 `await showDialog` 後馬上 dispose，退場動畫期間 TextField 還在樹上 →「Who's playing?」輸入名字按 Save 就 `used after being disposed`（加級聯 layout/scheduler assertion，整個遊戲畫面消失）。→ 改 `StatefulWidget`，在 `dispose()` 釋放（比照 `snapshots.dart`）。
  - 「You win!」／「Game Over!」**不是覆蓋層**：兩個 `Container(black54)` 是 body `Column` 的一列 → 沒蓋住棋盤、黑底出現在棋盤**下方**，還把 `Expanded` 的棋盤擠小。→ 搬到外層 `Stack` 的 `Positioned.fill`；雨個遮罩抽成 `_scrim()`（順帶去重复）。
  - 切玩家沒等 `_pending` → 在飛的寫入會落到換好的人 namespace。→ `setCurrentPlayer` 前 `await _pending`。
- **Should fix**
  - 玩家選單不能捲（`Column` 直排 `ListTile`）→ 玩家一多「新增」那列被擠出對白框。→ 清單改 `Flexible + ListView(shrinkWrap)`。
  - **Daily 局沿用「上次的格數」**（先開 8×8 再按 Daily → daily 變 8×8），家庭每日排行榜卻把不同格數的分數排在一起。→ daily 一律 4×4；回普通局時 `size` 改回 `settings.boardSize`。
  - 玩家名沒長度上限（使用者自己敲）：`addPlayer` 統一 trim + 限長 20（`PrefsDefaults.playerNameLimit`）+ 大小寫去重（'Amy'/'amy' 不變成兩位玩家），並**回傳實際玩家名**給選單去 pop（否則呼叫端拿原始大小寫去 `setCurrentPlayer`，會切到不存在的 namespace）。
  - CI 的 Codecov 那步永遠是空上傳（`flutter test` 沒 `--coverage` → `coverage/lcov.info` 根本不存在；action 預設 `fail_ci_if_error: false` 所以不会紅）。→ 加 `--coverage`。
- **Nice to have**
  - `history` 只進不出（8×8 長局記憶體線性成長）→ 上限 `_historyLimit = 200`，超過丢最老的；檢查點放在「這手成立」之後，被擋下的無效移動不會误删。
  - 跨午夜還在玩 daily → 分數记在昨天的 `lastDailyDate`。→ `_afterMove` 比對 `dailySeedFor(now)` 與 `_seed`，不同則這局改算今天。
  - 分享截圖的 3 張 `ui.Image` 沒 dispose（native 記憶體等 GC）→ 補 `.dispose()`。
  - AppBar 標題整排 `FittedBox(scaleDown)` + 玩家名 `maxWidth 160` + ellipsis；Undo/Redo/New Game/Daily 那排包 `FittedBox(scaleDown)`；分數區包 `Expanded`。（排版三項的**真實**觸發條件是窄螢幕 + 系統字體放大，不是 review 講的「一定爆」。）
  - 删死碼：l10n `switchPlayer`（4 個 arb + 產生檔，全案无人用）、`tileColor` 的 `case 0`。
- **測試**（+7，共 26）：`switching player from the list…`（正當路徑 regression guard）、`typing an existing name in the Add field…`（查畫面分數 **和** `saved_game/B` 的 tile id）、`player dialogs do not use a disposed controller`、`win overlay covers the board without shrinking it`（比對 overlay 前後棋盤 rect + 遮罩是否蓋住棋盤中心）、`daily game is always 4x4…`（數背景格）、`player picker stays usable with many players`（15 位）、`layout survives a narrow phone with large system text`（320×640 + textScale 1.3 + 21 字玩家名，`takeException()` 必為 null）。
  **驗收**：`git stash push -- lib/` 用**舊 lib + 新測試**跑 → 6 支新測試全紅；換回新 lib → 26/26 全綠；舊的 19 支一路都綠。
- 驗收：`flutter analyze` No issues、`flutter test` 26/26。

---
## 2026-11-10 Code review 修正（REVIEW.md 14 項，review 檔已併入本檔刪除）

Read-only review（`REVIEW.md`，已刪）對 2026-11-10 功能 backlog commit（`a675834`）的 14 項發現：13 項全清、1 項半清（剩 class 合併，搬 TODO.md）。

- **Must fix**
  - Leaderboard dialog layout 崩潰（5 個 `RadioListTile` 放 `Row` → 無限寬 assert；debug 紅屏、release 渲染壞）→ 每個包 `Expanded`
  - Leaderboard 格數 picker 不 stick（`var size = initialSize` 在 `StatefulBuilder` builder 內，每次 rebuild 重設）→ 移出 builder
  - New Game 選目前尺寸無反應（`RadioGroup.onChanged` 只在 selection 改變時觸發）→ `groupValue: null`（每個 tap 都算改變；代價：目前尺寸不高亮）
- **Should fix**
  - Daily 後回不到普通局（Daily 替換記憶體狀態、只能重啟 app 拿回、New Game 會覆蓋普通存檔）→ Daily 按鈕改 Daily↔普通 toggle：切走前 `_persist` 目前局、再按切回（l10n 新增 `normal` ×4 語）
  - Daily 分數計入 per-size best 與 leaderboard（`_afterMove` 不看 mode）→ `if (mode == GameMode.normal && score > best)`
  - Share 截圖檔堆積 + web 炸（檔名帶 timestamp、`writeAsBytesSync` 在 UI thread、`dart:io` File 在 web throw）→ 固定檔名 `d2048_share.png` + `await writeAsBytes` + `kIsWeb` skip
  - 損毀存檔靜默丟 board（`loadSavedGame` catch 回 null 無 log，寫入路徑都有）→ 加 `debugPrint`
  - Leaderboard dialog 無測試（沒測的 dialog 正是會崩的那個）→ 新測試：開 leaderboard、tap 6×6、expect 6×6 欄
  - 每步兩個未 await 的寫入（fire-and-forget；app 被 kill 最後一步不落盤）→ `_persist` 串接寫入（`_pending.then`，依序落盤）
- **Nice to have**
  - `SavedGame.mode` 冗餘（key 已表達 mode）→ 刪欄位（保留 `seed`）、`_restoreSaved` 改收 mode 參數；舊存檔多出的欄位被 fromJson 忽略、照讀
  - Tile 序列化 5 份 → `_tilesToJson`/`_tilesFromJson`（`game_storage.dart`）+ `_tileData()`（`main.dart`）；**兩 class 合併未做**（見 TODO.md）
  - TODO.md 過時「470 行」數字 → 刪
  - Leaderboard row 兩 dialog 重複 → `_rankRow` helper
  - Share text 報 board 已不存在的 maxTile（`_gameMaxTile` undo 不回滾）→ 從 `tiles` 重算
- **測試修正**：daily／auto-resume 測試的「重啟」是假的——`pumpWidget` 同型別 widget 會保留 State（`initState` 不重跑），舊測試靠 State 沒被銷毀才過。改先 pump 空 widget 銷毀 State 再重開，才是真重啟。
- **Review 誤判一則**：review 的「undo 吃掉剛 spawn 的 tile」是 false positive——snapshot 在移動前拍，undo 還原移動前狀態（新 tile 消失、score 回滾）正是正確行為；測試 `expect(readBoard, equals(before))` 斷言的就是正確行為。已從 review 移除。
- 驗收：`flutter analyze` No issues、`flutter test` 18/18（原 17 + 新 leaderboard dialog）。

---
## 2026-11-10 功能 backlog 5 項：per-player／每日排行榜／里程碑慶祝／分享／本地排行榜

- **Per-player Profiles**（`lib/game_storage.dart`、`lib/widgets/players.dart`）：遊戲資料全部按玩家 namespace（`saved_game/<player>`、`saved_game_daily/<player>`、`snapshots/<player>`、`best_scores/<player>`、`stats/<player>`）+ `players`（name list）+ `current_player`。首次啟動輸入名字（placeholder 畫面 + dialog，取消可重按）；AppBar 玩家 chip（person icon + 名字）tap 切換／新增。遷移：舊全域 4 個 key 首次跑新 code 時搬進預設玩家 `"Player"` 並刪舊 key（`players` key 存在即跳過，只跑一次）。
- **家庭 Daily Leaderboard**（`GameMode.daily`、`dailySeedFor`）：seed = 本地日期（如 20261110）；daily 局用 `Random(seed)` → 全家同開局 2 格，走第一步後各自分岔（Wordle 式）；daily 局獨立存檔（`saved_game_daily/<player>`；`SavedGame` 加 `mode`/`seed` 欄位，舊存檔缺欄位預設 normal）；`GameStats` 加 `dailyBest`/`lastDailyDate`（新的一天重置）。Daily 按鈕開／接續今天的局；trophy 按鈕開排行榜（今日分數高→低，沒玩的排最後）。
- **里程碑慶祝**：本局最大方塊跨過 1024/2048/4096 → 全屏 scale-in + fade-out 動畫（1.5 秒、1.6 秒後自動消失、`IgnorePointer` 不擋過關 overlay 的按鈕）。
- **分享成績**（`share_plus` 13.3.1）：share 對話框 → 文字（玩家/score/best/moves/max tile）或 board 截圖（`RepaintBoundary` → PNG → temp file）。13.x 的 gradle 已相容 AGP 9 built-in Kotlin（10.x 無條件套 KGP 會被擋）。
- **本地排行榜**（`lib/widgets/leaderboards.dart`）：podium 按鈕，每格數 top 10（跨玩家，`bestScoreFor`），RadioGroup 切格數。
- **l10n**：14 個新字串（players/whoIsPlaying/yourName/addPlayer/add/switchPlayer/daily/dailyLeaderboard/leaderboard/notPlayed/noScores/share/shareText/shareScreenshot），4 個 arb + `flutter gen-l10n`。
- **dgx1 build 修復**：AGP 9 built-in Kotlin 下，新 plugin（shared_preferences_android 2.5.x、path_provider_android 2.3.x）走 jni → NDK（只有 x86-64 host）→ aarch64 編不了；舊 plugin（2.4.8）套 KGP 又被 AGP 9 擋。解法：pin「無 KGP 且無 jni」的最後版本 `shared_preferences_android 2.4.28` + `path_provider_android 2.2.23`（dNeko 同款模式，見 `~/dennys/AGENTS.md`）。
- 驗收：`flutter analyze` No issues、`flutter test` 17/17（原 11 + 新 6：遷移、per-player namespace、daily seed、daily 接續、里程碑、daily 排行榜）、`flutter build apk --debug --target-platform android-arm64` ✓ 83.5 MiB。

---
## 2026-11-10 Code review 修正（REVIEW.md 16 項全清，review 檔已併入本檔）

Read-only review（`REVIEW.md`，已刪）對 main + working tree 的 16 項發現，全部處理完。

- **Must fix**
  - 右/下方向方塊互相穿越（`_move` 對 right/down 改從目標邊收線，tile 順序才和 `_applyLine` 打包方向一致）
  - resume／載入快照後 tile id 碰撞（`_nextId` 每次啟動從 1 起 → `ValueKey` 重複；修法：還原後 `_syncNextId()`）
  - undo 過關那手 → `You win!` overlay 鎖死 board（`_Snapshot` 帶 `won`/`keepPlaying`）
  - 存檔格式變更靜默丟檔（`SavedGame.fromJson` 對 `moves`/`undoCount` 給預設值；`tiles`/`score`/`boardSize` 保留 hard cast）
  - 全部功能只在 working tree → checkpoint commit 先入版控
- **Should fix**
  - 測試補右/下合併規則（確定性棋盤 seed；原 merge 測試在 `Random(42)` 下初始兩方塊不同行、根本沒發生合併，是平凡通過）
  - undo 計數回滾（`_Snapshot` 帶 `moves`/`totalMerges`/`wins`；`best`/`maxTile` 是 high-water mark 不滾）
  - README 註明 arm64-only（x86-64 模擬器裝了開不起來）
  - CI 沒 keystore secrets 時 artifact 加 `-debugsigned` 後綴（debug 簽章每版簽名不同，不能覆蓋升級）
  - workflow 比對已作廢共用钥密碼改用 sha256 hash（明文不再進檔；11/9 已換鑰，純衛生）
  - 刪 dead `com/example/d2048/MainActivity.kt`（manifest 指 `com.dennys.d2048`）
  - `GameStorage` 四個 setter 加 try/catch（寫入失敗不再靜默）
- **Nice to have**
  - 4096+ 方塊四檔紅循環（原全部同色）
  - `Locale.fromSubtags(scriptCode:)` 取代 `Locale('zh','Hans')`（第二參是 region 不是 script）
  - `SettingsModel.load(prefs)` 傳入同一份 instance（main 不再多一次 `getInstance`）
  - 刪未引用的 `assets/icon/*.png`（mipmap 已 commit，source 在 git history 可找回）
- 驗收：`flutter analyze` No issues、`flutter test` 10/10（原 8 + 右/下合併；新方向測試對舊邏輯實測 fail）。
- 未做（依指示）：iOS/macOS/Linux/Windows 建置路徑、真機、CI 日志；dNeko/dHealth 的同一明文 literal（`dNeko/.github/workflows/github_action.yaml:99`、`dHealth/...:132`）。

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

