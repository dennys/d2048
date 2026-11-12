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

  test('gameMessage collapses whitespace in the player name', () {
    expect(
      TelegramService.gameMessage(
        id: 'abc123',
        date: 20261111,
        size: 4,
        player: ' Mom  Li ',
        score: 1234,
      ),
      'd2048 v2 abc123 20261111 4 Mom Li 1234',
    );
  });

  test('parseGames extracts only well-formed game lines and dedupes by id', () {
    const html = '''
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 v2 a1 20261111 4 Dad 2048</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">hello &amp; bye</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 daily 20261111 Old 3</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 v2 a2 20261111 5 Bob 3<br>x</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 v2 a3 20261111 4 Kid &amp; Co 512</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">d2048 v2 a1 20261111 4 Dad 2048</div>
''';
    final games = TelegramService.parseGames(html);
    expect(games.length, 2);
    expect(games[0].id, 'a1');
    expect(games[0].player, 'Dad');
    expect(games[0].score, 2048);
    expect(games[1].player, 'Kid & Co');
    expect(games[1].size, 4);
    expect(games[1].score, 512);
  });

  test('ranked sorts by date desc, then score desc', () {
    const games = [
      TelegramGame(id: '1', date: 20261110, size: 4, player: 'A', score: 9999),
      TelegramGame(id: '2', date: 20261111, size: 4, player: 'B', score: 100),
      TelegramGame(id: '3', date: 20261111, size: 4, player: 'C', score: 300),
    ];
    final ids = TelegramService.ranked(games).map((g) => g.id).toList();
    expect(ids, ['3', '2', '1']);
  });

  test('newGameId returns distinct ids', () {
    final ids = {for (var i = 0; i < 100; i++) TelegramService.newGameId()};
    expect(ids.length, 100);
  });

  test('cache round-trips per channel', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await TelegramService.writeCache(prefs, 'fam', [
      const TelegramGame(id: 'x', date: 1, size: 4, player: 'A', score: 2),
    ]);
    final hit = TelegramService.readCache(prefs, 'fam');
    expect(hit.single.id, 'x');
    expect(hit.single.player, 'A');
    expect(hit.single.score, 2);
    // 換頻道後不可沿用舊頻道的快取。
    expect(TelegramService.readCache(prefs, 'other'), isEmpty);
  });
}
