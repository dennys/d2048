# d2048 Code Review — 2026-11-11

範圍：今天 3 支未 push 的 commit（`cfb06e1`／`45ddfe0`／`1159a01`，`origin/main..HEAD`）＋ 全案。
**只評不改**：一個檔案都沒動。

## 0. 我實際跑過什麼（結論有依據，不是光看）

| 項目 | 結果 |
|---|---|
| `flutter analyze` | **No issues found**（Flutter 3.47.9 / Dart 3.13） |
| `flutter test` | **27/27 通過** |
| `flutter test --coverage` | 全案 **72.5%**（`lib/`，詳見 F-1） |
| `flutter gen-l10n` | 重跑**零 diff** → `lib/generated/` 與 `.arb` 同步，沒脫節 |
| l10n key 比對 | 4 支 arb 各 **51** 個 key，`app_en` 為準 **無缺、無多** |
| `git status` | 乾淨（`pub get` 沒改髒任何檔案） |
| Dart `Future` 語意驗證 | 見 H-1，用一支 `/tmp` 小程式實測，非推論 |

---

# Part 1 — 今天的 3 支 commit

**總評：值得合。** 13 項修的都是真 bug（不是風格），而且多數有對應測試；註解講的是「為什麼」而不是「做了什麼」，
`shortcut:` 標記有守規矩。以下問題**沒有一個需要擋下 merge**，但 H-1／H-2 建議近期補掉。

## H-1 严重 · `_persist()` 那條 Future 鏈一旦拋錯，這次啟動的自動存檔就**永久失效**

`lib/main.dart:430`（`_persist`，鏈在 `:441`）：

```dart
_pending = _pending.then((_) async {
  await storage.saveGame(game, mode);
  await storage.saveStats(stats);
  _notifySaveFailure();          // ← 這也在這條鏈裡
});
```

Dart 的 `then` 對「已經失敗的 Future」會**跳回呼函數、原樣把錯誤傳下去**。所以鏈上任何一次拋例外，
之後每一次 `_persist()` 的回呼函數都**不會被執行**，而且是靜默的（沒有人 `catchError`，最後只會在 zone 噴未處理例外）。
實測（`/tmp/dt/a.dart`，`dart run`）：

```
persist callbacks that actually ran after one throw: 0 / 3
```

今天這版看不到這個爆炸，是因為 `GameStorage._write` 把例外全吞了。但 `_notifySaveFailure()` 就在同一條鏈裡，
它要拿 `context`、`ScaffoldMessenger.of(context)`；那條鏈的「安全」現在**完全依賴「鏈上永遠不會有人拋」**這個隱含假設。
小遊戲不該因為存檔失敗而崩（這個判断對），但代價不該是「整個 session 不再存檔」。

修法（概念，一行的量）：鏈尾用 `whenError`／`catchError` 做隔離，或把 `_notifySaveFailure()` 移到鏈外。

## H-2 严重 · `saveGame`／`saveStats` 的 **玩家 key 是在「寫入執行時」才解析**，所以 `await _pending` 其實沒保護到它要保護的那個 case

`cfb06e1` 的註解寫：

```dart
final shown = storage.currentPlayer;
...
await _pending; // 等在飛的寫入落盤，否則那筆會寫到換好的人 namespace 下
await storage.setCurrentPlayer(chosen);
```

問題：`GameStorage.saveGame` → `_key(...)` → 用的是 **執行當下的 `currentPlayer`**：

```dart
String _key(String base, [String? player]) => '$base/${player ?? currentPlayer}';
```

在「Add 欄輸入既有名字」這條路徑上，`onAdd` → `addPlayer()` **已經先把 `currentPlayer` 改成新人**了。
所以 `await _pending` 排在後面的那筆舊玩家盤面，落盤時 `currentPlayer` **早已是新玩家** →
`await _pending` 保護不到它，寫錯人的視窗還在。`cfb06e1` 加的測試會過，是因為平台寫入約 1–5 ms，
人手從輸入到按下 Add 早已把隊列排空 —— 也就是**目前是靠時機僥倖正確，不是靠程式邏輯正確**。

