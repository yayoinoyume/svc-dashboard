import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';
import '../widgets/flow_diagram.dart';

/// 客户端 ID 原样显示：magpie 上报什么就显示什么，不做翻译或别名。
/// 这里只负责配色——同一个名字永远同一个颜色，没见过的按稳定哈希取。
const _agentPalette = <Color>[
  Color(0xFF9B7BB8),
  Color(0xFF7FA6C9),
  Color(0xFF7BC9A6),
  Color(0xFFD9B36C),
  Color(0xFFE57373),
  Color(0xFFA0D2EB),
  Color(0xFFC3A6E0),
];

String _agentKey(Map<String, dynamic> r) {
  final a = (r['agent'] ?? '').toString().trim();
  return a.isEmpty ? 'other' : a;
}

String _agentName(Map<String, dynamic> r) => _agentKey(r);

Color _agentColorOf(String key) {
  if (key == 'other') return const Color(0xFF8E9BB3);
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _agentPalette[h % _agentPalette.length];
}

const _running = Color(0xFF9B7BB8);
const _done = Color(0xFF7BC9A6);
const _error = Color(0xFFE57373);
const _reroute = Color(0xFFD9B36C);

Color _dotColor(String state) {
  switch (state) {
    case 'live':
      return _running;
    case 'err':
      return _error;
    default:
      return _done;
  }
}

String _modelShort(dynamic m) {
  final s = (m ?? '').toString();
  final i = s.indexOf('/');
  return i >= 0 ? s.substring(i + 1) : s;
}

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

({String key, String kind, String name, String sub}) _targetOf(
    Map<String, dynamic> r) {
  final g = r['group'];
  if (g is Map && g['name'] != null) {
    final members = (g['members'] as List?) ?? const [];
    return (
      key: 'g:${g['id'] ?? g['name']}',
      kind: 'group',
      name: g['name'].toString(),
      sub: '${members.length} 账号',
    );
  }
  final prov = (r['provider'] ?? '未知').toString();
  final model = _modelShort(r['model']);
  return (
    key: 'd:$prov/$model',
    kind: 'direct',
    name: _cap(prov),
    sub: model,
  );
}

DateTime? _timeOf(Map<String, dynamic> r) =>
    DateTime.tryParse((r['time'] ?? '').toString());

String _stateOf(Map<String, dynamic> r) {
  if (r['done'] != true) return 'live';
  if (asInt(r['status']) >= 400) return 'err';
  final tries = (r['tries'] as List?) ?? const [];
  if (tries.length > 1) return 'reroute';
  return 'ok';
}

int _outTokens(Map<String, dynamic> r) {
  final usage = r['usage'];
  if (usage is List && usage.isNotEmpty && usage.first is Map) {
    final o = asInt((usage.first as Map)['out']);
    if (o > 0) return o;
  }
  return asInt(r['out']);
}

/// 输出速度：输出 token / 流式时长（秒）。
/// flow 缺失时退回 (总耗时 - 首字) 估算。
double _tpsOf(Map<String, dynamic> r) {
  final tries = (r['tries'] as List?) ?? const [];
  if (tries.isEmpty || tries.last is! Map) return 0;
  final t = tries.last as Map;
  final out = _outTokens(r);
  if (out <= 0) return 0;
  var flow = asInt(t['flow']);
  if (flow <= 0 && r['done'] == true) {
    final ms = asInt(t['ms']);
    final ttft = asInt(t['ttft']);
    if (ms > ttft && ttft > 0) flow = ms - ttft;
  }
  if (flow <= 0) return 0;
  return out / (flow / 1000);
}

int _msOf(Map<String, dynamic> r) {
  final tr = (r['tries'] as List?) ?? const [];
  if (tr.isEmpty) return 0;
  final last = tr.last;
  if (last is! Map) return 0;
  final ms = asInt(last['ms']);
  if (ms > 0) return ms;
  final start = DateTime.tryParse((last['start'] ?? '').toString());
  if (start == null) return 0;
  final end = r['done'] == true
      ? (DateTime.tryParse((r['time'] ?? '').toString()) ?? DateTime.now())
      : DateTime.now();
  return end.difference(start).inMilliseconds;
}

