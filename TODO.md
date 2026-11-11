# d2048 TODO

慣例：一個待辦一段，寫清「檔案:行」與「為什麼現在是這樣」；**做完就搬到 `CHANGELOG.md`**（`git log` 才是權威）。

> **2026-11-11 重整**：全案 read-only review（明細在 `review.md`）的發現全部併入本檔；原本重複的
> Built-in Kotlin 那 60 行背景**已刪**（同樣的內容與證據早在 `CHANGELOG.md:160-190`）。
> 新規格 E（Telegram 家庭排行榜）是這輪討論的結論，附實測依據。

## 狀態總覽

| 組 | 項 | 一句話 |
|---|---|---|
| **A 會吃資料或會崩** | 6 | 全部是「讀 code 就確定」，不用真機 |
| **B 榜上數字的誠信** | 2 | 統計灌水／每日榜只記今天 |
| **C 測試** | 4 | 27 支全綠但 `settings_screen.dart` 0% |
| **D 體驗與無障礙** | 6 | 含原本那條實機確認 |
| **E Telegram 家庭排行榜** | 1 | 新規格，不用架站、不用帳號 |
| **F 明確不做** | 8 | 寫死，別每輪再問一次 |
| **G 收尾 nit** | 5 | 各一行的量 |
| **H 今日修復復盤** | 3 | A-1…A-6 那輪判斷「不值得當天做」的三項，影響範圍已查清 |

---

# A 會吃資料或會崩（依風險排序，先做這組）

## A-1 `_persist()` 的 Future 鏈一旦拋錯，這次啟動的自動存檔**永久失效**

* **檔案**：`lib/main.dart:430`（鏈在 `:441`）
* **為什麼現在是這樣**：`_pending = _pending.then(...)`。Dart 的 `then` 對已失敗的 Future **跳回呼、原樣往下傳錯**，
  所以鏈上任何一次拋例外，之後每次 `_persist()` 的回呼**不會被執行**，而且靜默。
  用一支小程式實測過：`persist callbacks that actually ran after one throw: 0 / 3`。
  今天沒炸只因為 `GameStorage._write` 把例外全吞了——而 `_notifySaveFailure()`（要拿 `context`／`ScaffoldMessenger`）就在同一條鏈裡。
* **做法**：鏈尾 `catchError`／`whenError` 做隔離，或把 `_notifySaveFailure()` 移到鏈外。一行。
* **驗收**：讓鏈上某步刻意拋 → 再滑一下，確認**仍然寫盤**（比照既有 `_FailingStore` 那支測試的寫法）。

## A-2 `saveGame`／`saveStats` 的玩家 key 在「寫入執行時」才解析

* **檔案**：`lib/game_storage.dart:234`（`_key()`），呼叫點 `:248`（saveGame）／`:319`（saveStats）；`lib/main.dart:163` 的 `await _pending`
* **為什麼現在是這樣**：`_key()` 用 `currentPlayer` 的**活值**。在「Add 欄輸入既有名字」那條路徑上，
  `addPlayer()` 已經先把 `currentPlayer` 改成新人，所以 `await _pending` **保護不到**它要保護的那筆舊玩家盤面。
  `cfb06e1` 加的測試會過，是因為平台寫入約 1–5 ms 而人手更慢——**目前是靠時機正確，不是靠邏輯正確**。
  對照：同檔 `setBestScore` 是 `final key = _key(...)` 在呼叫時**同步**算好，那才是對的寫法。
* **做法**：`_persist()` 一併 captures `final player = storage.currentPlayer`，`saveGame`／`saveStats` 收明確 player 參數。
* **驗收**：一支測試「寫入在飛時切玩家 → A 的盤不會寫進 B 的槽」。

## A-3 `currentPlayer` 是空字串時沒有救回機制

