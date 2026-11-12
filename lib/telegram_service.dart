import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'settings_keys.dart';

/// 從頻道解析出來的一局：id 是去重的 key，date 是 yyyymmdd，size 是格數。
class TelegramGame {
  final String id;
  final int date;
  final int size;
  final String player;
  final int score;

  const TelegramGame({
    required this.id,
    required this.date,
    required this.size,
    required this.player,
    required this.score,
  });
}

/// 錯誤訊息只含 Telegram 回的 description 或簡短原因，**絕不含 URL**（token 在 path 裡）。
class TelegramException implements Exception {
  final String message;

  TelegramException(this.message);

  @override
  String toString() => message;
}

/// Telegram 家庭排行榜：頻道就是資料庫，每局一則訊息。讀取走公開的 `t.me/s/<頻道>`（免憑證），
/// 寫入走 bot 的 `sendMessage`（需 token）。
class TelegramService {
  TelegramService._();

  static const _timeout = Duration(seconds: 8);
  static final _usernameRe = RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$');
  static final _messageTextRe = RegExp(r'js-message_text[^>]*>([\s\S]*?)</div>');
  static final _gameLineRe = RegExp(r'^d2048 v2 ([0-9a-z]+) (\d{8}) (\d+) (.+) (\d+)$');

  /// 去掉前導 `@` 並驗證格式；空字串回傳空字串（代表未設定），格式錯誤回傳 null。
  static String? normalizeChannel(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'^@'), '');
    if (value.isEmpty) return '';
    return _usernameRe.hasMatch(value) ? value : null;
  }

  /// 每局一個 id（時間 + 隨機），當作去重的 key。
  static String newGameId() {
    final rng = Random();
    final suffix = List.generate(4, (_) => rng.nextInt(36).toRadixString(36)).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$suffix';
  }

  /// 要送進頻道的那一行。名字壓成單行，免得破壞解析。
  static String gameMessage({
    required String id,
    required int date,
    required int size,
    required String player,
    required int score,
  }) {
    final name = player.replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'd2048 v2 $id $date $size $name $score';
  }

  static Future<List<TelegramGame>> fetchGames(String channel) async {
    final (status, body) = await _request(Uri.https('t.me', '/s/$channel'));
    if (status != 200) throw TelegramException('HTTP $status');
    return parseGames(body);
  }

  /// 解析 `t.me/s/` 的 HTML。格式沒文件、隨時會改，所以只抓節點文字，抓不到就回空清單。
  /// 同一個 id 只保留第一筆（重送、補送都會被忽略）。
  static List<TelegramGame> parseGames(String html) {
    final out = <TelegramGame>[];
    final seen = <String>{};
    for (final m in _messageTextRe.allMatches(html)) {
      final match = _gameLineRe.firstMatch(_plainText(m.group(1)!));
      if (match == null) continue;
      final id = match.group(1)!;
      final date = int.tryParse(match.group(2)!);
      final size = int.tryParse(match.group(3)!);
      final score = int.tryParse(match.group(5)!);
      if (date == null || size == null || score == null) continue;
      if (!seen.add(id)) continue;
      out.add(TelegramGame(
        id: id,
        date: date,
        size: size,
        player: match.group(4)!.trim(),
        score: score,
      ));
    }
    return out;
  }

  /// 排序：日期新→舊，同一天分數高→低。
  static List<TelegramGame> ranked(List<TelegramGame> games) {
    return [...games]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.score.compareTo(a.score);
      });
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

  static List<TelegramGame> readCache(SharedPreferences prefs, String channel) {
    final raw = prefs.getString(Prefs.telegramCache);
    if (raw == null) return const [];
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['channel'] != channel) return const [];
      return [
        for (final e in map['games'] as List)
          TelegramGame(
            id: e['i'] as String,
            date: e['d'] as int,
            size: e['z'] as int,
            player: e['p'] as String,
            score: e['v'] as int,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> writeCache(
    SharedPreferences prefs,
    String channel,
    List<TelegramGame> games,
  ) {
    return prefs.setString(
      Prefs.telegramCache,
      jsonEncode({
        'channel': channel,
        'games': [
          for (final g in games) {'i': g.id, 'd': g.date, 'z': g.size, 'p': g.player, 'v': g.score},
        ],
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