String _fmtMs(int ms) {
  if (ms <= 0) return '--';
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final m = ms ~/ 60000;
  final s = ((ms % 60000) / 1000).round();
  return '${m}m${s}s';
}

class _Agg {
  int count = 0;
  int live = 0;
  int err = 0;
  DateTime? lastAt;
  final Set<String> convs = {};
}

class _Model {
  final List<FlowNode> clients;
  final List<FlowNode> targets;
  final List<FlowLink> links;
  final int total;
  final int live;
  final int reroute;
  final int errors;

  const _Model({
    required this.clients,
    required this.targets,
    required this.links,
    required this.total,
    required this.live,
    required this.reroute,
    required this.errors,
  });

  static _Model build(List<Map<String, dynamic>> routes) {
    final cm = <String, _Agg>{};
    final tm = <String, _Agg>{};
    final em = <String, _Agg>{};
    final tMeta = <String, ({String kind, String name, String sub})>{};

    var live = 0, reroute = 0, errs = 0;
    for (final r in routes) {
      final a = _agentKey(r);
      final t = _targetOf(r);
      final st = _stateOf(r);
      final ts = _timeOf(r);

      final c = cm.putIfAbsent(a, () => _Agg())
        ..count += 1
        ..convs.add((r['conv'] ?? r['folder'] ?? r['id']).toString());
      if (st == 'live') c.live++;
      if (st == 'err') c.err++;
      if (ts != null && (c.lastAt == null || ts.isAfter(c.lastAt!))) {
        c.lastAt = ts;
      }

      final ta = tm.putIfAbsent(t.key, () => _Agg())..count += 1;
      if (st == 'live') ta.live++;
      if (st == 'err') ta.err++;
      if (ts != null && (ta.lastAt == null || ts.isAfter(ta.lastAt!))) {
        ta.lastAt = ts;
      }
      tMeta[t.key] = (kind: t.kind, name: t.name, sub: t.sub);

      final ek = '$a|${t.key}';
      final e = em.putIfAbsent(ek, () => _Agg())..count += 1;
      if (st == 'live') e.live++;
      if (st == 'err') e.err++;

      if (st == 'live') live++;
      if (st == 'err') errs++;
      if (st == 'reroute') reroute++;
    }

    // 只保留仍然活跃的节点：正在处理，或最近 15 秒内有动静。
    // 否则窗口中所有历史请求会把已经空闲的客户端一直挂在图上。
    final now = DateTime.now();
    const activeWindow = Duration(seconds: 15);
    bool isActive(_Agg? a) =>
        a != null &&
        (a.live > 0 ||
            (a.lastAt != null && now.difference(a.lastAt!) <= activeWindow));

    final clientKeys = cm.keys.where((k) => isActive(cm[k])).toList()
      ..sort((x, y) => cm[y]!.count.compareTo(cm[x]!.count));
    final targetKeys = tm.keys.where((k) => isActive(tm[k])).toList()
      ..sort((x, y) => tm[y]!.count.compareTo(tm[x]!.count));
    final activeClients = clientKeys.toSet();
    final activeTargets = targetKeys.toSet();

    final clients = [
      for (final k in clientKeys)
        FlowNode(
          key: k,
          label: k,
          sub: '${cm[k]!.count} 次 · ${cm[k]!.convs.length} 会话',
          dot: _agentColorOf(k),
          count: cm[k]!.count,
          live: cm[k]!.live > 0,
          err: cm[k]!.err > 0,
        ),
    ];

    final targets = [
      for (final k in targetKeys)
        FlowNode(
          key: k,
          label: tMeta[k]!.name,
          sub: tMeta[k]!.kind == 'group'
              ? '${tm[k]!.count} 次 · ${tMeta[k]!.sub}'
              : '${tm[k]!.count} 次',
          dot: tm[k]!.err > 0
              ? _error
              : tm[k]!.live > 0
                  ? _running
                  : const Color(0xFF59637A),
          count: tm[k]!.count,
          live: tm[k]!.live > 0,
          err: tm[k]!.err > 0,
        ),
    ];

    final links = <FlowLink>[];
    for (final e in em.entries) {
      // agent 名是上游原样给的，可能含 |；目标 key 受控，从右侧找分隔符
      final sep = e.key.lastIndexOf('|');
      final from = e.key.substring(0, sep);
      final to = e.key.substring(sep + 1);
      if (!activeClients.contains(from) || !activeTargets.contains(to)) {
        continue;
      }
      links.add(
        FlowLink(
          from: from,
          to: to,
          count: e.value.count,
          live: e.value.live > 0,
          err: e.value.err > 0,
        ),
      );
    }

    return _Model(
      clients: clients,
      targets: targets,
      links: links,
      total: routes.length,
      live: live,
      reroute: reroute,
      errors: errs,
    );
  }
}