對比：同一檔裡的 `setBestScore` 用的是**對的**寫法 —— `final key = _key(Prefs.bestScores);` 在呼叫時**同步**算好。
照這個模式，把 `_persist()` 裡的 `final player = storage.currentPlayer;` 一併 captures、
`saveGame/saveStats` 收一個明確的 player 參數即可，diff 很小。

## H-3 中 · `1159a01`（寫入失敗不再靜默）**只做了一半**

`_write()` 成了全案唯一寫入口（好事），但 UI 提示**只掛在 `_persist` 這條路**：

* `storage.saveSnapshots(...)`（`main.dart` 的 `_saveSnapshot`／快照刪除）→ 失敗**完全無訊號**，只有 `debugPrint`。
  使用者按了存快照、以為存到了。
* `storage.setBestScore(...)` 同樣無提示（這個可以接受，最高分丟了影響小）。
* **`_write` 只看例外、不看回傳值**：`SharedPreferences.setString` 也可能**不拋、直接回傳 `false`**
  （平台實作可以回報失敗）。這種情況現在還是靜默成功。

## H-4 中 · `addPlayer()` 這整組新的名字正規化，**一支測試都沒有**

`game_storage.dart`：`trim` → `runes.take(20)` 限長 → 大小寫不分去重（保留原 spelling）→ 全空白不建玩家、回傳 `currentPlayer`。
這批 commit 裡**唯一的純函數級新行為**，也是最容易在日後被改壞的那種（有分支、有邊界、有回傳值語意）。
今天只有間接被 `seedTwoPlayers` 用到。建議補一支 `test('addPlayer normalizes names')`：
`'  amy  '` vs 既有 `Amy` 要合併成 `Amy`、20 字上限、全空白不新增。**另外一個小邊界**：
`String.fromCharCodes(runes.take(20))` 限的是 20 個 **code point**，emoji（UTF-16 兩個 unit）會讓字串長度變成 40。
不致命，但「限長撐爆佈局」的原始目的就打折了。

## H-5 低 · `_askPlayerName` 少了 await 之後的 `mounted` 檢查

```dart
final name = await showPlayerNameDialog(context);
if (name == null || !mounted) return;
await storage.addPlayer(name);
setState(() { ... });          // ← await 之後沒再確認 mounted
```

本檔其他 async 路徑（`_switchPlayer`、`_saveSnapshot`）都有 await 後 `if (!mounted) return;` 的二次確認，
這一處漏了。視窗機率極低（冷啟動對話框期間不會被拆），但這是**同檔已知的慣例**，補上才一致。

## H-6 低 · 跨午夜那段改了 `_seed`，**沒改 `_dailyRng`**

`_afterMove`：`_seed = today; stats.lastDailyDate = today; stats.dailyBest = 0;` 但 `_dailyRng` 仍是昨天那條亂數流。
新方塊的位置／2 or 4 跟新 seed 不再對應 → 同一天兩個玩家的「同 seed 同開局」保證斷掉了（只在跨午夜還在玩時）。
另外這段會**直接歸零昨天的 `dailyBest`**：見 P-4，`GameStats` 根本沒有一天一筆的結構。

## H-7 低 · `45ddfe0` 刪掉的 `tileColor` 的 `case 0` 只是把自己埋了地雷

```dart
default:
  return [red[400], red[500], red[600], red[700]][(value ~/ 2048) % 4];
```
`case 0:` 被刪掉 → 現在 `tileColor(0)` 會落到 `default` → `(0 ~/ 2048) % 4 == 0` → **回傳紅色**。
今天沒有人會傳 0 進去（背景格是 `_buildBoard`／`MiniBoard` 另外畫的），所以**不是 bug**，
但「拿掉一個 branch」換來的是「函數對 0 的定義變錯且沒人會發現」。這 2 行的刪除換到的價值是 0。

## H-8 低 · 遮罩內容沒做 fit，跟這輪 commit 自己的原則不一致

