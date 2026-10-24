import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个已发布的版本。
class ReleaseInfo {
  final String tag; // v1.7.0
  final String version; // 1.7.0
  final String url; // Release 页面
  final String notes;
  final DateTime? publishedAt;

  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.url,
    this.notes = '',
    this.publishedAt,
  });

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'version': version,
        'url': url,
        'notes': notes,
        'publishedAt': publishedAt?.toIso8601String(),
      };

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) => ReleaseInfo(
        tag: (j['tag'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        notes: (j['notes'] ?? '').toString(),
        publishedAt: DateTime.tryParse((j['publishedAt'] ?? '').toString()),
      );
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);

  @override
  String toString() => message;
}

/// 检查 GitHub Releases 上的新版本。
///
/// 只读公开接口，不需要令牌；结果缓存 24 小时，
/// 避免每次启动都打 GitHub 的匿名额度（每小时 60 次）。
class UpdateService {
  static const repo = 'yayoinoyume/svc-dashboard';
  static const _cacheKey = 'magpie_update_cache_v1';
  static const _ttl = Duration(hours: 24);

  static String? _current;

  /// 当前安装的版本号，如 1.7.0
  static Future<String> currentVersion() async {
    if (_current != null) return _current!;
    try {
      final info = await PackageInfo.fromPlatform();
      _current = info.version.isEmpty ? '0.0.0' : info.version;
    } catch (_) {
      _current = '0.0.0';
    }
    return _current!;
  }

  /// 有新版本时返回它，已最新返回 null，网络/解析失败抛 [UpdateException]。
  ///
  /// [force] 为 true 时忽略 24 小时缓存，用于用户手动点「检查更新」。
  static Future<ReleaseInfo?> check({
    bool force = false,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final current = await currentVersion();
    final cached = await _readCache();

    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.at) < _ttl) {
      return _newerThan(cached.release, current) ? cached.release : null;
    }

    final fresh = await _fetch(timeout);
    if (fresh == null) {
      // 拿不到最新版本时，退回旧缓存里已经知道的新版本
      if (cached != null && _newerThan(cached.release, current)) {
        return cached.release;
      }
      throw const UpdateException('无法连接更新服务器，请检查网络后重试');
    }
    await _writeCache(fresh);
    return _newerThan(fresh, current) ? fresh : null;
  }

  /// 上次检查的时间，用于界面上说明结果是什么时候拿到的。
  static Future<DateTime?> lastCheckedAt() async => (await _readCache())?.at;

  static bool _newerThan(ReleaseInfo r, String current) =>
      compareVersions(r.version, current) > 0;

  /// 按数字分段比较，1.10.0 > 1.9.0；非数字段按 0 处理。
  static int compareVersions(String a, String b) {
    List<int> parts(String s) => s
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static Future<ReleaseInfo?> _fetch(Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          )
          .timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'MagpieFlutter');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body =
          await res.transform(utf8.decoder).join().timeout(timeout);
      final d = jsonDecode(body) as Map<String, dynamic>;
      final tag = (d['tag_name'] ?? '').toString();
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (version.isEmpty) return null;
      return ReleaseInfo(
        tag: tag,
        version: version,
        url: (d['html_url'] ?? '').toString(),
        notes: (d['body'] ?? '').toString(),
        publishedAt: DateTime.tryParse((d['published_at'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<({DateTime at, ReleaseInfo release})?> _readCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null) return null;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      return (
        at: DateTime.fromMillisecondsSinceEpoch((d['at'] as num).toInt()),
        release: ReleaseInfo.fromJson(
          (d['release'] as Map).cast<String, dynamic>(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(ReleaseInfo r) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _cacheKey,
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'release': r.toJson(),
        }),
      );
    } catch (_) {
      // 缓存写不进去不影响检查结果
    }
  }
}
