# d2048 TODO

慣例：一個待辦一段，寫清「檔案:行」與「為什麼现在是這樣」；**做完就搬到 `CHANGELOG.md`**（`git log` 才是權威）。

---
## 2026-11-11 待辦：窄螢幕 + 系統大字體的實機確認

- **為什麼現在是這樣**：那輪 review 報的「按鈕排／AppBar 標題溢出」是 `flutter test` 的 Ahem 字體（每字元 14×14 方塊，比真機 Roboto 寬一倍）量出來的假數字，真機 Pixel 5／Poco F5 實測不爆。已防呆：四按鈕排與 AppBar 標題 `FittedBox(scaleDown)`、分數區 `Expanded`、玩家名 `maxWidth 160` + 限長 20；測試 `layout survives a narrow phone with large system text`（320×640 + textScale 1.3）用的是**測試字體**，比真機嚴格但不等於真機。
- **做法**：debug 版裝到機型最小的那支（≤360dp），系統字體調到最大，玩一局看 Undo/Redo/New Game/Daily 與 AppBar 玩家名有沒有黃黑條紋；有的話把 `FittedBox` 那兩處換成可捲的 `SingleChildScrollView`。

---
## 2026-11-10 待辦：SavedGame／BoardSnapshot 合併（REVIEW.md finding 11 剩半）

> tile 序列化去重已完成（`lib/game_storage.dart:18,22` 的 `_tilesToJson`/`_tilesFromJson` + `lib/main.dart` 的 `_tileData()`，見 CHANGELOG 2026-11-10 review 修正）；剩下的是把兩個 class 併成一個。

- **為什麼現在是這樣**：兩 class 的 JSON 格式不同（`SavedGame`（`game_storage.dart:33`）有 moves/undoCount/keepPlaying/seed，`BoardSnapshot`（`game_storage.dart:75`）有 name/savedAt），合併要一堆 optional 欄位，風險大、可讀性反而變差，所以先只做序列化 helper。
- **做法**：併成一個 class（optional 欄位），保留現有 JSON keys 讓舊存檔照讀；驗收 `flutter test`（migration／snapshot／daily 測試）。

---
## 2026-11-10 待辦：新功能 backlog（re-review 後討論）

> 依 effort/回報排序，★ = 建議先做。場景：主要我和家人幾個人用，可能同一支手機多人共用。
> 2026-11-10 已完成並搬到 CHANGELOG：Per-player Profiles、家庭 Daily Leaderboard、里程碑慶祝、分享成績、本地排行榜。

- **★ 鍵盤控制**——方向鍵（desktop/web）。落點：`GameScreen` 加 `Focus` + `onKey` 映射到 `_swipe` 的 Direction。
- **音效**——合併/過關音效（震動已有）。需 asset + 播放（`SystemSound` 或 `audioplayers`）。
- **遊戲模式**——計時模式（60 秒衝分）、解謎模式（固定 board、最少步數）。
- **成就/徽章**——「到達 4096」「合併 100 次」「連玩 7 天」。
- **遊戲歷史 / 連玩天數**——過去幾局 score/moves 列表；consecutive days。
- **無障礙**——tile 加 semantic label（螢幕閱讀器）；高對比/大字。
- **暫不（需後端）**——全球排行榜、雲端同步。

---

## 2026-11-09 待辦：遷移到 Flutter Built-in Kotlin（d2048 / dNeko / dHealth 三案共同）

> **狀態（2026-11-09）**：d2048 **已遷移完成**，本機 debug 驗过（看本節末「d2048 已做」）。
> dNeko／dHealth 仍待比照，但得等各自的原生插件就緒（d2048 零插件，條件最好）。

每次 Gradle build 都會噴：

```
WARNING: Your Android app project: app located at: .../android/app/build.gradle.kts
applies the Kotlin Gradle Plugin, which will cause build failures in future versions of Flutter.
Please migrate your app to Built-in Kotlin using this guide:
https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
```

**現在為什麼還跑得動**：三案的 `android/gradle.properties` 都把開關壓關了（是 Flutter migrator 自動加的）：

```properties
android.builtInKotlin=false     # d2048 第 7 行、dNeko 第 61 行、dHealth 第 11 行
android.newDsl=false            # d2048 第 9 行、dNeko 第 63 行、dHealth 第 13 行
```

搭配 `android/settings.gradle.kts` 的 `id("org.jetbrains.kotlin.android") version "2.4.0" apply false`
與 `android/app/build.gradle.kts` 的 `id("org.jetbrains.kotlin.android")` + `kotlin { compilerOptions { jvmTarget = JVM_17 } }`。

**風險**：這是「未來會變成 build 失敗」的警告，不是 lint 噪音。等它真的變成 error 時，三案都會被卡死在
「不能升 Flutter 新版」的狀態，到時候是被動改，很貴。現在是主動改，便宜。

**根因不是 Gradle 9，是 AGP 9**（Android Gradle Plugin 9.0）：AGP 9 把「套 `org.jetbrains.kotlin.android`（KGP）
來編 Kotlin」這條路**移除**，改成 AGP 自己內建 Kotlin 編譯（預設開）。Google 的動機：build 檔更簡單、
不必再處理 AGP↔KGP 的版本相容矩陣（developer.android.com/build/migrate-to-built-in-kotlin）。
代價是 Kotlin 編譯器變成 **AGP 內附**，版本不再由你選——已有 AGP 內附 2.2.10 低於 Flutter 要求下限 2.2.20
→ 在 configuration 階段就被 FGP 擋下的案例（flutter#192167）。
Flutter 3.44 只是加了**暫時的逃生口** `android.builtInKotlin=false`（flutter#183909），migrator 自動把它寫進
gradle.properties —— 就是上面那兩行「added automatically by Flutter migrator」註解的由來；逃生口拆掉
就是警告變 error。`android.newDsl` 是同期的另一件事（AGP 舊 DSL 型別），雨個 flag 可分開翻。

**前提**：自己的 app 與**每一個 plugin** 都要先就緒（flutter#181383），否則翻完 flag 就 build 不起來。
版版下限我們都過了：遷移要 Flutter 3.44+、開 `builtInKotlin=true` 要 Flutter 3.47+（本機 3.47.9）、AGP 9+（三案 9.1.0）。
注意 settings 裡 KGP 的 `version "2.4.0"` 那一行**先留著**（只删 app 的 `id("org.jetbrains.kotlin.android")`），
等所有插件都遷移完再清；`kotlin { compilerOptions { jvmTarget } }` 已經是新寫法，不用動。

**沒人試過**，所以先在最簡單的 d2048（只有 `lib/main.dart`、**零 native plugin**）試通，再複製到 dNeko／dHealth
（dNeko 的 `packages/flutter_overlay_window` 是本地 fork，得自己改；dHealth 十來個原生插件——
awesome_notifications／workmanager／health／permission_handler／file_picker／share_plus——只能等上游）。
方向（**尚未驗證**，以官方 guide 為準）：`android.builtInKotlin=true` + 拿掉 app 的 KGP plugin 行。
驗收至少要有：`flutter analyze`、`flutter test`、`flutter build apk --debug --target-platform android-arm64`，
加一次 **release**（AOT 只能在 x86-64 機器或 CI 驗；aarch64 主機出不了 linux-arm64 release，見 `~/dennys/AGENTS.md`）。

> d2048 端的遷移已完成、以及「AGP 不升 9.5」的決定與證據，都搬到 `CHANGELOG.md`。

