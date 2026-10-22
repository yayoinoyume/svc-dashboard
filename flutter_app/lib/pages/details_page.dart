import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class DetailsPage extends StatefulWidget {
  final AppState state;
  const DetailsPage({super.key, required this.state});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  String tab = 'sessions';
  final Set<String> expanded = {};

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.state.usageRev,
      builder: (context, _, __) {
        final u = widget.state.usage ?? <String, dynamic>{};
        final rows = _rows(u);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'sessions', label: Text('会话')),
                  ButtonSegment(value: 'accounts', label: Text('账号')),
                  ButtonSegment(value: 'callers', label: Text('调用方')),
                  ButtonSegment(value: 'keys', label: Text('密钥')),
                ],
                selected: {tab},
                onSelectionChanged: (s) => setState(() {
                  tab = s.first;
                  expanded.clear();
                }),
              ),
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
                              Text(
                                _title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _subtitle,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          rows.isEmpty ? '' : '共 ${rows.length} 条',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6E778F),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      const EmptyHint('暂无数据')
                    else
                      for (var i = 0; i < rows.length; i++) ...[
                        _detailRow(context, rows[i], i, rows.length),
                        if (i != rows.length - 1) const SizedBox(height: 9),
                      ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '数据来自 magpie 用量接口 · $_title',
                style: const TextStyle(fontSize: 10, color: Color(0xFF6E778F)),
              ),
            ),
          ],
        );
      },
    );
  }

  String get _title {
    switch (tab) {
      case 'sessions':
        return '会话用量';
      case 'accounts':
        return '账号用量';
      case 'callers':
        return '调用方用量';
      default:
        return '供应商密钥';
    }
  }

  String get _subtitle {
    switch (tab) {
      case 'sessions':
        return '按调用次数排序，点击查看明细';
      case 'accounts':
        return '账号已打码，点击查看明细';
      case 'callers':
        return '按调用方密钥统计';
      default:
        return '按供应商密钥统计';
    }
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> u) {
    List<Map<String, dynamic>> raw;
    switch (tab) {
      case 'sessions':
        raw = asMapList(u['sessions']);
        break;
      case 'accounts':
        raw = asMapList(u['accounts']);
        break;
      case 'callers':
        raw = asMapList(u['callerKeys']);
        break;
      default:
        raw = asMapList(u['providerKeys']);
        break;
    }
    raw.sort((a, b) => asDouble(b['calls']).compareTo(asDouble(a['calls'])));
    return raw;
  }

  String _costLabel(Map<String, dynamic> r) {
    final cost = asDouble(r['cost']);
    if (cost > 0) return fmtMoney(cost);
    if (asDouble(r['credits']) > 0) {
      return '${asDouble(r['credits']).toStringAsFixed(1)} 信用';
    }
    return '';
  }

  (String, String) _labels(Map<String, dynamic> r) {
    switch (tab) {
      case 'sessions':
        return (
          '${r['agent'] ?? '未知'} · #${shortId((r['id'] ?? '').toString())}',
          [
            _costLabel(r),
            '${fmtCompact(asInt(r['input']) + asInt(r['output']))} tokens',
            if (asInt(r['errors']) > 0) '错误 ${fmtInt(r['errors'])}',
          ].where((e) => e.isNotEmpty).join(' · '),
        );
      case 'accounts':
        return (
          maskAccount((r['account'] ?? r['name'] ?? r['id'] ?? '?').toString()),
          [
            if (r['provider'] != null) r['provider'].toString(),
            _costLabel(r),
          ].where((e) => e.isNotEmpty).join(' · '),
        );
      case 'callers':
        return (
          (r['name'] ?? r['callerKeyName'] ?? shortId((r['callerKeyId'] ?? r['id'] ?? '?').toString()))
              .toString(),
          [
            _costLabel(r),
            if (asInt(r['errors']) > 0) '错误 ${fmtInt(r['errors'])}',
            if (asInt(r['unpriced']) > 0) '未计价 ${fmtInt(r['unpriced'])}',
          ].where((e) => e.isNotEmpty).join(' · '),
        );
      default:
        return (
          '${r['provider'] ?? '?'} · ${r['providerKeyName'] ?? shortId((r['providerKeyId'] ?? r['id'] ?? '?').toString())}',
          [
            _costLabel(r),
            '${fmtInt(r['calls'])} 次',
          ].where((e) => e.isNotEmpty).join(' · '),
        );
    }
  }

  Widget _detailRow(
    BuildContext context,
    Map<String, dynamic> r,
    int index,
    int total,
  ) {
    final key = '$tab:$index';
    final isOpen = expanded.contains(key);
    final labels = _labels(r);
    final calls = asDouble(r['calls']);
    final maxCalls = total == 0
        ? 1.0
        : asDouble(_rows(widget.state.usage ?? {}).first['calls']);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            if (isOpen) {
              expanded.remove(key);
            } else {
              expanded.add(key);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labels.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            labels.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: (calls / maxCalls).clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor: AppColors.surfaceHigh,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scheme.primary.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          fmtCompact(calls),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        ExpandChevron(open: isOpen),
                      ],
                    ),
                  ],
                ),
                if (isOpen) ...[
                  const SizedBox(height: 9),
                  Divider(color: AppColors.outline.withValues(alpha: 0.6)),
                  const SizedBox(height: 9),
                  _detailBody(r),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailBody(Map<String, dynamic> r) {
    final timed = asDouble(r['timed']);
    final ttft = timed > 0 ? asDouble(r['ttft_ms']) / timed : 0.0;
    final decodeMs = asDouble(r['decode_ms']);
    final decode =
        decodeMs > 0 ? asDouble(r['decode_out']) / (decodeMs / 1000) : 0.0;
    final cells = <(String, String)>[
      ('输入', fmtCompact(r['input'])),
      ('输出', fmtCompact(r['output'])),
      ('缓存读', fmtCompact(r['cache_read'])),
      ('缓存写', fmtCompact(r['cache_write'])),
      ('推理', fmtCompact(r['reasoning'])),
      ('信用', asDouble(r['credits']) > 0 ? asDouble(r['credits']).toStringAsFixed(1) : '—'),
      ('平均首字', ttft > 0 ? fmtMs(ttft) : '—'),
      ('解码', decode > 0 ? '${decode.round()} t/s' : '—'),
      ('未计价', fmtInt(r['unpriced'])),
      ('计时请求', fmtInt(r['timed'])),
    ];

    return Column(
      children: [
        for (var i = 0; i < cells.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                Expanded(child: _cell(cells[i])),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < cells.length
                      ? _cell(cells[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell((String, String) cell) {
    return Row(
      children: [
        Text(
          cell.$1,
          style: const TextStyle(
            fontSize: 10.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          cell.$2,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
