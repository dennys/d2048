# REVIEW.md — d2048 (read-only review, 2026-11-10, HEAD a675834)

No code was changed. Findings were checked by reading the code and by running
`flutter analyze` (clean), `flutter test` (17/17 green), and throw-away probe tests
run in a scratch copy under `/tmp/d2048-probe` (deleted after; nothing added here).

## What this repo does

A Flutter 2048 game: swipe to slide and merge tiles, with undo/redo, named board
snapshots, per-player save files, a daily (same-puzzle-for-the-family) mode, leaderboards,
stats and share. Load assumed: one family, a handful of players sharing one phone,
a few hundred moves per sitting — not a server, not thousands of users. The
game engine itself (move/merge/undo/serialize) is in good shape; the weak spots
are all in the newer dialog screens.

## Must fix

1. **The Leaderboard dialog throws during layout** (`lib/widgets/leaderboards.dart:78-95`)
   - **What this is:** The "Leaderboard" button in the app bar opens a dialog with a
     row of five board-size radio buttons (`4×4 … 8×8`).
   - **Problem:** Five `RadioListTile`s sit in a `Row` with no width limit. A horizontal
     `Row` gives its non-flex children infinite width, and Flutter asserts:
     `BoxConstraints forces an infinite width` — reproduced by tapping the leaderboard
     button in a probe test. In debug that is a red-screen exception; in release the
     assert is compiled out, so the row renders broken or blank.
   - **Fix:** Wrap each option in `Expanded(child: RadioListTile<int>(…))` so each gets
     one fifth of the dialog. Verified in the scratch copy: the probe test then passes.
   - **If we skip it:** The feature added in the last commit does not work at all.

2. **The leaderboard's board-size picker never sticks** (`lib/widgets/leaderboards.dart:65-84`)
   - **What this is:** That dialog lets you pick which board size's scores you want to see.
   - **Problem:** `var size = initialSize;` is declared *inside* the `StatefulBuilder`
     builder (line 65), so every re-render re-creates it from `initialSize`. Picking
     `6×6` re-renders the list for the size you started on. Probe test: best scores
     `{4:100, 6:7}`, pick 6×6, the list still shows 100.
   - **Fix:** Move that one line above `return StatefulBuilder(...)`. Verified: after the
     move the list shows the 6×6 score.
   - **If we skip it:** The picker looks interactive but always shows the same column.

3. **"New Game" does nothing if you pick the size you already play** (`lib/main.dart:611-633`)
   - **What this is:** New Game opens a dialog asking the board size, then restarts.
   - **Problem:** `RadioGroup.onChanged` fires only when the selection *changes*, so
     tapping the current size (line 612 `groupValue: size`) pops nothing: the modal just
     stays open and no game starts. Probe test confirms the dialog is still open and
     no new game was created. Only Cancel gets you out.
   - **Fix:** Pass `groupValue: null` so every tap counts as a change (one word, costs
     the "current size" highlight), or add an explicit confirm action next to Cancel.
   - **If we skip it:** Four of the five buttons work, the fifth looks dead.

## Should fix

4. **No way back to your normal game after playing the Daily one** (`lib/main.dart:419-431,118`)
   - **What this is:** Normal and Daily games are two save slots
     (`saved_game/<player>` and `saved_game_daily/<player>`), but the screen shows one at a
     a time and Daily replaces it in memory.
   - **Problem:** Tapping Daily drops the in-progress normal game from the screen; no
     button reloads it. Restarting the app is the only way back, and New Game then
     overwrites the saved normal game (probe test: score 77 / tile 128 gone from the board
     while the save still held it, until a new game writes over it).
   - **Fix:** On mode switch, `_persist()` the outgoing game and restore the other slot
     (`_restoreSaved(storage.loadSavedGame(mode))`) when the user taps Daily again or a
     "Resume" action is added to the same button row.
   - **If we skip it:** Family members can't get back to their normal game without
     restarting the app (the save is on disk, just unreachable from the UI).

5. **Daily scores count into the per-size best score and the leaderboard** (`lib/main.dart:303-306`)
   - **What this is:** `best` and `best_scores/<player>` are keyed by board size only; the
     Daily puzzle of the day is also a 4×4 board.
   - **Problem:** `_afterMove` updates the best score regardless of `mode`, so a
     Wordle-style daily run of 500 outranks a real 4×4 game of 300 in
     `LeaderboardDialog`, even though `stats.dailyBest` tracks it separately already.
   - **Fix:** `if (mode == GameMode.normal && score > best)` — one condition.
   - **If we skip it:** The two record types get silently mixed and rankings lie.

6. **Share-screenshot files pile up forever, and break on web** (`lib/main.dart:498-510`)
   - **What this is:** Board screenshot → PNG → temp file → share dialog.
   - **Problem:** The file name carries `millisecondsSinceEpoch`, so every share leaves a
     new PNG in the system temp dir (never deleted, unbounded), and it is written
     synchronously on the UI thread. `dart:io` `File` throws `UnsupportedOperationException`
     on the web target, which this repo ships (`web/`), so the button dies there.
   - **Fix:** One fixed file name (`d2048_share.png`) plus `await file.writeAsBytes(...)`
     instead of `writeAsBytesSync`; skip the image path on web.
   - **If we skip it:** Disk grows with every share; web builds fail at runtime.

