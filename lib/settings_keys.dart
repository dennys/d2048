/// 所有 SharedPreferences 的 key 與預設值，全案唯一定義處（比照 dHealth）。
class Prefs {
  Prefs._();

  static const language = 'language';
  static const theme = 'theme';
  static const boardSize = 'board_size';
  static const haptics = 'haptics';

  // 遊戲資料（GameStorage 用）
  static const savedGame = 'saved_game';
  static const snapshots = 'snapshots';
  static const bestScores = 'best_scores';
  static const stats = 'stats';
}

/// 預設值。同一個語意只准出現一次。
class PrefsDefaults {
  PrefsDefaults._();

  static const language = 'system';
  static const theme = 'system';

  /// 新遊戲預設格數；New Game 對話框可選 4–8。
  static const boardSize = 4;
  static const List<int> boardSizeOptions = [4, 5, 6, 7, 8];

  /// 合併震動，預設關。
  static const haptics = false;

  /// 快照上限：滿了擋下新存檔。
  static const snapshotLimit = 50;
}