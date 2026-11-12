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
- Family leaderboard of all finished games via a public Telegram channel (optional)
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

Every finished game is posted to a public Telegram channel, and the
leaderboard lists all games in the channel (name, date, board size, score),
newest first.

### Setup

1. **Create a public channel** in Telegram and give it a username, e.g. `@my_family_2048`.
   The leaderboard reads the public channel page, so it must be public.
2. **Optional, for automatic sending:** create a bot with
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

- **Send automatically:** when a game ends and a bot token is set, the game is
  posted to the channel. Each game has a unique id, so re-sending is safe and
  duplicates are ignored. Messages have the form
  `d2048 v2 <id> <yyyymmdd> <size> <name> <score>`.
- **Send manually:** **Send to Telegram** in the share dialog re-sends the most
  recently finished game. Without a token, it opens the system share sheet
  instead, so you can paste the text into the channel yourself.
- Failed sends show an error message and are not retried.
- **View the leaderboard:** tap the leaderboard button. It shows the channel's
  games. If the network is unavailable, the last cached games are shown.

### Limitations

- The app reads only the channel's most recent ~20 messages, so older games
  can drop off the leaderboard.
- Reading relies on Telegram's public web page (`t.me/s/<channel>`). If Telegram
  changes that page layout, reading games may stop working until the app is
  updated.
- Names are shown in lowercase, and each game is listed separately (no merging
  of a player's games).
- The game date is the local date when the game ended, so players in different
  time zones may see different dates near midnight.
- Release builds need network access: the Android `INTERNET` permission is
  declared in the manifest.

## Records

In-progress work: [TODO.md](TODO.md). Completed work: [CHANGELOG.md](CHANGELOG.md).