`_scrim` 的內容是 `Column`（文字 28px ＋ 一顆／兩顆按鈕），
但同一輪 commit 為了防溢出已經把按鈕排與 AppBar 標題都包了 `FittedBox(scaleDown)`。
棋盤是**正方形**、`Expanded` 裡可能被擠得不太高，`textScale 1.3` ＋ 較長的本地化字串（遊戲結束）有 RenderOverflow 風險。
新加的 `layout survives a narrow phone with large system text` **不會進到 game over**，所以這條路徑無人守。

## H-9 低 · CI 现在會產生 `coverage/`，但 `.gitignore` 沒有它

`.gitignore` 全文**沒有 `coverage/`**（已 `git check-ignore` 確認 NOT ignored）。
`cfb06e1` 把 `flutter test` 改成 `flutter test --coverage` 之後，本機跑一次測試就會多一個未追蹤目錄。
一行 `.gitignore` 的事。

---

# Part 2 — 全案

架構判断是好的：`main.dart`（遊戲邏輯＋UI）、`game_storage.dart`（持久化）、`settings_model.dart`（設定）、
`widgets/*`（對白框）、`settings_keys.dart`（key/預設值唯一定義）分得清楚；
`SavedGame`／`BoardSnapshot` 的選填欄位都給預設值，舊存檔缺欄位不會整份遺失 —— 這是對的直覺。
以下依「影響使用者資料／體驗」排序。

## P-1 `currentPlayer` 是空字串時**沒有救回機制**（會把整個玩家的資料變孤兒）

```dart
currentPlayer = _prefs.getString(Prefs.currentPlayer) ?? '';
```
`GameScreen.initState` 只檢查 `loadPlayers().isEmpty`。
所以只要 `players` **非空**而 `current_player` 不見（被清掉／備份還原到一半／`addPlayer` 回傳 `''` 的极端情况），
app 就正常開著、AppBar 名字空白，而所有讀寫都落在 `saved_game/`（key 尾巴著一個 `/`）→
**該玩家舊資料永遠讀不到**，而且沒有任何提示。
一行的防呆：`if (currentPlayer.isEmpty && players.isNotEmpty) currentPlayer = players.first;`

## P-2 `players` JSON 損毀 ⇒ **靜默資料全遺失**

`loadPlayers()` 的 `catch (_) { return []; }` → `initState` 認為「還沒有玩家」→ 出「誰在玩」→
`addPlayer` 把 `players` 寫成 `['新名字']` → 舊的 `*/<舊玩家>` 全部變孤兒，**永不可達**。
這正是 `1159a01` 剛在「寫入」那一側修掉的「靜默吞掉」，讀取這一側還在。
（`loadSavedGame`／`loadSnapshots` 都有「損毀只當沒有、其餘照讀」的註解與逐筆容錯，`players` 是這裡唯一會造成**全案資料**歸零的點。）

## P-3 Daily 破局後按 **Play Again**，會「不告而別」地開一局 **4×4 普通局**

Game over 遮罩的按鈕是 `setState(_initializeGame)`；`_initializeGame` 的 `mode` 預設是 `normal`，
而 `size` **沿用 daily 的 4**，也不會去讀 `settings.boardSize`。
結果：原本玩 8×8 的人，在 daily 破局後按 Play Again → 得到一局**普通的 4×4**，最高分也變成看 4×4 那欄。
`cfb06e1` 為同一個病因在 `_restoreNormal()` 修過（`size = widget.settings.boardSize`），**這條路徑漏了**。
新測試 `daily game is always 4x4...` 只驗證「進 daily」，**沒驗證「回普通」會恢復 8×8**。

## P-4 `GameStats` 只記「今天」，家庭每日排行榜**沒有昨天**

`dailyBest` ＋ `lastDailyDate` 是單一欄位 → 一天只容得下一筆。
昨天那輪排名不存在任何地方（P-6 也講到），而且 `lastDailyDate` **只會在 `_afterMove` 被更新**：
開了 daily、一個方塊都沒滑，排行榜就會把你算成「沒玩」。
若「全家比今天」是明確需求，這就不是 bug、是設計；但請在 `GameStats` 上標註這個極限，
否則日後一定有人問「昨天的排行呢」。

## P-5 `stats.gamesPlayed` 被灌水（數字會無中生有）

