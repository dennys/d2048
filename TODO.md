# d2048 TODO

慣例：一個待辦一段，寫清「檔案:行」與「為什麼现在是這樣」，做完就刪掉這條。

---

## 2026-11-09 待辦：遷移到 Flutter Built-in Kotlin（d2048 / dNeko / dHealth 三案共同）

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

**沒人試過**，所以先在最簡單的 d2048（只有 `lib/main.dart` 470 行、**零 native plugin**）試通，再複製到 dNeko／dHealth
（dNeko 的 `packages/flutter_overlay_window` 是本地 fork，得自己改；dHealth 十來個原生插件——
awesome_notifications／workmanager／health／permission_handler／file_picker／share_plus——只能等上游）。
方向（**尚未驗證**，以官方 guide 為準）：`android.builtInKotlin=true` + 拿掉 app 的 KGP plugin 行。
驗收至少要有：`flutter analyze`、`flutter test`、`flutter build apk --debug --target-platform android-arm64`，
加一次 **release**（AOT 只能在 x86-64 機器或 CI 驗，本機 dgx1 出不了 release）。

---