* **檔案**：`lib/game_storage.dart:152`
* **為什麼現在是這樣**：`_prefs.getString(Prefs.currentPlayer) ?? ''`，而 `initState` 只檢查 `loadPlayers().isEmpty`。
  只要 `players` 非空而 `current_player` 不見，app 正常開著、AppBar 名字空白，所有讀寫落在 `saved_game/`
  （key 尾巴一個 `/`）→ **該玩家舊資料永遠讀不到，且毫無提示**。
* **做法**：`if (currentPlayer.isEmpty && loadPlayers().isNotEmpty) currentPlayer = loadPlayers().first;` 一行。

## A-4 `players` JSON 損毀 ⇒ 靜默資料全遺失

* **檔案**：`lib/game_storage.dart:195`（`catch (_) => []`）＋ `initState` 的 `loadPlayers().isEmpty` 判斷
* **為什麼現在是這樣**：`loadPlayers()` 壞掉時回 `[]` → app 認為「還沒有玩家」→ 出「誰在玩」→
  下一次 `addPlayer` 把清單蓋成 `['新名字']` → 舊的 `*/<舊玩家>` **全部永不可達**。
  這正是 `1159a01` 剛在「寫入」那側修掉的「靜默吞掉」，讀取這側還在；而且 `loadSavedGame`／`loadSnapshots`
  都有「損毀只當沒有、其餘照讀」的容錯，`players` 是唯一會造成**全案**歸零的點。
* **做法**：區分「沒有」與「壞掉」——壞掉時**保留原字串不動**，用既有的 `lastError` 那套提示一次，不進「誰在玩」流程。
* **驗收**：`players` 寫成壞 JSON → 不新增玩家、不覆蓋原值。

## A-5 Daily 破局後按 Play Again，會不告而別地開一局 **4×4 普通局**

* **檔案**：遮罩按鈕 `lib/main.dart:1064`；`_initializeGame` 在 `:169`（`mode` 預設 `normal`）
* **為什麼現在是這樣**：`_initializeGame` 用的 `size` 沿用 daily 的 4、也不會去讀 `settings.boardSize`。
  原本玩 8×8 的人會得到一局普通的 4×4，最高分也變成看 4×4 那欄。
  `cfb06e1` 為同一病因在 `_restoreNormal()`（`:495`）修過，**這條路徑漏了**；新測試
  `daily game is always 4x4...` 只驗「進 daily」，沒驗「回普通會恢復 8×8」。
* **做法**：`mode == GameMode.daily` 時 Play Again 改走 `_restoreNormal()`。
* **驗收**：測試「8×8 → Daily → 破局 → Play Again → 仍是 8×8」。

## A-6 快照寫入失敗仍然靜默；`_write` 也不看 `setString` 的回傳值

* **檔案**：`lib/game_storage.dart:166`（`_write`）、`:273`（`saveSnapshots`）、`lib/main.dart:607`（`_saveSnapshot`）
* **為什麼現在是這樣**：`1159a01`（寫入失敗不再靜默）只做了一半——UI 提示只掛在 `_persist` 那條路。
  存快照／刪快照失敗只有 `debugPrint`，**使用者以為存到了**。另外 `SharedPreferences.setString`
  也可能**不拋、直接回傳 `false`**（平台回報失敗），這種情況現在還是靜默成功。
* **做法**：`_write` 把 `false` 也視為失敗；`_saveSnapshot`／刪除後照 `_notifySaveFailure` 那套提示。

---

# B 榜上數字的誠信

## B-1 `stats.gamesPlayed` 會無中生有

* **檔案**：`lib/main.dart:187`（`stats.gamesPlayed++` 在 `_initializeGame` 裡）
* **為什麼現在是這樣**：`_initializeGame` 也會由 **Daily↔Normal 切換**（`:469`／`:495`）、**New Game**（`:735`）、
  **切到一個還沒有存檔的玩家**（`_loadForCurrentPlayer` `:134`）觸發。
  新玩家第一次打開 app、一步沒動，設定頁就顯示「已玩 1 局」；反覆切玩家就一直加。統計是給家人看的，這種數字最傷信任。
