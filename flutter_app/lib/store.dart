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
    // 仓库是公开的，默认地址留空，由用户首次打开时自行填写
    this.baseUrl = '',
    this.key = '',
    this.cookieName = 'magpie_web_3430',
  });

  bool get hasKey =>
      key.trim().isNotEmpty && baseUrl.trim().isNotEmpty;
}

class ConfigStore {
  static const _kBase = 'magpie_base';
  static const _kKey = 'magpie_key';
  static const _kCookie = 'magpie_cookie';

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return AppConfig(
      baseUrl: p.getString(_kBase) ?? '',
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

  /// 细粒度刷新信号：各页面只监听自己需要的那一份，
  /// 避免任一数据变化时五页同时重建。
  final usageRev = ValueNotifier<int>(0);
  final traceRev = ValueNotifier<int>(0);
  final quotasRev = ValueNotifier<int>(0);
  final providersRev = ValueNotifier<int>(0);

  /// 隐私（掩码）统计：只服务「明细 → 隐私」子页
  final maskingRev = ValueNotifier<int>(0);
  Map<String, dynamic>? maskingSummary;
  int maskingDays = 7;
  DateTime? _maskingAt;
  bool _maskingRunning = false;

  /// 记录列表与筛选条件，放在这里是为了切走子页再回来不丢
  List<Map<String, dynamic>> maskingRecords = [];
  bool maskingMore = false;
  bool maskingRecordsLoading = false;
  String maskKind = '';
  String maskBy = '';
  String maskAgent = '';
  String maskProvider = '';

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
      usageRev.value++;
      quotasRev.value++;
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
      usageRev.value++;
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
      providersRev.value++;
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

  // ---------- 隐私（掩码）统计 ----------

  /// 汇总数据。网关不支持时抛 404，页面据此显示升级提示。
  Future<void> loadMasking({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        maskingSummary != null &&
        _maskingAt != null &&
        now.difference(_maskingAt!).inSeconds < 12) {
      return;
    }
    try {
      final d = await api.getJson('/api/masking/summary?days=$maskingDays');
      maskingSummary = d;
      maskingError = null;
      _maskingAt = now;
      maskingRev.value++;
    } catch (e) {
      // 404 = 网关版本太旧；其它错误保留上一份数据
      maskingError = e is ApiException && e.statusCode == 404
          ? 'unsupported'
          : e.toString();
      maskingRev.value++;
    }
  }

  String? maskingError;
  bool get maskingUnsupported => maskingError == 'unsupported';

  void setMaskingDays(int d) {
    if (maskingDays == d) return;
    maskingDays = d;
    maskingRev.value++;
    unawaited(loadMasking(force: true));
  }

  /// 隐私子页可见时才轮询，切走就停
  void startMaskingLive() {
    if (_maskingRunning) return;
    _maskingRunning = true;
    unawaited(_maskingLoop());
  }

  void stopMaskingLive() {
    _maskingRunning = false;
  }

  Future<void> _maskingLoop() async {
    while (_maskingRunning) {
      await loadMasking(force: true);
      await loadMaskingRecords(force: true);
      if (!_maskingRunning) break;
      await Future.delayed(const Duration(seconds: 15));
    }
  }

  Future<void> loadMaskingRecords({bool more = false, bool force = false}) async {
    if (maskingRecordsLoading) return;
    if (!more && !force && maskingRecords.isNotEmpty) return;
    maskingRecordsLoading = true;
    try {
      final q = <String>['limit=40'];
      if (more && maskingRecords.isNotEmpty) {
        q.add('before=${maskingRecords.last['key']}');
      }
      if (maskKind.isNotEmpty) q.add('kind=$maskKind');
      if (maskBy.isNotEmpty) q.add('by=$maskBy');
      if (maskAgent.isNotEmpty) q.add('agent=$maskAgent');
      if (maskProvider.isNotEmpty) q.add('provider=$maskProvider');
      final d = await api.getJson('/api/masking/records?${q.join('&')}');
      final got = asMapList(d['records']);
      maskingRecords = more ? [...maskingRecords, ...got] : got;
      maskingMore = d['more'] == true;
      maskingRev.value++;
    } catch (_) {
      // 老版本网关没有这个接口，页面会按空列表处理
    } finally {
      maskingRecordsLoading = false;
    }
  }

  /// 换了筛选条件就从头拉
  void setMaskFilter({
    String? kind,
    String? by,
    String? agent,
    String? provider,
  }) {
    maskKind = kind ?? '';
    maskBy = by ?? '';
    maskAgent = agent ?? '';
    maskProvider = provider ?? '';
    maskingRecords = [];
    maskingMore = false;
    maskingRev.value++;
    unawaited(loadMaskingRecords(force: true));
  }

  /// 查占位符对应的原文。网关只存在内存里，重启后返回 null。
  Future<String?> maskValue(String placeholder) async {
    try {
      final d = await api.getJson(
        '/api/masking/value?p=${Uri.encodeComponent(placeholder)}',
      );
      final v = d['value'];
      return v is String ? v : null;
    } catch (_) {
      return null;
    }
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
    traceRev.value++;
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
    stopMaskingLive();
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
    maskingSummary = null;
    _maskingAt = null;
    error = null;
    usageRev.value++;
    traceRev.value++;
    quotasRev.value++;
    providersRev.value++;
    maskingRev.value++;
    notifyListeners();
  }

  @override
  void dispose() {
    _liveRunning = false;
    _maskingRunning = false;
    api.close();
    usageRev.dispose();
    traceRev.dispose();
    quotasRev.dispose();
    providersRev.dispose();
    maskingRev.dispose();
    super.dispose();
  }
}
