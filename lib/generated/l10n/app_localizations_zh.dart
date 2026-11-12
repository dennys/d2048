// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get score => '分數';

  @override
  String get undo => '復原';

  @override
  String undoCount(int count) {
    return '復原 ×$count';
  }

  @override
  String get newGame => '新遊戲';

  @override
  String get settings => '設定';

  @override
  String get gameOver => '遊戲結束！';

  @override
  String get playAgain => '再玩一次';

  @override
  String get swipeHint => '滑動移動方塊，合併相同數字得到 2048！';

  @override
  String get selectBoardSize => '格數';

  @override
  String get language => '語言';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get english => 'English';

  @override
  String get traditionalChinese => '繁體中文';

  @override
  String get simplifiedChinese => '簡體中文';

  @override
  String get theme => '主題';

  @override
  String get light => '淺色';

  @override
  String get dark => '深色';

  @override
  String get system => '系統';

  @override
  String get best => '最高分';

  @override
  String get moves => '步數';

  @override
  String get redo => '重做';

  @override
  String get youWin => '你贏了！';

  @override
  String get keepPlaying => '繼續玩';

  @override
  String get saveSnapshot => '存快照';

  @override
  String get loadSnapshot => '快照';

  @override
  String get snapshotName => '名字';

  @override
  String get noSnapshots => '還沒有快照';

  @override
  String snapshotLimit(int limit) {
    return '快照已達上限（$limit）';
  }

  @override
  String get save => '儲存';

  @override
  String get cancel => '取消';

  @override
  String get haptics => '震動';

  @override
  String get stats => '統計';

  @override
  String get gamesPlayed => '局數';

  @override
  String get wins => '勝場';

  @override
  String get maxTile => '最大方塊';

  @override
  String get totalMerges => '總合併數';

  @override
  String get players => '玩家';

  @override
  String get whoIsPlaying => '誰在玩？';

  @override
  String get yourName => '你的名字';

  @override
  String get addPlayer => '新玩家名字';

  @override
  String get add => '新增';

  @override
  String get daily => '每日';

  @override
  String get normal => '普通';

  @override
  String get dailyLeaderboard => '每日排行榜';

  @override
  String get leaderboard => '排行榜';

  @override
  String get notPlayed => '—';

  @override
  String get noScores => '還沒有分數';

  @override
  String get share => '分享';

  @override
  String get shareText => '分享文字';

  @override
  String get shareScreenshot => '分享截圖';

  @override
  String get saveFailed => '儲存失敗（儲存空間不足？）：這一局可能不會被存起來';

  @override
  String get dataBroken => '讀不到玩家清單（儲存資料損毀）：已保留原始資料，不會覆寫';

  @override
  String get telegramSection => 'Telegram 家庭排行榜';

  @override
  String get telegramChannel => '頻道（@使用者名稱）';

  @override
  String get telegramToken => 'Bot token（選填）';

  @override
  String get telegramHelp => '頻道需為公開頻道。Token 留空則用分享選單送出分數。';

  @override
  String get telegramTest => '測試';

  @override
  String get telegramTestOk => '連線正常';

  @override
  String get telegramTestFail => '連線失敗';

  @override
  String get telegramInvalidChannel => '頻道名稱格式錯誤（5 個以上英數或底線，且以英文字母開頭）';

  @override
  String get sendToTelegram => '送到 Telegram';

  @override
  String get telegramSent => '已送到 Telegram';

  @override
  String get telegramNoGame => '請先完成一局';

  @override
  String get telegramSendFailed => '送到 Telegram 失敗';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get score => '分数';

  @override
  String get undo => '撤销';

  @override
  String undoCount(int count) {
    return '撤销 ×$count';
  }

  @override
  String get newGame => '新游戏';

  @override
  String get settings => '设置';

  @override
  String get gameOver => '游戏结束！';

  @override
  String get playAgain => '再玩一次';

  @override
  String get swipeHint => '滑动移动方块，合并相同数字得到 2048！';

  @override
  String get selectBoardSize => '格数';

  @override
  String get language => '语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get english => 'English';

  @override
  String get traditionalChinese => '繁体中文';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get theme => '主题';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get system => '系统';

  @override
  String get best => '最高分';

  @override
  String get moves => '步数';

  @override
  String get redo => '重做';

  @override
  String get youWin => '你赢了！';

  @override
  String get keepPlaying => '继续玩';

  @override
  String get saveSnapshot => '存快照';

  @override
  String get loadSnapshot => '快照';

  @override
  String get snapshotName => '名字';

  @override
  String get noSnapshots => '还没有快照';

  @override
  String snapshotLimit(int limit) {
    return '快照已达上限（$limit）';
  }

  @override
  String get save => '保存';

  @override
  String get cancel => '取消';

  @override
  String get haptics => '震动';

  @override
  String get stats => '统计';

  @override
  String get gamesPlayed => '局数';

  @override
  String get wins => '胜场';

  @override
  String get maxTile => '最大方块';

  @override
  String get totalMerges => '总合并数';

  @override
  String get players => '玩家';

  @override
  String get whoIsPlaying => '谁在玩？';

  @override
  String get yourName => '你的名字';

  @override
  String get addPlayer => '新玩家名字';

  @override
  String get add => '新增';

  @override
  String get daily => '每日';

  @override
  String get normal => '普通';

  @override
  String get dailyLeaderboard => '每日排行榜';

  @override
  String get leaderboard => '排行榜';

  @override
  String get notPlayed => '—';

  @override
  String get noScores => '还没有分数';

  @override
  String get share => '分享';

  @override
  String get shareText => '分享文字';

  @override
  String get shareScreenshot => '分享截图';

  @override
  String get saveFailed => '储存失败（存储空间不足？）：这一局可能不会被保存';

  @override
  String get dataBroken => '读不到玩家清单（储存资料损毁）：已保留原始资料，不会覆写';

  @override
  String get telegramSection => 'Telegram 家庭排行榜';

  @override
  String get telegramChannel => '频道（@用户名）';

  @override
  String get telegramToken => 'Bot token（选填）';

  @override
  String get telegramHelp => '频道需为公开频道。Token 留空则用分享菜单发送分数。';

  @override
  String get telegramTest => '测试';

  @override
  String get telegramTestOk => '连接正常';

  @override
  String get telegramTestFail => '连接失败';

  @override
  String get telegramInvalidChannel => '频道名称格式错误（5 个以上英数或下划线，且以英文字母开头）';

  @override
  String get sendToTelegram => '发送到 Telegram';

  @override
  String get telegramSent => '已发送到 Telegram';

  @override
  String get telegramNoGame => '请先完成一局';

  @override
  String get telegramSendFailed => '发送到 Telegram 失败';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get score => '分數';

  @override
  String get undo => '復原';

  @override
  String undoCount(int count) {
    return '復原 ×$count';
  }

  @override
  String get newGame => '新遊戲';

  @override
  String get settings => '設定';

  @override
  String get gameOver => '遊戲結束！';

  @override
  String get playAgain => '再玩一次';

  @override
  String get swipeHint => '滑動移動方塊，合併相同數字得到 2048！';

  @override
  String get selectBoardSize => '格數';

  @override
  String get language => '語言';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get english => 'English';

  @override
  String get traditionalChinese => '繁體中文';

  @override
  String get simplifiedChinese => '簡體中文';

  @override
  String get theme => '主題';

  @override
  String get light => '淺色';

  @override
  String get dark => '深色';

  @override
  String get system => '系統';

  @override
  String get best => '最高分';

  @override
  String get moves => '步數';

  @override
  String get redo => '重做';

  @override
  String get youWin => '你贏了！';

  @override
  String get keepPlaying => '繼續玩';

  @override
  String get saveSnapshot => '存快照';

  @override
  String get loadSnapshot => '快照';

  @override
  String get snapshotName => '名字';

  @override
  String get noSnapshots => '還沒有快照';

  @override
  String snapshotLimit(int limit) {
    return '快照已達上限（$limit）';
  }

  @override
  String get save => '儲存';

  @override
  String get cancel => '取消';

  @override
  String get haptics => '震動';

  @override
  String get stats => '統計';

  @override
  String get gamesPlayed => '局數';

  @override
  String get wins => '勝場';

  @override
  String get maxTile => '最大方塊';

  @override
  String get totalMerges => '總合併數';

  @override
  String get players => '玩家';

  @override
  String get whoIsPlaying => '誰在玩？';

  @override
  String get yourName => '你的名字';

  @override
  String get addPlayer => '新玩家名字';

  @override
  String get add => '新增';

  @override
  String get daily => '每日';

  @override
  String get normal => '普通';

  @override
  String get dailyLeaderboard => '每日排行榜';

  @override
  String get leaderboard => '排行榜';

  @override
  String get notPlayed => '—';

  @override
  String get noScores => '還沒有分數';

  @override
  String get share => '分享';

  @override
  String get shareText => '分享文字';

  @override
  String get shareScreenshot => '分享截圖';

  @override
  String get saveFailed => '儲存失敗（儲存空間不足？）：這一局可能不會被存起來';

  @override
  String get dataBroken => '讀不到玩家清單（儲存資料損毀）：已保留原始資料，不會覆寫';

  @override
  String get telegramSection => 'Telegram 家庭排行榜';

  @override
  String get telegramChannel => '頻道（@使用者名稱）';

  @override
  String get telegramToken => 'Bot token（選填）';

  @override
  String get telegramHelp => '頻道需為公開頻道。Token 留空則用分享選單送出分數。';

  @override
  String get telegramTest => '測試';

  @override
  String get telegramTestOk => '連線正常';

  @override
  String get telegramTestFail => '連線失敗';

  @override
  String get telegramInvalidChannel => '頻道名稱格式錯誤（5 個以上英數或底線，且以英文字母開頭）';

  @override
  String get sendToTelegram => '送到 Telegram';

  @override
  String get telegramSent => '已送到 Telegram';

  @override
  String get telegramNoGame => '請先完成一局';

  @override
  String get telegramSendFailed => '送到 Telegram 失敗';
}