* **做法**：把 `++` 從 `_initializeGame` 挪到「真的開了一局」的呼叫點（New Game／Play Again／每日新的一天）。

## B-2 每日排行**只記今天**，且「開了 daily 沒滑」不算玩

* **檔案**：`GameStats.dailyBest`／`lastDailyDate`（`game_storage.dart:113-114`）；`DailyLeaderboardDialog`（`widgets/leaderboards.dart:17`）
* **為什麼現在是這樣**：各一欄 → 一天只容得下一筆，昨天的排名不存在任何地方；且 `lastDailyDate` 只在
  `_afterMove`（`main.dart:322` 附近）更新。
* **做法**：**fun 版就在 class 上標註這個極限就好**，別補歷史。要補就加 `{date: best}` map——
  但那是 E 上線後才值得思考的事，現在做是倒果為因。

---

# C 測試（27 支全綠，覆蓋 72.5%；缺的不是量，是位置）

* **C-1 `lib/widgets/settings_screen.dart` 覆蓋 0%**（51 行，整頁從未渲染）。**最便宜的一筆投資**：
  pump 一次並切一次語言／主題。之後 E 要加的 config 欄位也在這支檔案，先補測試再動它。
* **C-2 `addPlayer` 的正規化零測試**（`game_storage.dart:210`）：`trim` → `runes.take(20)` → 大小寫不分去重
  （保留原 spelling）→ 全空白不建玩家。這批新行為唯一的純函數，也最容易日後被改壞。
  另記一個邊界：`runes.take(20)` 限的是 20 個 **code point**，emoji 會讓字串長度變 40 → 對「限長撐爆佈局」打折。
* **C-3 缺的三條行為測試**：A-5（回普通局仍 8×8）、A-2（寫入在飛時切玩家）、A-4（`players` 損毀）。
* **C-4 慣例（寫下來才守得住）**：每一支 fix commit 都附一支「會復現那個 bug」的測試。
  `cfb06e1` 這樣做了（附 7 支），品質很好——`readBoard` 從 `AnimatedPositioned` 反推棋盤、
  `_FailingStore` 連「UI 已走到第 2 步但 store 裡仍是 moves:0」都驗到了。照這個標準走。

---

# D 體驗與無障礙

* **D-1 鍵盤控制（方向鍵）**——desktop/web **現在完全不能玩**。`_swipe` 已經是單一把 handler，
  只要 `GameScreen` 加 `Focus` + `onKey` 對到 `Direction` 即可。**backlog 裡唯一還值得做的兩個之一。**
* **D-2 Semantics**——方塊與棋盤無語意標籤（螢幕閱讀器讀到的是無意義的 Stack）。
* **D-3 深色模式對比不足**——`Colors.grey[700]`（`main.dart:949, 952, 1080`）實算對比 **3.02:1**，
  低於 AA 正文門檻 4.5。改用 `Theme.of(context).colorScheme.onSurfaceVariant` 這類**已有**的顏色，
  不要自己算色。棋盤／格子也用死死的 `grey[400]/grey[300]`——若「黑底貼一張淺色棋盤」是刻意保留經典配色，
  **寫一行註解**，否則會被當成 bug 回報。
* **D-4 遮罩內容沒做 fit**——`_scrim`（`main.dart:815`）是 `Column`（文字 28px ＋按鈕），
  但同一輪已把按鈕排與 AppBar 標題包了 `FittedBox(scaleDown)`。棋盤是正方形、可能被擠矮，
  `textScale 1.3` ＋較長本地字串有 RenderOverflow 風險，而新測試不會進到 game over → 這條路徑無人守。
