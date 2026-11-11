import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'game_storage.dart';
import 'settings_keys.dart';

/// 從頻道解析出來的一筆家庭分數。
class TelegramScore {
  final int seed;
  final String player;
  final int score;

  const TelegramScore(this.seed, this.player, this.score);
}

/// 錯誤訊息只含 Telegram 回的 description 或簡短原因，**絕不含 URL**（token 在 path 裡）。
class TelegramException implements Exception {
  final String message;

  TelegramException(this.message);

  @override
  String toString() => message;
}

/// Telegram 家庭排行榜：頻道就是資料庫。讀取走公開的 `t.me/s/<頻道>`（免憑證），
/// 寫入走 bot 的 `sendMessage`（需 token）。
class TelegramService {
  TelegramService._();

  static const _timeout = Duration(seconds: 8);
  static final _usernameRe = RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$');
  static final _messageTextRe = RegExp(r'js-message_text[^>]*>([\s\S]*?)</div>');
  static final _scoreLineRe = RegExp(r'^d2048 daily (\d{8}) (.+) (\d+)$');

  /// 去掉前導 `@` 並驗證格式；空字串回傳空字串（代表未設定），格式錯誤回傳 null。
  static String? normalizeChannel(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'^@'), '');
    if (value.isEmpty) return '';
    return _usernameRe.hasMatch(value) ? value : null;
  }

  /// 要送進頻道的那一行。名字壓成單行，免得破壞解析。
  static String scoreMessage({required int seed, required String player, required int score}) {
    final name = player.replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'd2048 daily $seed $name $score';
  }

  static Future<List<TelegramScore>> fetchScores(String channel) async {
    final (status, body) = await _request(Uri.https('t.me', '/s/$channel'));
    if (status != 200) throw TelegramException('HTTP $status');
    return parseScores(body);
  }

  /// 解析 `t.me/s/` 的 HTML。格式沒文件、隨時會改，所以只抓節點文字，抓不到就回空清單。
  static List<TelegramScore> parseScores(String html) {
    final out = <TelegramScore>[];
    for (final m in _messageTextRe.allMatches(html)) {
      final match = _scoreLineRe.firstMatch(_plainText(m.group(1)!));
      if (match == null) continue;
      final seed = int.tryParse(match.group(1)!);
      final score = int.tryParse(match.group(3)!);
      if (seed == null || score == null) continue;
      out.add(TelegramScore(seed, match.group(2)!.trim(), score));
    }
    return out;
  }

  static Future<void> sendMessage({
    required String token,
    required String channel,
    required String text,
  }) async {
    await _api(token, 'sendMessage', json: {'chat_id': '@$channel', 'text': text});
  }

  /// 回傳 bot 的 username（不含 @），用來確認 token 正確。
  static Future<String> getMeUsername(String token) async {
    final result = await _api(token, 'getMe');
    final username = result is Map ? result['username'] : null;
    if (username is! String) throw TelegramException('bad response');
    return username;
  }

  /// 合併本機與頻道的今日 daily 分數：同一玩家取較高者；本機尚未送出的分數也保留。
  static List<(String, GameStats)> mergeDailyRows({
    required List<(String, GameStats)> local,
    required List<TelegramScore> remote,
    required int seed,
  }) {
    final remoteBest = <String, int>{};
    for (final s in remote) {
      if (s.seed != seed) continue;
      if (s.score > (remoteBest[s.player] ?? -1)) remoteBest[s.player] = s.score;
    }
    final merged = <String, GameStats>{for (final (name, stats) in local) name: stats};
    remoteBest.forEach((name, score) {
      final mine = merged[name];
      if (mine != null && mine.lastDailyDate == seed && mine.dailyBest >= score) return;
      merged[name] = GameStats(dailyBest: score, lastDailyDate: seed);
    });
    return [for (final e in merged.entries) (e.key, e.value)];
  }

  static List<TelegramScore> readCache(SharedPreferences prefs, String channel) {
    final raw = prefs.getString(Prefs.telegramCache);
    if (raw == null) return const [];
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['channel'] != channel) return const [];
      return [
        for (final e in map['scores'] as List)
          TelegramScore(e['s'] as int, e['p'] as String, e['v'] as int),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> writeCache(
    SharedPreferences prefs,
    String channel,
    List<TelegramScore> scores,
  ) {
    return prefs.setString(
      Prefs.telegramCache,
      jsonEncode({
        'channel': channel,
        'scores': [for (final s in scores) {'s': s.seed, 'p': s.player, 'v': s.score}],
      }),
    );
  }

  static Future<Object?> _api(String token, String method, {Map<String, Object?>? json}) async {
    final (_, body) = await _request(Uri.https('api.telegram.org', '/bot$token/$method'), json: json);
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw TelegramException('bad response');
    }
    if (map['ok'] != true) throw TelegramException('${map['description'] ?? 'error'}');
    return map['result'];
  }

  static Future<(int, String)> _request(Uri uri, {Map<String, Object?>? json}) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = json == null ? await client.getUrl(uri) : await client.postUrl(uri);
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(json));
      }
      final res = await req.close().timeout(_timeout);
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      return (res.statusCode, body);
    } catch (_) {
      // 不把原始例外往上拋：HttpException 可能帶著含 token 的 URI。
      throw TelegramException('network error');
    } finally {
      client.close(force: true);
    }
  }

  static String _plainText(String html) {
    final noTags = html.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]+>'), '');
    return noTags
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }
}