`stats.gamesPlayed++` 在 `_initializeGame` 裡，而 `_initializeGame` 也會由
**Daily↔Normal 切換**、**New Game**、**切到一個還沒有存檔的玩家**、**冷啟動時該玩家沒存檔** 觸發。
也就是：新玩家第一次打開 app、還未動過任何一步，設定頁就會顯示「已玩 1 局」；
反覆切玩家／切 Daily 就一直加。統計是給家人看的，這種「無中生有」的數字最傷信任。

## P-6 `dependency_overrides` 是**全域 commit**，正式版／CI 也吃這些舊版

`pubspec.yaml` 把 `shared_preferences_android 2.4.28` ＋ `path_provider_android 2.2.23` 釘在 `dependency_overrides`
（註解自己寫「這是那台主機的限制，不是本專案的」），但它同時**進了 `pubspec.lock` → CI 與 release build 也用這版本**。
dHealth 的做法（釘選放 **gitignored `pubspec_overrides.yaml`**）才是對的形狀：本機解卡、CI／正式版用乾淨依賴集。
若刻意留在 commit 裡，請在 README 寫明「正式版也含這兩個舊版插件」，避免未來有人以為 CI 驗的是上游新版。

## P-7 CI：**`CODECOV_TOKEN` 沒設 ⇒ 最後一步必紅**（keystore 那步有防呆，這步沒有）

`codecov-action@v5` 需要 token，缺 token 會 `Token required` 非零退出（v5 起 tokenless 上傳已關，已查證 issue #1653／#1671）。
同檔的 `Restore signing key` 那步寫了完整的缺 secret 防呆（warning ＋ `-debugsigned` 後綴 ＋ 不退 1），
對照之下 Codecov 這步只差 `continue-on-error: true` —— 否則整條 CI 訊號會在「analyze／test／debug／release 全綠」之後紅掉。

## P-8 深色模式對比不足（`Colors.grey[700]` 在白底以外的地方是灰字壓黑底）

`main.dart` 有 5 處 secondary 文字用 `Colors.grey[700]`。實算對比：
**grey[700] vs 深色 surface ≈ 3.02:1**，低于 WCAG AA 正文門檻 4.5:1（只有 `grey[600]` 4.06、`grey[500]` 6.98 夠）。
棋盤與格子也用死死的 `grey[400]/grey[300]`，所以深色模式其實是「黑底貼一張淺色棋盤」——
如果是刻意的（2048 經典配色），請寫一行註解，否則這會被當成 bug 回報。

## P-9 無障礙與輸入

* 方塊與棋盤**沒有 Semantics label**（螢幕閱讀器讀到的是無意義的 Stack）；`TODO.md` 已列，尚未動。
* 只吃 `onHorizontalDragEnd/onVerticalDragEnd`：**沒有鍵盤**（desktop／web 完全不能玩），
  且拖到**停住才放手**（速度 0）會被 `_swipe` 直接丟掉 —— 這是 `_swipe` 有註解的刻意行為，但不是所有人都知道。
* `_shareScreenshot()` 在 web **靜默 return**，按了完全沒反應（`kIsWeb` 那段註解是對的，缺一個使用者可見的提示）。

## F-1 測試：覆蓋率 72.5%，但真正的洞只有一個地方

| 檔案 | 覆蓋 |
|---|---|
| `lib/widgets/settings_screen.dart` | **0.0%**（51 行） |
| `lib/settings_model.dart` | 65.0% |
| `lib/main.dart` | 86.3%（615 行） |
| `lib/game_storage.dart` | 96.2% |
| `lib/widgets/players.dart` | 96.8% |
| `lib/widgets/snapshots.dart` | 98.7% |
| `lib/widgets/leaderboards.dart` | 98.3% |
| `lib/tile_style.dart` | 80.0% |
| `lib/generated/l10n/*` | 0%（zh 系完全沒被跑到；測試只用 en） |