* **D-5 web 分享靜默**——`_shareScreenshot()` 在 `kIsWeb` 直接 return，按了完全沒反應。
* **D-6 窄螢幕 ＋系統大字體的實機確認**（原 2026-11-11 那條，保留原文）
  > 那輪 review 報的「按鈕排／AppBar 標題溢出」是 `flutter test` 的 Ahem 字體（每字元 14×14 方塊，
  > 比真機 Roboto 寬一倍）量出來的假數字，真機 Pixel 5／Poco F5 實測不爆。已防呆：四按鈕排與 AppBar 標題
  > `FittedBox(scaleDown)`、分數區 `Expanded`、玩家名 `maxWidth 160` ＋限長 20；測試
  > `layout survives a narrow phone with large system text`（320×640 + textScale 1.3）用的是**測試字體**，
  > 比真機嚴格但不等於真機。
  **做法**：debug 版裝到機型最小的那支（≤360dp），系統字體調到最大，玩一局看 Undo/Redo/New Game/Daily 與
  AppBar 玩家名有沒有黃黑條紋；有的話把 `FittedBox` 那兩處換成可捲的 `SingleChildScrollView`。

---

# E Telegram 家庭排行榜（三隻手機互相比；**不用架站、不用帳號、不用憑證**）

## 為什麼現在是這樣

三台要互相比。現有排行（`widgets/leaderboards.dart:17`）**只在單機**：全部資料在該機的
SharedPreferences，且 app **沒有任何網路依賴**（執行期只有 `flutter / flutter_localizations / intl /
share_plus / shared_preferences`）。原本的「需後端，暫不」是誤判——Telegram 有個匿名公開的讀取口子。

## 已實測的依據（2026-11-11，Linux/aarch64 開發機）

| 檢查 | 結果 |
|---|---|
| `https://t.me/s/<公開頻道>` 匿名讀 | ✅ **HTTP 200**、127 KB、1.3 s，**無 token 無帳號** |
| 連續 4 次抓取 | ✅ 全 200，無 rate-limit、無 403（**僅 4 次、單一 IP，不可外推**） |
| 可抓的結構 | 20 則訊息，每則有 `data-post="頻道/441"`、`tgme_widget_message_text js-message_text" dir="auto"`、`datetime="...+00:00"` |
| 想要 RSS？ | ❌ `?format=rss` 回原 HTML、`.rss` 回 302 → **只能抓 HTML 做 regex** |
| 不存在／被關的頻道 | **HTTP 302，不是 404** → 別用 status code 判好壞，改判「有沒有抓到 `js-message_text` 節點」 |
| Android 網路權限 | ⚠️ **只有 `debug/`、`profile/` 的 manifest 宣告 `INTERNET`，`main/` 沒有** → debug 測得通、**正式版靜默失靈**（教科書級坑） |
| `chat_id` 要不要查 | ❌ **不用**。官方 `sendMessage` 文件：`chat_id` 可用「`@username` 格式的目標 channel」→ 就直接打 `@頻道名` |
| 作廢 token | `@BotFather` → **`/revoke`**，舊 token **立即失效**，bot 與 @username 不變 |

## 架構：**頻道就是資料庫**

開一個「**公開**」頻道，名字取個猜不到的（例 `d2048_hou_ja_7x9q`）。公開 ⇒ 知道 URL 的人都能讀，
這是 obscurity，對分數榜可接受，但**別放任何不想讓陌生人讀的內容**。

* **讀（全自動，零憑證）**：GET `t.me/s/<頻道>` → regex 抓 `js-message_text` 內容 ＋ `datetime` →
  過濾 `d2048 daily <seed> <名字> <分數>` → 餵給**既有的** `DailyLeaderboardDialog`
  （排序、「今天沒玩的排後面」全部已經寫好了）。三台讀同一個頻道 → **每台的榜長一樣**。
* **寫（兩種模式，一份 binary）**：

  | Config | 發分數 |
  |---|---|
  | **留空** | `t.me/share/url?text=...` 深連結，Telegram 分享框已填好 → 按發送（2 下） |
  | **填了** | app 直接 `sendMessage` → **0 下** |

* **白得的紅利**：頻道本身就是歷史資料庫 → **本週／上週榜幾乎免費**、本機不用存 remote 資料（頂多離線快取）、
  榜在 Telegram 裡也同時看得到。**hub（一台當計分板）那個方案已被本條取代。**

