import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

const _avatarPalette = [
  Color(0xFF9B7BB8),
  Color(0xFF7FA6C9),
  Color(0xFF7BC9A6),
  Color(0xFFD9B36C),
  Color(0xFFC98FA0),
  Color(0xFF8E9BB3),
];

Color _colorFor(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = (h * 31 + s.codeUnitAt(i)) & 0x7fffffff;
  }
  return _avatarPalette[h % _avatarPalette.length];
}

String _initial(String s) {
  final t = s.trim();
  return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
}

class QuotasPage extends StatefulWidget {
  final AppState state;
  const QuotasPage({super.key, required this.state});

  @override
  State<QuotasPage> createState() => _QuotasPageState();
}

class _QuotasPageState extends State<QuotasPage> {
  final Set<String> expanded = {};

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final list = asMapList(widget.state.quotas)
            .where((q) => (q['windows'] as List?)?.isNotEmpty == true)
            .toList();

        if (list.isEmpty) {
          return const Center(child: EmptyHint('暂无配额数据'));
        }

        for (final q in list) {
          var minRemain = 100.0;
          for (final w in asMapList(q['windows'])) {
            final remain = 100 - asDouble(w['used']).clamp(0, 100);
            if (remain < minRemain) minRemain = remain;
          }
          q['_min'] = minRemain;
        }
        list.sort((a, b) => asDouble(a['_min']).compareTo(asDouble(b['_min'])));

        final allRemain = <double>[];
        var lowCount = 0;
        for (final q in list) {
          for (final w in asMapList(q['windows'])) {
            final remain = 100 - asDouble(w['used']).clamp(0, 100);
            allRemain.add(remain);
            if (remain < 30) lowCount++;
          }
        }
        final health = allRemain.isEmpty
            ? 0.0
            : allRemain.reduce((a, b) => a + b) / allRemain.length;
        final healthColor = health >= 60
            ? AppColors.success
            : health >= 30
                ? AppColors.warning
                : AppColors.error;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    RingChart(
                      percent: health,
                      color: healthColor,
                      center: '${health.round()}%',
                      caption: '健康度',
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '额度总览',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${list.length} 个供应商 · ${allRemain.length} 个额度窗口'
                            '${lowCount > 0 ? ' · $lowCount 项低于 30%' : ' · 整体充足'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              _Legend(color: AppColors.success, text: '充足'),
                              _Legend(color: AppColors.warning, text: '偏低'),
                              _Legend(color: AppColors.error, text: '告急'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final q in list) ...[
              _quotaCard(context, q),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            const Center(
              child: Text(
                '按最低剩余额度排序 · 数据来自 magpie',
                style: TextStyle(fontSize: 10, color: Color(0xFF6E778F)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _quotaCard(BuildContext context, Map<String, dynamic> q) {
    final qid = (q['provider'] ?? q['name'] ?? 'quota').toString();
    final windows = asMapList(q['windows']);
    final isOpen = expanded.contains(qid);
    final visible = isOpen ? windows : windows.take(4).toList();
    final minRemain = asDouble(q['_min']);
    final pctColor = minRemain >= 60
        ? AppColors.success
        : minRemain >= 30
            ? AppColors.warning
            : AppColors.error;
    final color = _colorFor(qid);

    final seen = <String, int>{};
    final labels = <String>[];
    for (final w in windows) {
      final base = (w['name'] ?? '额度').toString();
      seen[base] = (seen[base] ?? 0) + 1;
      labels.add(seen[base]! > 1 ? '$base #${seen[base]}' : base);
    }
    final offset = windows.length - visible.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initial((q['name'] ?? q['provider'] ?? '?').toString()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (q['name'] ?? q['provider'] ?? '未知').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        (q['plan'] ?? q['provider'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${minRemain.round()}%',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: pctColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      '最低',
                      style: TextStyle(fontSize: 9, color: Color(0xFF6E778F)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 11),
            for (var i = 0; i < visible.length; i++)
              _window(context, visible[i], labels[windows.indexOf(visible[i])]),
            if (windows.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    if (isOpen) {
                      expanded.remove(qid);
                    } else {
                      expanded.add(qid);
                    }
                  }),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.outline, width: 0.8),
                    foregroundColor: AppColors.onSurfaceVariant,
                    minimumSize: const Size.fromHeight(36),
                    textStyle: const TextStyle(fontSize: 11.5),
                  ),
                  child: Text(isOpen ? '收起' : '展开全部 ${windows.length} 项'),
                ),
              ),
            if (offset > 0 && !isOpen)
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _window(BuildContext context, Map<String, dynamic> w, String label) {
    final used = asDouble(w['used']).clamp(0, 100);
    final remain = 100 - used;
    final color = remain >= 60
        ? AppColors.success
        : remain >= 30
            ? AppColors.warning
            : AppColors.error;
    final detail = (w['display'] ??
            (w['amount'] != null && w['limit'] != null
                ? '${fmtInt(w['amount'])} / ${fmtInt(w['limit'])}'
                : ''))
        .toString();
    final reset = w['resetsAt'] != null
        ? '重置 ${fmtUntil(w['resetsAt'].toString())}'
        : '';

    return Padding(
      padding: EdgeInsets.only(top: label == '' ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              Text(
                '剩余 ${remain.round()}%',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: remain / 100,
              minHeight: 4,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            [detail, reset].where((e) => e.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xFF6E778F),
            ),
          ),
        ],
      ),
    );
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
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
