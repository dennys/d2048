# d2048 code review — 2026-11-10

Read-only review of `main` + working tree. No project file was changed by the review.
Verification was run in a throwaway copy at `/tmp/d2048-probe` (existing 8 tests + 7 probe tests).

## What this repo does

Flutter (Dart) 2048 puzzle game: swipe four directions to slide and merge tiles, with score,
undo/redo, auto-save to `shared_preferences`, named board snapshots, board size 4–8, zh/en localization.
All game logic sits in `lib/main.dart` (753 lines).

**Load assumed:** one person playing on one device. No server, no concurrent users.

---

## Must fix

### 1. Swiping right or down reverses the tile order — 2 of 4 directions play wrong

`lib/main.dart:L170-182`, `lib/main.dart:L234-274`

- **What this is:** `_move` collects each row/column left→right, `_applyLine` packs from slot 0, and `_target` mirrors the slot for right/down.
- **Problem:** the packing edge and the tile order disagree. Measured: row `2@col0, 4@col3` swiped right gives `2→col3, 4→col2`; correct 2048 is `2→col2, 4→col3` — the tiles pass through each other. Same for down (`2@row0, 4@row3` → `2@row3, 4@row2`). Merge case `[2,4,4]` right gives `8@col2, 2@col3`, should be `8@col3, 2@col1`.
- **Fix:** collect the line from the target edge — loop `j` from `size-1` down to `0` when direction is right/down. One loop bound, no new helper.
- **If we skip it:** half the game is unwinnable; "right/down feels broken", 2048 unreachable that way.

### 2. Reopening the app reuses saved tile ids → duplicate animation keys

`lib/main.dart:L85`, `L121-133`, `L135`

- **What this is:** `_nextId` restarts at 1 on every app launch, while `_restoreSaved` keeps the ids stored in the save file (also `_loadSnapshot`, `L296`).
- **Problem:** probe result: save file holds ids `[1,2]`; after relaunch the next spawned tile gets id `1` again. The `Stack` then has two `ValueKey(1)` children and Flutter throws `Duplicate keys found.` — red screen in debug, and in release the slide animation starts from the wrong tile, which is exactly what the `key: ValueKey(t.id)` comment (`L285-290`) was written to prevent.
- **Fix:** after `_restoreSaved` / `_loadSnapshot`, set `_nextId = (highest stored id) + 1`. One line in each restore path.
- **If we skip it:** every debug run after a resume logs assertion errors; released builds animate wrong.

### 3. Undoing the winning move leaves the "You win!" wall up and locks input

`lib/main.dart:L292-300`, `L406`

- **What this is:** `_undo` / `_restoreSnapshot` restore tiles and score but never reset `won` / `keepPlaying`.
- **Problem:** probe: win, press Undo → board is back to two `1024` tiles, `You win!` overlay still shown, and `_swipe` returns early on `won && !keepPlaying`, so no swipe works until "Keep playing" is pressed.
- **Fix:** in `_restoreSnapshot`, recompute `won` / `keepPlaying` from the restored tiles (`won = tiles.any((t) => t.value >= 2048)`).
- **If we skip it:** the game looks playable but is frozen.

### 4. An upgraded app silently throws away the game in progress

`lib/game_storage.dart:L38-51`, `lib/main.dart:L92-97`

- **What this is:** `SavedGame.fromJson` casts every field hard (`json['undoCount'] as int`); there is no schema marker.
- **Problem:** a save written by an older/newer build (e.g. one with no `undoCount` key — that field was added later, commit `3160fe2`) throws, `loadSavedGame` catches and returns `null`, `initState` then runs `_initializeGame()` → `_persist()` overwrites the old save. The player loses the board with no message.
- **Fix:** default the optional ints (`json['moves'] as int? ?? 0`, same for `undoCount`, `boardSize`); keep the hard cast only for `tiles` / `score`.
- **If we skip it:** every save-format change is a silent data-loss event on user devices.

### 5. The whole feature set exists only in the working tree

`git status`: 8 modified, 7 untracked files, 1143 insertions

- **What this is:** `lib/main.dart`, `lib/game_storage.dart`, `lib/settings_*`, `lib/widgets/`, `lib/l10n/`, `test/widget_test.dart` are uncommitted; `origin/main` still has a `main.dart` with **no persistence at all**.
- **Problem:** one `git clean -fd` or `git checkout -- lib` deletes the settings, snapshot, stats and undo work; CI and any clone build a different, older app than the one under review.
- **Fix:** commit and push (also `l10n.yaml` and `lib/generated/`, if CI stops regenerating them).
- **If we skip it:** unbacked work; the green CI badge describes code that is no longer there.

---

## Should fix

### 6. No test touches right or down — that is why finding 1 shipped

`test/widget_test.dart:L104-140`

- **What this is:** all four game tests swipe left or up only.
- **Problem:** the merge-rule test also counts the still-rendered covered tile (`tiles` keeps `removed` tiles until the next move, `main.dart:L159`), so it passes by coincidence when the debris value equals the spawned value.
- **Fix:** add one right-swipe case with row `[2,4,4]`; filter `t.removed` out of `readBoard`.
- **If we skip it:** the two broken directions stay untested.

