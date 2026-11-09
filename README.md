# d2048

2048 puzzle game built with Flutter. Drag/swipe to slide and merge tiles.

## Features

1. Swipe (or drag) in four directions to move and merge tiles
2. Score tracking
3. New Game
4. Undo (rollback) the last move

## Run

```
flutter pub get
flutter run
```

## 建置 APK

只出 arm64（通用 APK 會多塞兩份引擎庫）；CI（`.github/workflows/github_action.yaml`）跑 analyze / test / debug+release APK。

| 機器 | debug | release |
|---|---|---|
| Windows（x86-64） | ✅ | ✅ |
| GitHub Actions（ubuntu-latest，x86-64） | ✅ | ✅ artifacts |
| Linux/aarch64（如 dgx1） | ✅ 實測 77 MiB | ❌ 沒有 linux-arm64 的 AOT `gen_snapshot`（Google 只發 x86-64 host 版；是主機平台限制，與本專案無關） |

```bash
flutter build apk --debug  --target-platform android-arm64
flutter build apk --release --target-platform android-arm64
```

### 簽名

模板預設是 debug 簽章，而每台 CI runner 的 debug key 都是現生的 → 每版簽名不同，只能砍掉重裝。
`android/app/build.gradle.kts` 已改成與 dNeko／dHealth 同一套：有 `android/app/{d2048.keystore,key.properties}`
（或 CI secrets `KEYSTORE_B64` / `KEY_PROPERTIES`）就用固定鑰，沒有就退回 debug 簽章（fork 不会紅）。
要正式發版時再生一把 keystore（全案只准一把，換鑰 = 舊安裝無法覆蓋升級），指令與注意事項見 dNeko／dHealth 的 README。

