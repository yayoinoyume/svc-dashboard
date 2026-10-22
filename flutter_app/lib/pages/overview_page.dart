import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class OverviewPage extends StatelessWidget {
  final AppState state;
  const OverviewPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: state.usageRev,
      builder: (context, _, __) {
        final u = state.usage ?? <String, dynamic>{};
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _periodBar(context),
            const SizedBox(height: 14),
            _hero(context, u),
            const SizedBox(height: 12),
            _kpis(context, u),
            const SizedBox(height: 12),
            _trendCard(context),
            const SizedBox(height: 12),
            _modelsCard(context, u),
            const SizedBox(height: 12),
            _agentsCard(context, u),
            const SizedBox(height: 8),
            Center(
              child: Text(
                state.lastOk == null
                    ? '等待数据'
                    : '最后更新 ${fmtClock(state.lastOk!.toIso8601String())} · 每 20 秒刷新',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF6E778F)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _periodBar(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'today', label: Text('今日')),
        ButtonSegment(value: '7d', label: Text('7 天')),
        ButtonSegment(value: '30d', label: Text('30 天')),
        ButtonSegment(value: 'all', label: Text('全部')),
      ],
      selected: {state.period},
      onSelectionChanged: (s) => state.setPeriod(s.first),
    );
  }

  Widget _hero(BuildContext context, Map<String, dynamic> u) {
    final calls = asDouble(u['calls']);
    final errors = asDouble(u['errors']);
    final retried = asDouble(u['retried']);
    final cost = asDouble(u['cost']);
    final success = calls > 0 ? (calls - errors) / calls * 100 : 0.0;
    final unpriced = asInt(u['unpriced']);
    final credits = asDouble(u['credits']);
    final avg = calls > 0 ? cost / calls : 0.0;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '本期费用',
                  style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ),
              StatusPill(
                text: periodLabel(state.period),
                color: scheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedNumber(
            value: cost,
            format: fmtMoney,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _heroMeta(fmtInt(calls), '次调用'),
              _dot(),
              _heroMeta(fmtInt(errors), '错误'),
              _dot(),
              _heroMeta(fmtInt(retried), '重试'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('成功率 ${success.toStringAsFixed(1)}%', AppColors.success),
              _chip('未计价 $unpriced 次', AppColors.onSurfaceVariant),
              _chip('信用 ${credits > 0 ? credits.toStringAsFixed(1) : '—'}', scheme.primary),
              _chip('每次 ${fmtMoney(avg)}', AppColors.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMeta(String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _dot() => Container(
        width: 3,
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 7),
        decoration: const BoxDecoration(
          color: Color(0xFF556077),
          shape: BoxShape.circle,
        ),
      );

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _kpis(BuildContext context, Map<String, dynamic> u) {
    final timed = asDouble(u['timed']);
    final ttft = timed > 0 ? asDouble(u['ttft_ms']) / timed : 0.0;
    final decodeMs = asDouble(u['decode_ms']);
    final decode = decodeMs > 0 ? asDouble(u['decode_out']) / (decodeMs / 1000) : 0.0;
    final cacheRead = asDouble(u['cache_read']);
    final input = asDouble(u['input']);
    final hit = (input + cacheRead) > 0 ? cacheRead / (input + cacheRead) * 100 : 0.0;
    final calls = asDouble(u['calls']);
    final output = asDouble(u['output']);

    final tiles = [
      KpiTile(label: '输入 Token', value: fmtCompact(input), foot: '缓存占比 ${hit.round()}%'),
      KpiTile(
        label: '输出 Token',
        value: fmtCompact(output),
        foot: calls > 0 ? '每次 ${fmtCompact(output / calls)} tokens' : '本期累计',
      ),
      KpiTile(label: '缓存读取', value: fmtCompact(cacheRead), foot: '命中率 ${hit.round()}%'),
      KpiTile(label: '缓存写入', value: fmtCompact(u['cache_write']), foot: '本期累计'),
      KpiTile(label: '平均首字', value: ttft > 0 ? fmtMs(ttft) : '--', foot: 'TTFT'),
      KpiTile(label: '解码速度', value: decode > 0 ? '${decode.round()} t/s' : '--', foot: '输出 Token / 秒'),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.95,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: tiles,
    );
  }

  Widget _trendCard(BuildContext context) {
    final isDaily = state.metric == 'daily';
    final isCost = state.metric == 'cost';
    List<double> values;
    List<String> labels;
    String subtitle;

    if (isDaily) {
      final days = asMapList(state.history?['days']);
      values = days.map((d) => asDouble(d['requests'])).toList();
      labels = days.map((d) {
        final day = (d['day'] ?? '').toString();
        return day.length >= 10 ? day.substring(5) : day;
      }).toList();
      subtitle = '最近 ${days.length} 天每日请求量';
    } else {
      final series = asMapList(state.usage?['series']);
      values = series
          .map((s) => asDouble(isCost ? s['cost'] : s['calls']))
          .toList();
      labels = series.map((s) => (s['label'] ?? '').toString()).toList();
      subtitle = state.period == 'today' ? '按小时统计' : '按天统计';
    }

    final sum = values.fold<double>(0, (a, b) => a + b);
    final peak = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      title: '调用趋势',
      subtitle: subtitle,
      trailing: isCost
          ? '峰值 ${fmtMoney(peak)}'
          : '峰值 ${fmtCompact(peak)}',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'calls', label: Text('调用')),
                    ButtonSegment(value: 'cost', label: Text('费用')),
                    ButtonSegment(value: 'daily', label: Text('日请求')),
                  ],
                  selected: {state.metric},
                  onSelectionChanged: (s) => state.setMetric(s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TrendChart(
            values: values,
            labels: labels,
            color: isCost ? scheme.tertiary : scheme.primary,
            money: isCost,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                isCost ? '合计 ${fmtMoney(sum)}' : '合计 ${fmtInt(sum)} 次',
                style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                isDaily ? '近 ${values.length} 天' : periodLabel(state.period),
                style: const TextStyle(fontSize: 11, color: Color(0xFF6E778F)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelsCard(BuildContext context, Map<String, dynamic> u) {
    final models = asMapList(u['models']);
    models.sort((a, b) => asDouble(b['calls']).compareTo(asDouble(a['calls'])));
    final shown = models.take(10).toList();
    final maxCalls = shown.isEmpty ? 1.0 : asDouble(shown.first['calls']);
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      title: '模型用量',
      subtitle: '按调用次数排序',
      trailing: '共 ${models.length} 个',
      child: shown.isEmpty
          ? const EmptyHint('暂无模型数据')
          : Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  RankRow(
                    index: i,
                    name: (shown[i]['model'] ??
                            (shown[i]['id'] ?? '未知').toString().split(' @ ').first)
                        .toString(),
                    subtitle: [
                      if (shown[i]['provider'] != null) shown[i]['provider'].toString(),
                      if (asDouble(shown[i]['cost']) > 0) fmtMoney(shown[i]['cost']),
                      if (asInt(shown[i]['errors']) > 0) '错误 ${fmtInt(shown[i]['errors'])}',
                    ].join(' · '),
                    value: fmtCompact(shown[i]['calls']),
                    progress: asDouble(shown[i]['calls']) / maxCalls,
                    color: i == 0 ? scheme.primary : scheme.primary.withValues(alpha: 0.65),
                  ),
              ],
            ),
    );
  }

  Widget _agentsCard(BuildContext context, Map<String, dynamic> u) {
    final agents = asMapList(u['agents']);
    agents.sort((a, b) => asDouble(b['calls']).compareTo(asDouble(a['calls'])));
    final shown = agents.take(8).toList();
    final maxCalls = shown.isEmpty ? 1.0 : asDouble(shown.first['calls']);
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      title: '智能体',
      subtitle: '谁在消耗网关',
      trailing: '共 ${agents.length} 个',
      child: shown.isEmpty
          ? const EmptyHint('暂无智能体数据')
          : Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  RankRow(
                    index: i,
                    name: (shown[i]['name'] ?? shown[i]['id'] ?? '未知').toString(),
                    subtitle: [
                      if (asDouble(shown[i]['cost']) > 0) fmtMoney(shown[i]['cost']),
                      if (asInt(shown[i]['errors']) > 0) '错误 ${fmtInt(shown[i]['errors'])}',
                    ].join(' · '),
                    value: fmtCompact(shown[i]['calls']),
                    progress: asDouble(shown[i]['calls']) / maxCalls,
                    color: i == 0 ? scheme.secondary : scheme.secondary.withValues(alpha: 0.65),
                  ),
              ],
            ),
    );
  }
}
