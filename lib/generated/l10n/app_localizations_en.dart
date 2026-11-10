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
}