class RoutingPage extends StatefulWidget {
  final AppState state;
  const RoutingPage({super.key, required this.state});

  @override
  State<RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends State<RoutingPage> {
  String tab = 'flow';
  String? selectedKey;
  bool selectedIsClient = true;
  final Set<String> expanded = {};
  bool showAll = false;

  /// 流向图默认只画请求最多的 3 个客户端，其余合并成一行
  bool _clientsExpanded = false;
  static const _clientLimit = 3;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.state.traceRev,
      builder: (context, _, __) {
        final raw = widget.state.trace;
        final routes = asMapList(raw?['routes']);
        final model = _Model.build(routes);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'flow', label: Text('实时流向')),
                ButtonSegment(value: 'groups', label: Text('路由组')),
              ],
              selected: {tab},
              onSelectionChanged: (s) => setState(() => tab = s.first),
            ),
            const SizedBox(height: 14),
            if (tab == 'flow')
              ..._flow(context, model, routes)
            else
              ..._groups(context),
          ],
        );
      },
    );
  }

  List<Widget> _flow(
    BuildContext context,
    _Model model,
    List<Map<String, dynamic>> routes,
  ) {
    final filtered = _filtered(routes);
    final shown = showAll ? filtered : filtered.take(12).toList();

    // 默认只画前 3 个客户端，"其他 N 种"合成一行；N 是实际剩余数量
    final allClients = model.clients;
    final hidden = allClients.length - _clientLimit;
    final folded = hidden > 0 && !_clientsExpanded;
    final visibleClients =
        _clientsExpanded ? allClients : allClients.take(_clientLimit).toList();
    final foldedCount = folded
        ? allClients.skip(_clientLimit).fold<int>(0, (a, c) => a + c.count)
        : 0;
    final diagramClients = <FlowNode>[
      ...visibleClients,
      if (folded)
        FlowNode(
          key: '__more',
          label: '其他 $hidden 种',
          sub: '合计 $foldedCount 次',
          dot: const Color(0xFF9B7BB8),
          count: foldedCount,
          hubOnly: true,
        ),
    ];
    final visibleKeys = diagramClients.map((c) => c.key).toSet();
    final diagramLinks = model.links
        .where((l) => visibleKeys.contains(l.from))
        .toList();
    // 只保留仍有可见入线的目标，避免折叠后出现没有任何连线的孤点
    final linkedTargets = diagramLinks.map((l) => l.to).toSet();
    final diagramTargets = model.targets
        .where((t) => linkedTargets.contains(t.key))
        .toList();

    return [
      StatStrip(
        items: [
          ('进行中', '${model.live}'),
          ('最近请求', '${model.total}'),
          ('改道', '${model.reroute}'),
          ('错误', '${model.errors}'),
        ],
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 13, 12, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '实时流向',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // 目标与流向按图上实际画的算，折叠时不会出现
                        // "写了 4 个目标、只画 2 个"的错位
                        Text(
                          model.clients.isEmpty
                              ? '当前没有活跃请求'
                              : '${model.clients.length} 个客户端 · '
                                  '${diagramTargets.length} 个目标 · '
                                  '${diagramLinks.length} 条流向',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6E778F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (allClients.length > _clientLimit) ...[
                    GestureDetector(
                      onTap: () => setState(
                        () => _clientsExpanded = !_clientsExpanded,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: AppColors.outline,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          _clientsExpanded
                              ? '收起'
                              : '展开 ${allClients.length} 种',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  LiveDot(ok: widget.state.liveOk),
                ],
              ),
              const SizedBox(height: 6),
              if (model.clients.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: EmptyHint('当前空闲，等待新请求'),
                )
              else
                FlowDiagram(
                  clients: diagramClients,
                  targets: diagramTargets,
                  links: diagramLinks,
                  selectedKey: selectedKey,
                  onTap: _onNodeTap,
                ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.only(top: 7),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x1FA9B0C6))),
                ),
                child: const Row(
                  children: [
                    _Legend(color: _running, text: '进行中'),
                    SizedBox(width: 12),
                    _Legend(color: Color(0x59A9B0C6), text: '已完成'),
                    SizedBox(width: 12),
                    _Legend(color: _reroute, text: '改道'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          const Expanded(
            child: Text(
              '请求流水',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${filtered.length} 条'
            '${model.live > 0 ? ' · ${model.live} 进行中' : ''}',
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF6E778F)),
          ),
          if (selectedKey != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _clearFilter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.outline, width: 0.8),
                ),
                child: const Text(
                  '清除筛选 ×',
                  style: TextStyle(fontSize: 9, color: Color(0xFFA9B0C6)),
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      if (filtered.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: EmptyHint('没有匹配的请求'),
        )
      else
        for (final r in shown) ...[
          _RouteRow(
            key: ValueKey(r['id'].toString()),
            route: r,
            open: expanded.contains(r['id'].toString()),
            onTap: () {
              final id = r['id'].toString();
              setState(() {
                if (!expanded.remove(id)) expanded.add(id);
              });
            },
          ),
          const SizedBox(height: 6),
        ],
      if (!showAll && filtered.length > 12)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton(
            onPressed: () => setState(() => showAll = true),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.outline, width: 0.8),
              foregroundColor: AppColors.onSurfaceVariant,
              minimumSize: const Size.fromHeight(38),
              textStyle: const TextStyle(fontSize: 10.5),
            ),
            child: Text('显示全部 ${filtered.length} 条'),
          ),
        ),
      const SizedBox(height: 8),
      const Center(
        child: Text(
          '长轮询实时流 · 有事件立即更新',
          style: TextStyle(fontSize: 9.5, color: Color(0xFF6E778F)),
        ),
      ),
    ];
  }

  void _onNodeTap(FlowNode node, bool isClient) {
    setState(() {
      if (selectedKey == node.key) {
        selectedKey = null;
      } else {
        selectedKey = node.key;
        selectedIsClient = isClient;
      }
    });
  }

  void _clearFilter() {
    setState(() => selectedKey = null);
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> routes) {
    final list = routes.where((r) {
      if (selectedKey == null) return true;
      if (selectedIsClient) return _agentKey(r) == selectedKey;
      return _targetOf(r).key == selectedKey;
    }).toList();

    list.sort((a, b) {
      final ad = a['done'] == true, bd = b['done'] == true;
      if (ad != bd) return ad ? 1 : -1;
      final at = DateTime.tryParse((a['time'] ?? '').toString());
      final bt = DateTime.tryParse((b['time'] ?? '').toString());
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    return list;
  }

  List<Widget> _groups(BuildContext context) {
    final g = widget.state.groups;
    if (g == null) {
      return const [EmptyHint('正在加载路由组…')];
    }
    final groups = asMapList(g['groups']);
    final pools = asMapList(g['pools']);
    final deciders = asMapList(g['deciders']);

    return [
      StatStrip(
        items: [
          ('路由组', '${groups.length}'),
          ('账号池', '${pools.length}'),
          ('决策器', '${deciders.length}'),
        ],
      ),
      const SizedBox(height: 14),
      for (final item in groups) ...[
        _GroupCard(group: item),
        const SizedBox(height: 9),
      ],
      if (pools.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Text(
            '账号池',
            style: TextStyle(
              fontSize: 10.5,
              color: Color(0xFF6E778F),
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final p in pools) ...[
          _PoolCard(pool: p),
          const SizedBox(height: 9),
        ],
      ],
      if (deciders.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Text(
            '决策器',
            style: TextStyle(
              fontSize: 10.5,
              color: Color(0xFF6E778F),
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final d in deciders) ...[
          _PoolCard(pool: d, isDecider: true),
          const SizedBox(height: 9),
        ],
      ],
    ];
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 9, color: Color(0xFF6E778F)),
        ),
      ],
    );
  }
}

