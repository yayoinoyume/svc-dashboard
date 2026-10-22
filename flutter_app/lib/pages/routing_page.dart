import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class RoutingPage extends StatefulWidget {
  final AppState state;
  const RoutingPage({super.key, required this.state});

  @override
  State<RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends State<RoutingPage> {
  String tab = 'live';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'live', label: Text('实时请求')),
                ButtonSegment(value: 'groups', label: Text('路由组')),
              ],
              selected: {tab},
              onSelectionChanged: (s) => setState(() => tab = s.first),
            ),
            const SizedBox(height: 14),
            if (tab == 'live') ..._live(context) else ..._groups(context),
          ],
        );
      },
    );
  }

  List<Widget> _live(BuildContext context) {
    final t = widget.state.trace;
    final totals = t?['totals'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final routes = asMapList(t?['routes']).reversed.toList();
    final running = routes.where((r) => r['done'] != true).length;

    return [
      StatStrip(
        items: [
          ('总请求', fmtCompact(totals['requests'])),
          ('改道', fmtCompact(totals['rerouted'])),
          ('错误', fmtCompact(totals['errors'])),
        ],
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                          '实时请求',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          running > 0
                              ? '正在处理 $running 个请求 · ${routes.length} 条记录'
                              : '当前空闲 · 最近 ${routes.length} 条记录',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  LiveDot(ok: widget.state.liveOk),
                ],
              ),
              const SizedBox(height: 12),
              if (routes.isEmpty)
                const EmptyHint('暂无路由记录')
              else
                for (final r in routes.take(20)) ...[
                  RouteCard(route: r),
                  const SizedBox(height: 9),
                ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Center(
        child: Text(
          '长轮询实时流 · 有事件立即更新',
          style: TextStyle(fontSize: 10, color: Color(0xFF6E778F)),
        ),
      ),
    ];
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
      chips.add(_memberChip(label, isOff ? AppColors.error : AppColors.onSurfaceVariant));
    }
    if (!open && count > visible) {
      chips.add(_memberChip('+${count - visible}', AppColors.onSurfaceVariant));
    }

    final meta =
        '$count 成员${off.isNotEmpty ? ' · ${off.length} 停用' : ''}${g['ready'] == true ? ' · 就绪' : ' · 未就绪'}';

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

class RouteCard extends StatefulWidget {
  final Map<String, dynamic> route;
  const RouteCard({super.key, required this.route});

  @override
  State<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<RouteCard> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final scheme = Theme.of(context).colorScheme;
    final done = r['done'] == true;
    final runningColor = const Color(0xFF7FA6C9);

    final name = (r['group'] is Map && r['group']['name'] != null)
        ? r['group']['name'].toString()
        : (r['model'] ?? '未知模型').toString().replaceFirst('group/', '');

    final tries = asMapList(r['tries']);
    final agent = r['agent']?.toString();
    final start = DateTime.tryParse((r['time'] ?? '').toString())?.toLocal();
    final tokens = r['prompt'] is Map ? asInt(r['prompt']['tokens']) : 0;

    final nodes = <Widget>[];
    void addArrow() {
      if (nodes.isNotEmpty) {
        nodes.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.arrow_forward_rounded, size: 11, color: Color(0xFF556077)),
        ));
      }
    }

    if (agent != null && agent.isNotEmpty) {
      addArrow();
      nodes.add(ChainNode(label: agent, color: AppColors.onSurfaceVariant));
    }
    addArrow();
    nodes.add(ChainNode(label: 'magpie', color: runningColor));
    if (tries.isEmpty) {
      addArrow();
      nodes.add(ChainNode(
        label: (r['provider'] ?? '未知').toString(),
        color: done ? AppColors.success : runningColor,
        pulse: !done,
      ));
    } else {
      for (var i = 0; i < tries.length; i++) {
        final tr = tries[i];
        final isLast = i == tries.length - 1;
        final color = isLast
            ? (done ? AppColors.success : runningColor)
            : AppColors.error;
        addArrow();
        nodes.add(ChainNode(
          label: (tr['id'] ?? tr['provider'] ?? '?').toString(),
          color: color,
          pulse: isLast && !done,
        ));
      }
    }

    final meta = <String>[
      if (start != null) fmtClock(start.toIso8601String()),
      if (tokens > 0) '${fmtCompact(tokens)} tokens',
      if (tries.length > 1) '尝试 ${tries.length} 次',
      if (r['effort'] != null) r['effort'].toString(),
    ].join(' · ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? AppColors.outline
              : runningColor.withValues(alpha: 0.32),
          width: 0.9,
        ),
        boxShadow: done
            ? null
            : [
                BoxShadow(
                  color: runningColor.withValues(alpha: 0.06),
                  blurRadius: 14,
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StatusPill(
                      text: done ? '完成' : '进行中',
                      color: done ? AppColors.success : runningColor,
                      dot: !done,
                    ),
                    const SizedBox(width: 4),
                    ExpandChevron(open: open),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 3,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: nodes,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (!done && start != null)
                      ElapsedText(start: start),
                  ],
                ),
                if (open) ...[
                  const SizedBox(height: 10),
                  Divider(color: AppColors.outline.withValues(alpha: 0.6)),
                  const SizedBox(height: 10),
                  _detail(context, r, scheme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, Map<String, dynamic> r, ColorScheme scheme) {
    final order = asMapList(r['order']);
    final affinity = r['affinity'] is Map ? r['affinity'] as Map : null;
    final prompt = r['prompt'] is Map ? r['prompt'] as Map : null;
    final parts = asMapList(prompt?['parts']);
    final total = asInt(prompt?['tokens']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (order.isNotEmpty) ...[
          _detailTitle('候选池', '${order.length} 个'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in order.take(10))
                Container(
                  width: 150,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.outline, width: 0.6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${o['name'] ?? o['id']}${o['model'] != null ? ' · ${o['model']}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '已用 ${_usedLabel(o['used'])}${asDouble(o['pace']) > 0 ? ' · 速度 ${(asDouble(o['pace']) * 100).round()}%' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (affinity != null) ...[
          _detailTitle('亲和性', ''),
          const SizedBox(height: 3),
          Text(
            [
              if (affinity['kept'] == true) '保持缓存',
              if (affinity['why'] != null) affinity['why'].toString(),
              if (affinity['turn'] != null) '第 ${asInt(affinity['turn']) + 1} 轮',
              if (asInt(affinity['cacheRead']) > 0)
                '缓存 ${fmtCompact(affinity['cacheRead'])}',
            ].join(' · '),
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 10),
        ],
        if (parts.isNotEmpty) ...[
          _detailTitle('上下文构成', '${fmtCompact(total)} tokens'),
          const SizedBox(height: 6),
          for (final p in parts)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      decodePartKind(p['kind']?.toString()),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      fmtCompact(p['tokens']),
                      style: const TextStyle(
                        fontSize: 10,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: total > 0
                            ? asDouble(p['tokens']) / total
                            : 0,
                        minHeight: 4,
                        backgroundColor: AppColors.surfaceHigh,
                        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 30,
                    child: Text(
                      total > 0
                          ? '${(asDouble(p['tokens']) / total * 100).round()}%'
                          : '',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (asDouble(r['cost']) > 0 || r['priced'] == false) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (asDouble(r['cost']) > 0) '费用 ${fmtMoney(r['cost'])}',
              if (r['priced'] == false) '未计价',
            ].join(' · '),
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailTitle(String text, String trailing) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          trailing,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6E778F)),
        ),
      ],
    );
  }

  String _usedLabel(dynamic used) {
    if (used == null) return '—';
    final n = asDouble(used);
    if (n >= 100) return n.round().toString();
    if (n >= 10) return n.toStringAsFixed(1);
    return n.toStringAsFixed(2);
  }
}
