import 'package:d2048/game_storage.dart';
import 'package:d2048/telegram_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('normalizeChannel', () {
    test('strips @ and accepts valid usernames', () {
      expect(TelegramService.normalizeChannel(' @d2048_family '), 'd2048_family');
      expect(TelegramService.normalizeChannel('abcde'), 'abcde');
    });

    test('empty means unset; invalid returns null', () {
      expect(TelegramService.normalizeChannel('  '), '');
      expect(TelegramService.normalizeChannel('1abcdef'), isNull);
      expect(TelegramService.normalizeChannel('abc'), isNull);
      expect(TelegramService.normalizeChannel('a/b/c d'), isNull);
    });
  });

  test('scoreMessage collapses whitespace in the player name', () {
    expect(
      TelegramService.scoreMessage(seed: 20261111, player: ' Mom  Li ', score: 1234),
      'd2048 daily 20261111 Mom Li 1234',
    );
  });

  test('parseScores extracts only well-formed daily score lines', () {
    const html = '''
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 daily 20261111 Dad 2048</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">hello &amp; bye</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 daily 20261111 Bob 3<br>x</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 daily 20261111 Kid &amp; Co 512</div>
''';
    final scores = TelegramService.parseScores(html);
    expect(scores.length, 2);
    expect(scores[0].player, 'Dad');
    expect(scores[0].score, 2048);
    expect(scores[1].player, 'Kid & Co');
    expect(scores[1].score, 512);
  });

  test('mergeDailyRows keeps the higher score and local unsent scores', () {
    const seed = 20261111;
    final local = <(String, GameStats)>[
      ('Dad', GameStats(dailyBest: 100, lastDailyDate: seed)),
      ('Mom', GameStats(dailyBest: 0, lastDailyDate: 0)),
    ];
    final remote = [
      const TelegramScore(seed, 'Dad', 300),
      const TelegramScore(seed, 'Mom', 50),
      const TelegramScore(20261110, 'Mom', 9999),
    ];
    final merged = TelegramService.mergeDailyRows(local: local, remote: remote, seed: seed);
    final byName = {for (final (n, s) in merged) n: s};
    expect(byName['Dad']!.dailyBest, 300);
    expect(byName['Mom']!.dailyBest, 50);
    expect(byName['Mom']!.lastDailyDate, seed);
  });

  test('cache round-trips per channel', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await TelegramService.writeCache(prefs, 'fam', [const TelegramScore(1, 'A', 2)]);
    final hit = TelegramService.readCache(prefs, 'fam');
    expect(hit.single.player, 'A');
    expect(hit.single.score, 2);
    // 換頻道後不可沿用舊頻道的快取。
    expect(TelegramService.readCache(prefs, 'other'), isEmpty);
  });
}
