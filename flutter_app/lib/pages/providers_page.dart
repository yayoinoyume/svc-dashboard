import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class ProvidersPage extends StatefulWidget {
  final AppState state;
  const ProvidersPage({super.key, required this.state});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  final TextEditingController search = TextEditingController();
  final Set<String> expanded = {};

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.state.providersRev,
      builder: (context, _, __) {
        final data = widget.state.providers;
        if (data == null) {
          return const Center(child: EmptyHint('正在加载供应商…'));
        }
        final all = asMapList(data['providers']);
        final q = search.text.trim().toLowerCase();
        final list = all.where((p) {
          if (q.isEmpty) return true;
          return '${p['name'] ?? ''} ${p['id'] ?? ''} ${p['host'] ?? ''}'
              .toLowerCase()
              .contains(q);
        }).toList();

        list.sort((a, b) {
          final ra = (a['ready'] == true && a['off'] != true) ? 1 : 0;
          final rb = (b['ready'] == true && b['off'] != true) ? 1 : 0;
          if (ra != rb) return rb - ra;
          return (a['name'] ?? a['id'] ?? '')
              .toString()
              .compareTo((b['name'] ?? b['id'] ?? '').toString());
        });

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '搜索供应商或域名',
                prefixIcon: Icon(Icons.search_rounded, size: 19),
              ),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const EmptyHint('没有匹配的供应商')
            else
              for (final p in list) ...[
                _providerCard(context, p),
                const SizedBox(height: 9),
              ],
            const SizedBox(height: 4),
            Center(
              child: Text(
                '共 ${all.length} 个 · ${all.where((p) => p['ready'] == true && p['off'] != true).length} 个在线'
                '${q.isEmpty ? '' : ' · 筛选出 ${list.length} 个'}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF6E778F)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _providerCard(BuildContext context, Map<String, dynamic> p) {
    final pid = (p['id'] ?? p['name'] ?? '?').toString();
    final isOpen = expanded.contains(pid);
    final models = asMapList(p['models']);
    final onCount = models.where((m) => m['on'] == true).length;
    final isOff = p['off'] == true;
    final ready = p['ready'] == true;
    final stateColor = isOff
        ? AppColors.error
        : ready
            ? AppColors.success
            : AppColors.onSurfaceVariant;
    final stateText = isOff ? '停用' : (ready ? '在线' : '离线');
    final name = (p['name'] ?? p['id'] ?? '未知').toString();

    final sub = [
      '${models.length} 个模型',
      if (models.isNotEmpty && onCount != models.length) '$onCount 已启用',
      if (p['host'] != null) p['host'].toString(),
    ].join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          if (isOpen) {
            expanded.remove(pid);
          } else {
            expanded.add(pid);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          sub,
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
                  StatusPill(text: stateText, color: stateColor, dot: true),
                  const SizedBox(width: 4),
                  ExpandChevron(open: isOpen),
                ],
              ),
              if (isOpen) ...[
                const SizedBox(height: 11),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final m in models.take(12))
                      _modelChip(
                        (m['name'] ?? m['id'] ?? '?').toString(),
                        m['on'] == true,
                      ),
                    if (models.length > 12)
                      _modelChip('+${models.length - 12}', false),
                    if (models.isEmpty) _modelChip('暂无模型清单', false),
                  ],
                ),
                _extras(context, p),
                if (models.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Divider(color: AppColors.outline.withValues(alpha: 0.6)),
                  const SizedBox(height: 9),
                  for (final m in models.take(8)) _modelRow(context, m),
                  if (models.length > 8)
                    Text(
                      '还有 ${models.length - 8} 个模型',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF6E778F),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _modelChip(String text, bool on) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: on
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: on
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
              : AppColors.outline,
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: on
              ? Theme.of(context).colorScheme.primary
              : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _extras(BuildContext context, Map<String, dynamic> p) {
    final bits = <String>[];
    final speaks = (p['speaks'] as List?) ?? [];
    if (speaks.isNotEmpty) bits.add(speaks.join(' / '));
    final keys = (p['keyList'] as List?) ?? [];
    if (keys.isNotEmpty) {
      bits.add(
        '密钥 ${keys.map((k) => (k['name'] ?? 'key').toString()).join('、')}',
      );
    }
    if (p['maxConcurrency'] != null) {
      bits.add('并发 ${p['maxConcurrency']}');
    }
    if (bits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        bits.join(' · '),
        style: const TextStyle(
          fontSize: 9.5,
          color: Color(0xFF6E778F),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _modelRow(BuildContext context, Map<String, dynamic> m) {
    final price = m['list'] is Map ? m['list'] as Map : null;
    final bits = <String>[];
    if (m['context'] != null) bits.add('上下文 ${fmtCompact(m['context'])}');
    if (m['output'] != null) bits.add('输出 ${fmtCompact(m['output'])}');
    if (price != null && price['input'] != null) {
      bits.add('\$${price['input']} / \$${price['output']}');
    }
    final efforts = (m['efforts'] as List?) ?? [];
    if (efforts.isNotEmpty) bits.add(efforts.join('/'));
    if (m['images'] == true) bits.add('图片');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (m['name'] ?? m['id'] ?? '?').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: m['on'] == true
                  ? AppColors.onSurface
                  : AppColors.onSurfaceVariant,
            ),
          ),
          Text(
            bits.join(' · '),
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