`settings_screen.dart` **一支測試都沒碰過**（語言／主題／震動切换的整頁從未渲染）。
其餘測試品質很好：確定性 seed、`readBoard` 從 `AnimatedPositioned` 反推棋盤、
`_FailingStore` 模擬落盤失敗（連「UI 已走到第 2 步但 store 裡仍是 moves:0」都驗了，很漂亮）、
退場動畫 controller 生命週期、窄螢幕＋大字體 —— 這些是真在守行為的測試。
**最便宜的一筆投資**：pump 一次 `SettingsScreen` 並切一次語言／主題。

另外明確**沒被任何測試守到**的：P-3（回普通局恢復 8×8）、H-4（`addPlayer` 正規化）、
H-2（寫入在飛時切玩家）、`saveSnapshots` 寫入失敗的提示、`players` 損毀。

## F-2 其他（nit 級，撿起來就順手）

* `android/app/build.gradle.kts:22` 還留著 Flutter 範本的 `// TODO: Specify your own unique Application ID`，
  但 `applicationId` 早就對了 → 純噪音。
* `README.md` 的 Features 清單**停在上世代**：per-player profiles、Daily 挑戰、家庭每日排行榜、
  本地排行榜、分享、里程碑慶祝 —— 一個都沒寫。README 是唯一對外入口，這條 drift 要補。
* `lastError` 是全域一個欄位：若 `saved_game` 成功、`stats` 失敗，提示仍是「你的遊戲存不下來」→
  歸因不準（可接受，知道就好）。
* 快照沒有「容量上限以外的去重／覆名」；玩家**不能刪除也不能改名**，`players` 無上限 → 每個玩家會再多組 key。
* `SnapshotListDialog` 的 `onDelete(_items)` 把**活列表的參考**交出去（`saveSnapshots` 當下立刻序列化，所以目前無害）。
* `_saveSnapshot`／`onDelete` 的存檔沒 await 結果（P-1/P-2 之外，這是最後一處未 await 的寫入）。
* `_undo`／`_redo` 不回滾 `stats.maxTile`／`_gameMaxTile`、也不重建 `_seed` 的 daily 流 ——
  「先過 2048 再 undo」會讓生涯最大方塊留下痕跡。刻意或否則都好，請標註。
* 快照寫入失敗無提示（同 H-3）。

---

## 如果要動手，順序是這樣

| 優先 | 事項 | 量 |
|---|---|---|
| 1 | H-1：`_persist` 鏈加錯誤隔離（`catchError`／`whenError`） | 一行 |
| 2 | H-2：`_persist` captures `player`，`saveGame`／`saveStats` 收明確參數（照 `setBestScore` 的寫法） | 小 |
| 3 | P-1：`currentPlayer` 空值時退回 `players.first` | 一行 |
| 4 | P-3：daily game over 的 Play Again 改走 `_restoreNormal()` ＋ 補「回普通局仍是 8×8」測試 | 小 |
| 5 | H-3：把 `lastError` 也掛到 `saveSnapshots`；`_write` 一併看 `setString` 的 `false` | 小 |
| 6 | H-4 ＋ P-2：補 `addPlayer` 正規化測試、`players` 損毀時別覆蓋清單 | 小 |
| 7 | P-5：把 `gamesPlayed++` 從 `_initializeGame` 挪到「真的開了新局」的三兩個呼叫點 | 小 |
| 8 | P-7／H-9：CI `continue-on-error`、`.gitignore` 加 `coverage/` | 各一行 |
| 9 | F-1：pump `SettingsScreen` 一支測試 | 小 |
| — | P-8 對比、P-9 無障礙、P-6 override 形狀、P-4 每日歷史 → **要嗎？要的話是另一輪工，不是今天的尾巴** | — |

**沒查／沒驗的東西**：真機行為（深色模式實際色值、實字體下的遮罩溢出、Android 13+ 分享行為）
只能在真機上確認，`flutter test` 的 Ahem 字體量不出來（`TODO.md` 已記這條）；
`release`（AOT）與 jni 在本機 aarch64 出不了，依 `~/dennys/AGENTS.md` 只能靠 CI；
我沒有連 GitHub 查 `CODECOV_TOKEN`／`KEYSTORE_B64` 兩組 secret 到底存不存在，
P-7 的說法是「**若沒設**則必然紅」，請自行確認 secret 狀態。