### 7. Undo does not roll back the counters

`lib/main.dart:L292-300`

- **What this is:** `_undo` restores tiles and score only.
- **Problem:** probe: two moves then two undos persist `moves: 2` and `stats.totalMerges: 1`; an undone win still leaves `stats.wins: 1` and `best` at the undone score. Undo ×N of a whole game leaves a save file reading "16 moves, score 0".
- **Fix:** put `moves`, `won`, `keepPlaying` (and `totalMerges` / `wins` if you want them honest) into `_Snapshot`; it already carries `tiles` and `score`.
- **If we skip it:** the stats screen and the resume file drift away from the board.

### 8. arm64-only APK will not start on an x86-64 device or the standard Android emulator

`android/app/build.gradle.kts:L30-31`

- **What this is:** `ndk.abiFilters += listOf("arm64-v8a")` ships one engine library.
- **Problem:** install it on the x86-64 emulator (Android Studio default) or a Play x86 device → no matching architecture, crash at launch.
- **Fix:** nothing if only arm64 phones are targeted — then state it in the README run section, which today documents only the CI build flag.
- **If we skip it:** "install works, app dies at once" reports from x86 testers.

### 9. Release APK is silently debug-signed when CI secrets are absent

`android/app/build.gradle.kts:L57`, `.github/workflows/github_action.yaml:L88-104`

- **What this is:** `signingConfigs.findByName("release") ?: getByName("debug")`.
- **Problem:** each runner regenerates its debug key, so two CI APKs of the same version have different signatures and Android refuses the in-place upgrade; the workflow only prints a `::warning::`.
- **Fix:** `exit 1` instead of the warning for a release/shipping build, or name the artifact `-debugsigned`.
- **If we skip it:** someone installs a CI artifact and cannot update it.

### 10. The burned shared keystore password is still printed in a public file

`.github/workflows/github_action.yaml:L102`

- **What this is:** the guard compares against the literal `iu6cv1o8k5b7re0d`, introduced in commit `005afdb`.
- **Problem:** README (`L41-43`) says d2048 / dNeko / dHealth share one keystore set, so a public literal names the password that must be rotated on the other two; d2048 has no `android/app/*.keystore` locally, so it cannot be checked from here.
- **Fix:** move the old value into workflow secrets (or compare a hash), and confirm dNeko / dHealth rotated too.
- **If we skip it:** a still-live signing key on the sibling apps is forgeable by anyone who reads this repo.

### 11. Dead Kotlin class still shipped

`android/app/src/main/kotlin/com/example/d2048/MainActivity.kt`

- **What this is:** the pre-rename `MainActivity` from commit `8424a8e`, still tracked; the manifest points at `com.dennys.d2048`.
- **Problem:** it compiles into the APK as an unused `FlutterActivity` subclass; a later `flutter create` / migrate run can regenerate it and someone fixing a build error may edit the wrong file.
- **Fix:** delete the file (and its folder). One deletion, nothing else changes.
- **If we skip it:** two identical-looking entry points in the tree.

### 12. Save writes are fire-and-forget with no error path

`lib/main.dart:L310-320`, `lib/game_storage.dart:L104-110`

- **What this is:** `_persist()` calls `saveGame` / `saveSnapshots` without awaiting or catching.
- **Problem:** if a prefs write throws (quota, disk) it becomes an uncaught async error and the last moves are lost silently; `_showSnapshots`'s `onDelete` (`main.dart:L242-247`) does the same for the snapshot list.
- **Fix:** one `.catchError` / `try` in `GameStorage`'s three setters.
- **If we skip it:** a failed write is invisible until the player notices lost progress.

---

## Nice to have

### 13. Tiles above 2048 all paint the same red

`lib/tile_style.dart:L30` — 4096 and 8192 look identical; one extra case or a modulo ramp.

### 14. `Locale('zh', 'Hans')` sets the *region* subtag, not the script

`lib/settings_model.dart:L60-72` — it matches the generated `Locale.fromSubtags(scriptCode: 'Hant')` only because both stringise to `zh_Hant`; `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')` says what is meant.

### 15. `main()` and `SettingsModel.load()` both call `SharedPreferences.getInstance()`

`lib/main.dart:L18-19` — same cached instance; the first call only exists to hand `prefs` to `Game2048App`.

### 16. `assets/icon/app_icon.png` and `assets/icon/d2048.png` are referenced nowhere

Not in `pubspec.yaml`'s `flutter:` section and not by the platform icon sets.

---

## Verdict

Fix 1, 2, 3 first (two of four directions are wrong, resuming a game breaks the animation keys, undo can lock the board), then commit the work in 5.

Lean: `-7` lines, `-2` files possible (delete the duplicate `MainActivity.kt`, the two unused icon assets, one redundant `getInstance`).

Not checked: iOS / macOS / Linux / Windows build paths, real-device installs, CI run logs (the API only showed `status: completed`), Play Store metadata, rendered zh text, and every non-`lib/` platform project.
