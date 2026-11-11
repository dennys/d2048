// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get score => 'Score';

  @override
  String get undo => 'Undo';

  @override
  String undoCount(int count) {
    return 'Undo ×$count';
  }

  @override
  String get newGame => 'New Game';

  @override
  String get settings => 'Settings';

  @override
  String get gameOver => 'Game Over!';

  @override
  String get playAgain => 'Play Again';

  @override
  String get swipeHint =>
      'Swipe to move tiles. Merge same numbers to get 2048!';

  @override
  String get selectBoardSize => 'Board size';

  @override
  String get language => 'Language';

  @override
  String get followSystem => 'Follow system';

  @override
  String get english => 'English';

  @override
  String get traditionalChinese => 'Traditional Chinese';

  @override
  String get simplifiedChinese => 'Simplified Chinese';

  @override
  String get theme => 'Theme';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get system => 'System';

  @override
  String get best => 'Best';

  @override
  String get moves => 'Moves';

  @override
  String get redo => 'Redo';

  @override
  String get youWin => 'You win!';

  @override
  String get keepPlaying => 'Keep playing';

  @override
  String get saveSnapshot => 'Save snapshot';

  @override
  String get loadSnapshot => 'Snapshots';

  @override
  String get snapshotName => 'Name';

  @override
  String get noSnapshots => 'No snapshots yet';

  @override
  String snapshotLimit(int limit) {
    return 'Snapshot limit ($limit) reached';
  }

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get haptics => 'Haptics';

  @override
  String get stats => 'Stats';

  @override
  String get gamesPlayed => 'Games played';

  @override
  String get wins => 'Wins';

  @override
  String get maxTile => 'Best tile';

  @override
  String get totalMerges => 'Total merges';

  @override
  String get players => 'Players';

  @override
  String get whoIsPlaying => 'Who\'s playing?';

  @override
  String get yourName => 'Your name';

  @override
  String get addPlayer => 'New player name';

  @override
  String get add => 'Add';

  @override
  String get daily => 'Daily';

  @override
  String get normal => 'Normal';

  @override
  String get dailyLeaderboard => 'Daily leaderboard';

  @override
  String get leaderboard => 'Leaderboard';

  @override
  String get notPlayed => '—';

  @override
  String get noScores => 'No scores yet';

  @override
  String get share => 'Share';

  @override
  String get shareText => 'Share text';

  @override
  String get shareScreenshot => 'Share screenshot';

  @override
  String get saveFailed =>
      'Couldn\'t save your game (out of storage?). This round may not be kept.';

  @override
  String get dataBroken =>
      'Couldn\'t read the player list (saved data is damaged). Nothing was overwritten.';
}
