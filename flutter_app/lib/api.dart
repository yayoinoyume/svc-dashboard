import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  final int statusCode;
  final String body;

  ApiException(this.statusCode, this.body);

  @override
  String toString() {
    if (statusCode == 401) return '密钥无效或未配置';
    if (body.isEmpty) return 'HTTP $statusCode';
    return 'HTTP $statusCode';
  }
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.key,
    required this.cookieName,
  });

  String baseUrl;
  String key;
  String cookieName;

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  String get _base {
    final b = baseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  Future<dynamic> getRaw(
    String path, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (key.trim().isEmpty) {
      throw ApiException(401, '');
    }
    final uri = Uri.parse('$_base$path');
    final req = await _client.getUrl(uri).timeout(timeout);
    req.headers.set(HttpHeaders.cookieHeader, '$cookieName=$key');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.userAgentHeader, 'MagpieFlutter/1.0');

    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body);
    }
    if (body.isEmpty) return <String, dynamic>{};
    return jsonDecode(body);
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final data = await getRaw(path, timeout: timeout);
    if (data is Map<String, dynamic>) return data;
    if (data is List) return <String, dynamic>{'data': data};
    return <String, dynamic>{};
  }

  Future<List<dynamic>> getList(
    String path, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final data = await getRaw(path, timeout: timeout);
    if (data is List) return data;
    if (data is Map<String, dynamic> && data['data'] is List) {
      return data['data'] as List<dynamic>;
    }
    return <dynamic>[];
  }

  void close() {
    _client.close(force: true);
  }
}
