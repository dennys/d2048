# d2048 CHANGELOG

已完成事项的归档区（把 TODO.md 瘦成「只剩還沒做的事」）。
**`git log` 才是權威**，這裡只是保留當時的判斷與驗收數字，方便日後回溯「為什麼现在是這樣」。
新的完成紀錄加在最上面。

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