class _RouteRow extends StatelessWidget {
  final Map<String, dynamic> route;
  final bool open;
  final VoidCallback onTap;

  const _RouteRow({
    super.key,
    required this.route,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = route;
    final st = _stateOf(r);
    final tgt = _targetOf(r);
    final tries = (r['tries'] as List?) ?? const [];
    final ms = _msOf(r);
    final conv = (r['conv'] ?? r['folderShort'] ?? '').toString();
    final tokens = asInt((r['prompt'] is Map) ? r['prompt']['tokens'] : 0);
    final tps = _tpsOf(r);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
      child: Container(
      decoration: BoxDecoration(
        color: st == 'live' ? const Color(0xFF171427) : AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: st == 'live'
              ? _running.withValues(alpha: 0.42)
              : AppColors.outline,
          width: 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _dotColor(st),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _agentName(r),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFA9B0C6),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        '→',
                        style: TextStyle(fontSize: 9, color: Color(0xFF4C566D)),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tgt.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      st == 'live' ? '进行中' : _fmtMs(ms),
                      style: TextStyle(
                        fontSize: 10,
                        color: st == 'live' ? _running : const Color(0xFF6E778F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      fmtClock((r['time'] ?? '').toString()),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF6E778F),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (conv.isNotEmpty)
                              TextSpan(text: '会话 $conv   '),
                            TextSpan(text: '${fmtCompact(tokens)} tok'),
                            if (tps > 0)
                              TextSpan(
                                text: '   ${tps.round()} tokens/秒',
                                style: const TextStyle(color: Color(0xFFB99BD1)),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF6E778F),
                        ),
                      ),
                    ),
                    if (tries.length > 1) ...[
                      const SizedBox(width: 6),
                      _Badge(text: '改道 ×${tries.length}', color: _reroute),
                    ],
                    if (st == 'err') ...[
                      const SizedBox(width: 6),
                      _Badge(text: 'HTTP ${r['status']}', color: _error),
                    ],
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: open
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            const Divider(color: Color(0x1FA9B0C6), height: 1),
                            const SizedBox(height: 8),
                            _detail(r),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _detail(Map<String, dynamic> r) {
    final tries = (r['tries'] as List?) ?? const [];
    final order = asMapList(r['order']).take(4).toList();
    final aff = r['affinity'] is Map ? r['affinity'] as Map : const {};
    final chosen = tries.isNotEmpty && tries.first is Map
        ? (tries.first['id'] ?? '').toString()
        : '';
    final t0 = tries.isNotEmpty && tries.last is Map ? tries.last as Map : null;
    final ttft = t0 == null ? 0 : asInt(t0['ttft']);
    final tps = _tpsOf(r);

    final meta = <(String, String)>[
      if (tries.isNotEmpty) ('尝试', '${tries.length} 次'),
      if ((r['effort'] ?? '').toString().isNotEmpty)
        ('思考', r['effort'].toString()),
      if (ttft > 0) ('首字', fmtMs(ttft)),
      if (tps > 0) ('速度', '${tps.round()} tokens/秒'),
      if (aff['turn'] != null) ('轮次', '第 ${asInt(aff['turn']) + 1} 轮'),
      if (asInt(aff['cacheRead']) > 0)
        ('缓存读取', fmtCompact(aff['cacheRead'])),
      if (asDouble(r['cost']) > 0) ('费用', fmtMoney(r['cost'])),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                for (final m in meta)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.$1,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Color(0xFF6E778F),
                        ),
                      ),
                      Text(
                        m.$2,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        for (var i = 0; i < order.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  child: Text(
                    (order[i]['id'] ?? '').toString() == chosen ? '✓' : '·',
                    style: TextStyle(
                      fontSize: 9,
                      color: (order[i]['id'] ?? '').toString() == chosen
                          ? _done
                          : const Color(0xFF6E778F),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${order[i]['name'] ?? order[i]['provider'] ?? ''}'
                    '${order[i]['model'] != null ? ' · ${order[i]['model']}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: (order[i]['id'] ?? '').toString() == chosen
                          ? const Color(0xFFD8C6E8)
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '#${i + 1}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF6E778F),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 8.5, color: color),
      ),
    );
  }
}

class _GroupCard extends StatefulWidget {
  final Map<String, dynamic> group;
  const _GroupCard({required this.group});

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final members = asMapList(g['memberInfo']);
    final rawMembers = (g['members'] as List?) ?? [];
    final off = (g['off'] as List?) ?? [];
    final count = rawMembers.isNotEmpty ? rawMembers.length : members.length;
    final visible = open ? count : count.clamp(0, 3);

    final infoById = <String, Map<String, dynamic>>{
      for (final m in members) (m['id'] ?? '').toString(): m,
    };

    final chips = <Widget>[];
    for (var i = 0; i < visible && i < rawMembers.length; i++) {
      final id = rawMembers[i].toString();
      final info = infoById[id] ?? <String, dynamic>{};
      final label = info['provider'] != null
          ? '${info['provider']}/${info['model'] ?? id}'
          : id;
      final isOff = off.map((e) => e.toString()).contains(id);
      chips.add(_memberChip(
        label,
        isOff ? AppColors.error : AppColors.onSurfaceVariant,
      ));
    }
    if (!open && count > visible) {
      chips.add(_memberChip('+${count - visible}', AppColors.onSurfaceVariant));
    }

    final meta = '$count 成员'
        '${off.isNotEmpty ? ' · ${off.length} 停用' : ''}'
        '${g['ready'] == true ? ' · 就绪' : ' · 未就绪'}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => open = !open),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (g['name'] ?? g['id'] ?? '未知').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  StatusPill(
                    text: (g['routing'] ?? 'order').toString(),
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  ExpandChevron(open: open),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(spacing: 5, runSpacing: 5, children: chips),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  final Map<String, dynamic> pool;
  final bool isDecider;

  const _PoolCard({required this.pool, this.isDecider = false});

  @override
  Widget build(BuildContext context) {
    final who = isDecider
        ? (pool['providerName'] ?? pool['provider'] ?? '').toString()
        : ((pool['who'] as List?) ?? [])
            .map((e) => maskAccount(e.toString()))
            .join('、');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (pool['name'] ?? pool['id'] ?? '未知').toString(),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!isDecider)
                  StatusPill(
                    text: (pool['kind'] ?? '池').toString(),
                    color: AppColors.onSurfaceVariant,
                  ),
              ],
            ),
            if (who.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                who,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