7. **A damaged save file silently loses the board** (`lib/game_storage.dart:213-214,50-64`)
   - **What this is:** On start-up the app reads the saved game; any parse problem returns
     `null` (line 214) and the app opens a brand-new game.
   - **Problem:** `SavedGame.fromJson` still hard-casts `boardSize`, `tiles` and every tile
     field, so one bad value (hand-edited prefs, a future format change) drops the
     whole in-progress board with no message and no `debugPrint`, unlike the write paths
     which do log.
   - **Fix:** One `debugPrint('d2048 saveGame undecodable: $e')` in that catch; keep
     `return null` as the behaviour.
   - **If we skip it:** Data loss with no clue in the log about what went wrong.

8. **The screens nobody tests are the ones that broke** (`test/widget_test.dart`)
   - **What this is:** 471 lines of tests cover the board, undo/redo, snapshots,
     migration, per-player namespacing and the Daily leaderboard.
   - **Problem:** Nothing opens `LeaderboardDialog` — the one dialog with no test is
     the one that throws (finding 1) and whose picker is broken (finding 2). Also
     untested: the Daily day-rollover branch (`main.dart:424-429`), the 50-snapshot cap,
     and `setBestScore`'s read-modify-write merge.
   - **Fix:** One test: tap the leaderboard icon, tap `6×6`, expect the 6×6 column.
     It fails today on both findings 1 and 2.
   - **If we skip it:** The next dialog change ships unverified again.

9. **Every move fires two un-awaited writes** (`lib/main.dart:401-417`)
   - **What this is:** `_persist()` sends the board and the stats to SharedPreferences
     after each move, undo and redo, without awaiting.
   - **Problem:** If the app is killed inside that window the last move never reaches
     disk, and `setBestScore` (`game_storage.dart:196-215`) rewrites the whole size map
     from a value it read earlier, so an overlapping write can drop an entry.
   - **Fix:** Chain the writes (`_pending = _pending.then(() => storage.saveGame(…))`)
     so they land in order; the write failures already log.
   - **If we skip it:** Rare, but the loss is the user's current board.

## Nice to have

10. **`SavedGame.mode` restates which key the save is stored under** (`lib/game_storage.dart:18-30`)
   - **What this is:** The Daily game is saved to `saved_game_daily/<player>`, the normal
     game to `saved_game/<player>`; `mode` is also written into the JSON.
   - **Problem:** The key and the field must always agree; `_restoreSaved` reads the field
     back, so a mismatch is possible in hand-edited data only.
   - **Fix:** Delete the field (keep `seed`, which the key cannot express).
   - **If we skip it:** Two sources of one fact.

11. **The tile list is serialized five times, in two near-copy classes** (`lib/main.dart:357,405,527` and `lib/game_storage.dart:41,90`)
   - **What this is:** `SavedGame` and `BoardSnapshot` are the same record plus
     name/date versus moves/undo/mode; both repeat the identical tile comprehension.
   - **Problem:** Five copies of one format; `BoardSnapshot` is `SavedGame` minus
     `undoCount`/`keepPlaying`/`mode`/`seed` plus `name`/`savedAt`.
   - **Fix:** One `(id, value, row, col) <-> map` helper used by both, then merge the two
     classes keeping the existing JSON keys so old saves still read.
   - **If we skip it:** Roughly 30 lines to keep in step by hand.

12. **`TODO.md:62` still says `lib/main.dart` is 470 lines** — it is 1029 now.
   - **Problem:** That line is the argument for "try the Kotlin migration in d2048 first
     because it is the smallest case"; the reasoning, not the number, is what matters.
   - **Fix:** Drop the number.

13. **The leaderboard row is written twice** (`lib/widgets/leaderboards.dart:31-39` and `106-114`)
   - Both dialogs build the same `ListTile` (rank, name, score) with the same
     bold-first-three style; a four-line private helper removes one copy.

14. **Share text reports a tile the board no longer has** (`lib/main.dart:487-495,366-380`)
   - `_shareText` prints `_gameMaxTile`, which undo does not roll back, so after undoing
     the winning move the shared text still says 2048. Recompute from `tiles` (one line).

## Verdict

Board logic, save format and per-player storage are sound; the two new leaderboard
screens are not — fix 1 and 2 before anything else, then 3 and 4, which users will
hit on the first session.

## Lean

`-40` lines, `-0` dependencies possible (findings 10-13). `intl` and `share_plus`
are both used, so no dependency can go.

## Not checked

No build was run for Android release/AOT, iOS, macOS, Linux or Windows (this aarch64
host cannot AOT-build, per `~/dennys/AGENTS.md`); no real device, no CI logs, no
`hc`/herdr runs. Not evaluated: dark-theme legibility of the tile palette, the
1.5 s celebration and 0.6 s +N animation timings, accessibility (no tile labels),
the `_migrateIfNeeded` path for builds older than the per-player change, and the
TODO.md Kotlin-migration plan itself (it is unverified by its own note).