## Config：兩個欄位，token **選填**

`SettingsModel` 的註解本來就寫「**唯一寫 prefs 的地方**」→ 加一個 setter 完全符合現有慣例；
`settings_screen.dart` 加兩個 `TextField`（token 那欄 `obscureText: true`）＋一個「測試」按鈕。
**填完立刻打一次 `getMe`**（不需參數）自我測試，成功顯示 bot 名稱、當場告訴你是貼錯——
runtime config 最常見的死法是「配置一直壞卻永遠沒人發現」。
一次性手動：把 bot 加進頻道當管理員並開 **Post Messages**（權限欄位 `can_post_messages`，
沒開的話每個 send 都回 rights error）。

## 必守的三條（洩漏只可能從這裡來）

1. **token 在 URL 的 path 裡**（`api.telegram.org/bot<TOKEN>/sendMessage`）→ **別 log 請求 URL**，
   要 log 就 log `ok`／`description`。這是本設計唯一實際存在的洩漏路徑（不是 git、也不是 APK：
   token 執行期才填，APK 裡根本沒有）。
2. token **不進**任何既有輸出：`_shareText` 的文字、`_shareScreenshot` 的圖、錯誤訊息都不能含它。
3. SharedPreferences 存明碼就好——**不要**引入 secure storage／keychain plugin（原生依賴 → 撞 jni 那條；
   保護對象是「一個只能往你家頻道貼分數的 bot」）。

## 四個會咬人的地方

* **release 要加 `<uses-permission android:name="android.permission.INTERNET"/>` 到 `main/AndroidManifest.xml`**（見上表）。
* **UTC vs 本地日期**：頁面 `datetime` 是 `+00:00`，而 `dailySeedFor()`（`game_storage.dart:12`）用的是**本地日期**
  → 必須先轉本地再比 seed，否則跨午夜那幾小時會掛錯天。
* **`t.me/s/` 的 HTML 沒有文件、隨時會改** → regex 要寬（只抓節點內文字）；抓不到就**顯示上次快取 ＋ `—`，
  永遠不要彈錯誤對話框**。fun 的軟體不該會痛。
* 網路庫用 **`http`（純 Dart、`dart:io` 實作，不是 Flutter plugin）→ 不觸發 CMake／jni**，守得住 aarch64 開發機那條死線。
  裝完照 G-5 那條規則確認 `pubspec.lock` 沒有 `jni`。

## 驗收 / 尚未驗證

* 驗收：`flutter test` 綠、**release** build 裝到機上真的抓得到榜（release 沒 INTERNET 那條只能靠這步抓出来）、
  三台顯示同一份榜、token 留空時仍能用 2 下模式。
* **我沒驗證的**：無 token 所以 `sendMessage`／`getMe`／`@username` 當 chat_id **只有官方文件依據、未實測**；
  「bot 發文後 `t.me/s/` 仍讀得到」也尚未實測；大量抓取会不会被擋不知道（只測了 4 次）；
  你三台是否同一時區（那條 UTC 陷阱會不會真咬到）。

---

# F 明確不做（寫死，別每輪再問一次）

