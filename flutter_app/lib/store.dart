import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'util.dart';

class AppConfig {
  String baseUrl;
  String key;
  String cookieName;

  AppConfig({
    this.baseUrl = 'https://magpie.example.invalid',
    this.key = '',
    this.cookieName = 'magpie_web_3430',
  });

  bool get hasKey => key.trim().isNotEmpty;
}

class ConfigStore {
  static const _kBase = 'magpie_base';
  static const _kKey = 'magpie_key';
  static const _kCookie = 'magpie_cookie';

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return AppConfig(
      baseUrl: p.getString(_kBase) ?? 'https://magpie.example.invalid',
      key: p.getString(_kKey) ?? '',
      cookieName: p.getString(_kCookie) ?? 'magpie_web_3430',
    );
  }

  static Future<void> save(AppConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBase, c.baseUrl.trim());
    await p.setString(_kCookie, c.cookieName.trim());
    if (c.key.trim().isNotEmpty) {
      await p.setString(_kKey, c.key.trim());
    }
  }

  static Future<void> clearKey() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
  }
}

class AppState extends ChangeNotifier {
  AppState(this.config)
      : api = ApiClient(
          baseUrl: config.baseUrl,
          key: config.key,
          cookieName: config.cookieName,
        );

  AppConfig config;
  ApiClient api;

  String period = 'today';
  String metric = 'calls';

  Map<String, dynamic>? usage;
  List<dynamic> quotas = [];
  Map<String, dynamic>? trace;
  Map<String, dynamic>? providers;
  Map<String, dynamic>? groups;
  Map<String, dynamic>? history;

  List<String> routeOrder = [];
  bool loading = false;
  bool live = false;
  bool liveOk = false;
  String? error;
  DateTime? lastOk;
  DateTime? lastTraceOk;

  DateTime? _providersAt;
  DateTime? _groupsAt;
  DateTime? _historyAt;
  bool _liveRunning = false;

  Future<void> refreshAll({bool force = false}) async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        api.getJson('/api/usage?period=$period'),
        api.getList('/api/usage/quotas'),
      ]);
      usage = results[0] as Map<String, dynamic>;
      quotas = results[1] as List<dynamic>;
      lastOk = DateTime.now();
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
    unawaited(_loadProviders(force));
    unawaited(_loadGroups(force));
    unawaited(_loadHistory(force));
    if (!live) unawaited(loadTraceOnce());
  }

  Future<void> refreshUsage() async {
    try {
      usage = await api.getJson('/api/usage?period=$period');
      lastOk = DateTime.now();
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> loadTraceOnce() async {
    try {
      final after = trace == null ? 0 : asInt(trace!['seq']);
      final d = await api.getJson('/api/gateway/trace?after=$after');
      mergeTrace(d, after);
    } catch (_) {
      // 次要数据，静默失败
    }
  }

  Future<void> _loadProviders(bool force) async {
    final now = DateTime.now();
    if (!force &&
        providers != null &&
        _providersAt != null &&
        now.difference(_providersAt!).inSeconds < 600) {
      return;
    }
    try {
      providers = await api.getJson('/api/providers');
      _providersAt = now;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadGroups(bool force) async {
    final now = DateTime.now();
    if (!force &&
        groups != null &&
        _groupsAt != null &&
        now.difference(_groupsAt!).inSeconds < 60) {
      return;
    }
    try {
      groups = await api.getJson('/api/groups');
      _groupsAt = now;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadHistory(bool force) async {
    final now = DateTime.now();
    if (!force &&
        history != null &&
        _historyAt != null &&
        now.difference(_historyAt!).inSeconds < 600) {
      return;
    }
    try {
      history = await api.getJson('/api/gateway/history');
      _historyAt = now;
      notifyListeners();
    } catch (_) {}
  }

  void setPeriod(String p) {
    if (period == p) return;
    period = p;
    notifyListeners();
    unawaited(refreshUsage());
  }

  void setMetric(String m) {
    metric = m;
    notifyListeners();
  }

  void mergeTrace(Map<String, dynamic> d, int after) {
    final incoming = asMapList(d['routes']);

    if (after == 0 || trace == null) {
      final map = <String, Map<String, dynamic>>{};
      for (final r in incoming) {
        map[routeKey(r)] = r;
      }
      routeOrder = map.keys.toList();
      trace = <String, dynamic>{
        'totals': d['totals'] ?? <String, dynamic>{},
        'seq': asInt(d['seq']),
        'routes': routeOrder.map((k) => map[k]).toList(),
      };
    } else {
      final map = <String, Map<String, dynamic>>{};
      for (final r in asMapList(trace!['routes'])) {
        map[routeKey(r)] = r;
      }
      for (final r in incoming) {
        final k = routeKey(r);
        map[k] = r;
        if (!routeOrder.contains(k)) routeOrder.add(k);
      }
      routeOrder.removeWhere((k) => !map.containsKey(k));
      while (routeOrder.length > 80) {
        map.remove(routeOrder.removeAt(0));
      }
      final seq = asInt(d['seq']);
      trace = <String, dynamic>{
        'totals': d['totals'] ?? trace!['totals'],
        'seq': seq != 0 ? seq : trace!['seq'],
        'routes': routeOrder
            .map((k) => map[k])
            .whereType<Map<String, dynamic>>()
            .toList(),
      };
    }
    notifyListeners();
  }

  void startLive() {
    if (_liveRunning) return;
    _liveRunning = true;
    live = true;
    notifyListeners();
    unawaited(_liveLoop());
  }

  void stopLive() {
    _liveRunning = false;
    live = false;
    notifyListeners();
  }

  Future<void> _liveLoop() async {
    while (_liveRunning) {
      try {
        final after = trace == null ? 0 : asInt(trace!['seq']);
        final path =
            '/api/gateway/trace?after=$after${after > 0 ? '&wait=1' : ''}';
        final d = await api.getJson(
          path,
          timeout: const Duration(seconds: 70),
        );
        mergeTrace(d, after);
        liveOk = true;
        lastTraceOk = DateTime.now();
        notifyListeners();
      } catch (_) {
        liveOk = false;
        notifyListeners();
        if (_liveRunning) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
      if (!_liveRunning) break;
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  void updateConfig(AppConfig c) {
    stopLive();
    config = c;
    api.close();
    api = ApiClient(
      baseUrl: c.baseUrl,
      key: c.key,
      cookieName: c.cookieName,
    );
    usage = null;
    quotas = [];
    trace = null;
    providers = null;
    groups = null;
    history = null;
    routeOrder = [];
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _liveRunning = false;
    api.close();
    super.dispose();
  }
}
