# d2048

[![GitHub Actions](https://github.com/dennys/d2048/actions/workflows/github_action.yaml/badge.svg)](https://github.com/dennys/d2048/actions/workflows/github_action.yaml)
[![codecov](https://codecov.io/gh/dennys/d2048/graph/badge.svg?token=AoyO8vBWZX)](https://codecov.io/gh/dennys/d2048)

A 2048 puzzle game built with Flutter. Swipe to slide and merge tiles.

## Features

- Swipe in four directions to move and merge tiles
- Score, best score (per board size), move counter
- Undo / redo
- Board sizes 4×4 to 8×8
- Auto-save and resume
- Named board snapshots (save / load / delete)
- Win detection (2048) with "keep playing"
- Haptics on merge (optional)
- Lifetime stats (games, wins, max tile, merges)
- Localization: English, 繁體中文, 简体中文
- Light / dark theme

## Run

```
flutter pub get
flutter run
```

## Build (Android)

arm64-only APK (a universal APK would bundle two extra engine copies). The APK
contains only the arm64-v8a engine, so it will not launch on x86-64 emulators
or x86 devices — use an arm64 emulator or a real device.

```bash
flutter build apk --debug   --target-platform android-arm64
flutter build apk --release --target-platform android-arm64
```

CI (`.github/workflows/github_action.yaml`) runs analyze, tests, and builds
debug + release APKs.

### Signing

Without a keystore, the release APK falls back to the debug signature. Each CI
runner generates its own debug key, so signatures differ per build and Android
refuses in-place upgrades; the artifact is named `-debugsigned` to make this
explicit. To sign properly, provide `android/app/{d2048.keystore,key.properties}`
or the CI secrets `KEYSTORE_B64` / `KEY_PROPERTIES` (shared with dNeko / dHealth).
Use one keystore for release — rotating it later breaks in-place upgrades.

## Records

In-progress work: [TODO.md](TODO.md). Completed work: [CHANGELOG.md](CHANGELOG.md).