| # | 事項 | 決定與理由 |
|---|---|---|
| **F-1** | `SavedGame`／`BoardSnapshot` class 合併（原 2026-11-10 那條「finding 11 剩半」） | **won't fix**。兩邊 JSON key 不同、合併要一堆 optional、可讀性變差；序列化去重已完成（`_tilesToJson`／`_tilesFromJson`），剩下的純自我修飾、零使用者價值 |
| **F-2** | 計時／解謎模式、成就徽章、音效 | **不做**。家庭版 2048，不會有人用。backlog 裡只剩 D-1 鍵盤 ＋ D-2 無障礙值得做 |
| **F-3** | 全球排行榜／雲端同步（需後端） | **被 E 取代**（E 無後端、無憑證）。真要做也絕不是 Firebase/Supabase：原生依賴 → aarch64 開發機 debug build 當場死，且 key 得編進 public repo 的 app |
| **F-4** | 反作弊（undo 可刷分、seed 只保證同開局） | **只做一句 l10n**：榜標題寫「家庭榜（誠信制）」。`_historyLimit=200` 步 undo 且 `dailyBest` 取 max ⇒ 滑錯就 Undo、零成本；跨機之後沒人看著 → 就讓它在榜上註明 |
| **F-5** | secure storage／keychain | 見 E「必守的三條」第 3 點 |
| **F-6** | 跨機的「一台當計分板（hub）」方案 | **被 E 取代**：讀取免憑證，所以不需要一台專門當榜、也不需要任何人記得貼 |
| **F-7** | release signing key 備份 | **非專案問題**（release 在另一台 build，本機只 dev）。但記著：`~/dennys/AGENTS.md` 講的 `~/backups/dNeko-signing-20261109/` **路徑已不存在**，而 d2048 `README` 說 keystore「與 dNeko／dHealth 共用」、dHealth 自己的說明卻說它有獨立 `dhealth.keystore` → 三處矛盾，**要修是改文件，不是改碼** |
| **F-8** | `tileColor(0)` 的行為 | **不動**。`case 0:` 被刪後 `tileColor(0)` 會落到 `default` 回傳紅色；今天沒人會傳 0（背景格是另外畫的），所以**不是 bug**，但那 2 行刪除換到的價值是 0。真想動就恢復 `case 0` |

---

# G 收尾 nit（撿起來就順手）

* **G-1** `.gitignore` 加 `coverage/`——CI 现已 `flutter test --coverage`，本機跑一次就多一個未追蹤目錄
  （已 `git check-ignore` 確認目前**沒**被 ignore）。
* **G-2** `android/app/build.gradle.kts:22` 還留著 Flutter 範本的 `// TODO: Specify your own unique Application ID`，
  但 `applicationId` 早就對了 → 純噪音。
* **G-3** `README.md` Features（`:5`）停在上一代：per-player profiles、Daily、家庭排行、本地排行、分享、
  里程碑慶祝**一個都沒寫**。順帶補一句「正式版也含 `shared_preferences_android 2.4.28` ＋
  `path_provider_android 2.2.23` 這兩個 pin 舊版」（見下）。
* **G-4** `pubspec.yaml:19` 的 `version: 1.0.0+1` 從未 bump。CI 每個 commit 都出 artefact 卻只能靠 sha 分辨；
  裝在手機上無法確認自己是哪版。lazy 版就是 commit 一個 `1.0.0+2` ＋ CHANGELOG 一行，**別加 `package_info_plus`**。
* **G-5** `~/dennys/AGENTS.md`（三案共同）三處要更新：
  ① `~/backups/...` 路徑已不存在；② `d2048 ≈83 MiB` 過時（實測 **110 MiB**）；
  ③ jni 那條補一句結論：**唯一解是 pin 版本**（NDK issue **#1752** 到 2026-01-25 仍 open、
  NDK r30 下載頁只有「Linux 64-bit (x86)」），**規則 = `pub upgrade` 前確認 `pubspec.lock` 沒有 `jni`／`jni_flutter`**
  （`shared_preferences_android 2.5.x`、`path_provider_android 2.3.x` 都是會把它拉回來的前例）。

---

# H 今日修復（A-1…A-6）留下的三項（2026-11-11 復盤）

都是當時判斷「今天不做」的，不是模糊擔憂：每項都實際跑過實驗確認影響範圍。

