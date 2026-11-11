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
- Daily challenge with a family leaderboard via a public Telegram channel (optional)
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

## Telegram family leaderboard

Share your daily challenge score to a public Telegram channel and see
everyone's scores for today's board.

### Setup

1. **Create a public channel** in Telegram and give it a username, e.g. `@my_family_2048`.
   The leaderboard reads the public channel page, so it must be public.
2. **Optional, for sending from the app:** create a bot with
   [@BotFather](https://t.me/BotFather) (`/newbot`) and copy its token.
   Add the bot to the channel as an administrator with the *Post Messages*
   permission.
3. In the app, open **Settings → Telegram family leaderboard** and enter:
   - **Channel**: the channel username (`@my_family_2048`, or the bare name).
   - **Bot token** (optional): the token from BotFather.
4. Tap **Test** to check the channel (and the token, if given).

The token is stored in plain text in the app's local preferences on the device,
and is only sent to `api.telegram.org`.

### Usage

- **Send a score:** finish a daily challenge (`Daily`), then choose
  **Send to Telegram** in the share dialog. The app posts a message in the form
  `d2048 daily <yyyymmdd> <name> <score>`.
  - With a bot token, the message is posted directly to the channel.
  - Without a token, the system share sheet opens with the score text, so you can
    paste it into the channel yourself.
  - Only today's daily score can be sent, and only after you have played it.
- **View the leaderboard:** open the daily leaderboard. It merges your local
  scores with the channel's scores for today. If the network is unavailable, the
  last cached channel scores are shown.

### Limitations

- The app reads only the channel's most recent ~20 messages, so older scores
  can drop off the leaderboard.
- Reading relies on Telegram's public web page (`t.me/s/<channel>`). If Telegram
  changes that page layout, reading scores may stop working until the app is
  updated.
- The daily date comes from the message text (the sender's local date), so
  players in different time zones may see different days near midnight.
- Release builds need network access: the Android `INTERNET` permission is
  declared in the manifest.

## Records

In-progress work: [TODO.md](TODO.md). Completed work: [CHANGELOG.md](CHANGELOG.md).