* **H-1** `_persist()` capture 了棋盤，卻把**活的** `GameStats` 交進鏈（`lib/main.dart:443-460`）。
  * **為什麼現在是這樣**：`game` 是呼叫當下建好的快照，`stats` 卻是同一個可變物件，`toJson()`
    在回呼執行當時才讀。鏈可能晚幾個 microtask 才跑（平台寫入 1–5 ms，8×8 長局或磁碟將滿時更慢），
    中間插入 `_undo()` 就會把 `stats.totalMerges`／`wins` 回滾（見 `_restoreSnapshot`）→
    落盤的兩把 key 變成「回滾後的統計 + 回滾前的盤」。
  * **代價**：不會崩、不會丟進度，只是統計數字偶爾跟盤面對不上。正常滑動速度打不滿這個窗口。
  * **做法**：要嘛 `saveStats(stats.copy(), player)` + 一個 6 行的 copy 方法；**要嘛認了**，
    在 `_persist` 寫一句「stats 是活的，落盤值是執行當下的」。**我傾向後者**（6 行換來的是沒人會看見的精度）。

* **H-2** 測試裡四支幾乎一樣的 store（`test/widget_test.dart:17-68`：`_FailingStore`／`_ThrowOnceStore`／
  `_FalseStore`／`_GatedStore`，共 52 行）。
  * **做法**：收成一支 `_BadStore(super.data, {this.throwOnCall = -1, this.returnValue = true, this.gate})`，
    `setValue` 五行搞定，約 **省 38 行**。
  * **現在別收**：類別名就是把「模擬哪種失敗」寫在測試名裡，收起來後意圖要靠參數名撐。
    **觸發條件 = 出現第五支時再收。**

* **H-3** 玩家清單損毀 **+** 之後又真的寫不進去 → 只有啟動那一句「清單壞掉」，後來的存檔失敗
  **半句都沒有**（`lib/main.dart:466-481`，`shortcut:` 已標那條）。
  * **為什麼現在是這樣**：`playersCorrupted` 是永久狀態，而提示只有一個 `_warnedSaveFailure` 旗標；
    啟動噴過一次之後，`_notifySaveFailure` 的早回（`lastError == null && !playersCorrupted`）永遠不重設它
    → 後來的寫入失敗被一起壓住。
  * **做法**（約 3–4 行）：`lastError` 只記**寫入**失敗（照它自己的文件），`loadPlayers()` 不再寫
    `lastError`（`game_storage.dart:218`）；提示拆兩個旗標（`_warnedSaveFailure`／`_warnedListBroken`），
    各管各的重設，寫入失敗那句優先。
  * **坑**：**別用「`lastError != null` 就講寫入失敗」偷懶判別** —— `loadPlayers()` 也會寫 `lastError`，
    那樣一判就把「清單壞掉」講成「存不進去」。先把它拿乾淨，判別才會對。

---

# 已結案（記錄，別再開）

* **jni on aarch64 主機**：pin（`shared_preferences_android 2.4.28` ＋ `path_provider_android 2.2.23`）
  就是**唯一解**，不是權宜之計。HEAD 實測：`flutter build apk --debug --target-platform android-arm64`
  **通過**、3.4 s、110 MiB，`pubspec.lock` **無 jni**（share_plus 13.3.1 這版不吃 jni）。規則見 G-5。
* **Codecov**：`CODECOV_TOKEN` 已設 → 原 review 的 P-7 不成立。（`flutter test --coverage` 已補，lcov 不再空上傳。）
* **`dependency_overrides` 維持 committed 全域**：d2048 是唯一做完 Built-in Kotlin 的案，
  `shared_preferences_android 2.4.8` 會在 configuration 就被 AGP 9 擋 → **不是純主機限制**，
  搬進 gitignored 反而讓 CI 直接紅。只在 README 標一句（G-3）。
* **Built-in Kotlin 遷移**：已完成；證據（`PROBE KGP_APPLIED` 與「AGP 不升 9.5」的決定）在
  `CHANGELOG.md:160-190`——原 TODO 那 60 行背景與之重複，故刪。
* **詳細 review 依據**：`review.md`（2026-11-11，read-only，一個檔案都沒改）。
  實測过：`analyze` 全淨、`flutter test` 27/27、coverage 72.5%、`gen-l10n` 零 diff、4 支 arb 各 51 key 無脫節、`git status` 乾淨。
