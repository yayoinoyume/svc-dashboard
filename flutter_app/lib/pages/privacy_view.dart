import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

/// magpie 上报的掩码类型（/api/masking/summary 的 kinds[].name）
const _kindNames = <String, String>{
  'API_KEY': 'API 密钥',
  'PRIVATE_KEY': '私钥',
  'TOKEN': '令牌',
  'PASSWORD': '密码',
  'SECRET': '机密',
  'EMAIL': '邮箱',
  'PHONE': '手机号',
  'ID_CARD': '身份证号',
  'BANK_CARD': '银行卡',
  'PERSON': '姓名',
  'ADDRESS': '地址',
  'ACCOUNT': '账号',
  'SSN': '社保号',
  'PASSPORT': '护照',
  'IBAN': 'IBAN',
  'BIRTHDAY': '生日',
  'MAC': 'MAC 地址',
  'SERIAL': '序列号',
  'USERNAME': '用户名',
  'HOSTNAME': '主机名',
  'IP': 'IP 地址',
  'BUCKET': '存储桶',
  'TERM': '自定义词',
};

const _byNames = <String, String>{
  'rule': '内置规则',
  'yours': '自定义规则',
  'word': '自定义词',
  'model': '本地模型',
  'known': '见过的值',
};

const _whatNames = <String, String>{
  'chat': '对话',
  'search': '联网搜索',
  'image': '图片',
  'video': '视频',
  'decide': '系统一',
  'embeddings': '向量',
  'audio': '音频',
};

const _palette = <Color>[
  Color(0xFF9B7BB8),
  Color(0xFF7BC9A6),
  Color(0xFFD9B36C),
  Color(0xFF6FA8DC),
  Color(0xFFE57373),
  Color(0xFFA0D2EB),
  Color(0xFFC3A6E0),
];

String _kindName(String k) => _kindNames[k] ?? k;

/// 打码后的样子：开头的字符 + 固定长度的圆点
String _shape(String head, int len) {
  final rest = math.max(1, math.min(len - head.length, 8));
  return '$head${List.filled(rest, '•').join()}';
}

Color _kindColor(String kind, List<Map<String, dynamic>> kinds) {
  final i = kinds.indexWhere((k) => k['name'] == kind);
  return _palette[(i < 0 ? 0 : i) % _palette.length];
}

/// 「明细 → 隐私」子页。数据来自 /api/masking/*，与网关设置里的隐私页同源。
class PrivacyView extends StatefulWidget {
  final AppState state;
  const PrivacyView({super.key, required this.state});

  @override
  State<PrivacyView> createState() => _PrivacyViewState();
}

class _PrivacyViewState extends State<PrivacyView> {
  final Set<int> _open = {};

  /// 占位符 → 原文；null 表示网关重启后已经忘了
  final Map<String, String?> _revealed = {};
  String? _dayPick;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    // 子页一进来就开始拉数据，之后每 15 秒自己刷新
    s.startMaskingLive();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: s.maskingRev,
      builder: (context, _, __) {
        if (s.maskingUnsupported) return _unsupported();
        final sum = s.maskingSummary;
        if (sum == null) return _loading();

        final kinds = asMapList(sum['kinds']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(sum),
            const SizedBox(height: 12),
            _breakdown(sum, kinds),
            if (asMapList(sum['agents']).isNotEmpty &&
                asMapList(sum['providers']).isNotEmpty) ...[
              const SizedBox(height: 12),
              _flow(sum),
            ],
            if (asMapList(sum['values']).isNotEmpty) ...[
              const SizedBox(height: 12),
              _topValues(sum, kinds),
            ],
            const SizedBox(height: 12),
            _records(kinds),
          ],
        );
      },
    );
  }

  // ---------- 各卡片 ----------

  Widget _hero(Map<String, dynamic> sum) {
    final days = asMapList(sum['days']);
    final n = asInt(sum['n']);
    if (days.isEmpty && n == 0) return _emptyMasking();

    final maxDay = days.fold<int>(1, (a, d) => math.max(a, asInt(d['n'])));
    final picked = _dayPick == null
        ? null
        : days.cast<Map<String, dynamic>?>().firstWhere(
              (d) => d?['day'] == _dayPick,
              orElse: () => null,
            );

    return _card(
      title: '本机掩码',
      subtitle: '请求离开网关前换掉，回答里再放回去',
      trailing: _daysSwitch(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AnimatedNumber(
                value: n.toDouble(),
                format: (v) => fmtInt(v.round()),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '个值被掩码',
                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _metaBit('${fmtInt(sum['distinct'])} 个不同值'),
              _metaBit('${fmtInt(sum['requests'])} 个请求'),
              if (asInt(sum['blocked']) > 0)
                _metaBit(
                  '${fmtInt(sum['blocked'])} 个请求被拦截',
                  color: AppColors.error,
                ),
              if (asInt(sum['warned']) > 0)
                _metaBit(
                  '${fmtInt(sum['warned'])} 个值原文放行',
                  color: AppColors.warning,
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: days.length > 14 ? 1 : 2.5,
                      ),
                      child: _bar(
                        day: days[i],
                        max: maxDay,
                        isToday: i == days.length - 1,
                        selected: _dayPick == days[i]['day'],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(_dayLabel(days.first['day'] as String?),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6E778F))),
              const Spacer(),
              Text(_dayLabel(days.last['day'] as String?),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6E778F))),
            ],
          ),
          if (picked != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '${_dayLabel(picked['day'] as String?)} · '
                '${fmtInt(picked['n'])} 个值 · ${fmtInt(picked['requests'])} 个请求',
                style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _daysSwitch() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in const [7, 30])
          GestureDetector(
            onTap: () => s.setMaskingDays(d),
            child: Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: s.maskingDays == d
                    ? AppColors.surfaceHigh
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$d 天',
                style: TextStyle(
                  fontSize: 11,
                  color: s.maskingDays == d
                      ? AppColors.onSurface
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar({
    required Map<String, dynamic> day,
    required int max,
    required bool isToday,
    required bool selected,
  }) {
    final n = asInt(day['n']);
    final ratio =
        n == 0 ? 0.0 : math.max(0.06, n / max).toDouble();
    final base = isToday ? const Color(0xFFC9AEE2) : AppColors.seed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(
        () => _dayPick = selected ? null : day['day'] as String?,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: ratio),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) => FractionallySizedBox(
            heightFactor: t == 0 ? 0.02 : t,
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? base
                    : base.withValues(alpha: n == 0 ? 0.18 : 0.72),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                  bottom: Radius.circular(1),
                ),
                border: selected
                    ? Border.all(color: const Color(0xFFC9AEE2), width: 1.2)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _breakdown(Map<String, dynamic> sum, List<Map<String, dynamic>> kinds) {
    final top = kinds.take(6).toList();
    final rest = kinds.skip(6).toList();
    final rows = [...top];
    if (rest.isNotEmpty) {
      rows.add({
        'name': '__other',
        'n': rest.fold<int>(0, (a, k) => a + asInt(k['n'])),
      });
    }
    final maxN = rows.isEmpty
        ? 1
        : rows.fold<int>(1, (a, r) => math.max(a, asInt(r['n'])));

    final byMap = (sum['by'] as Map?)?.cast<String, dynamic>() ?? const {};
    final byList = byMap.entries.toList()
      ..sort((a, b) => asInt(b.value).compareTo(asInt(a.value)));
    final byTotal = byList.fold<int>(1, (a, e) => a + asInt(e.value));

    return _card(
      title: '按类型',
      subtitle: '掩码次数',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _ledgerRow(rows[i], i, maxN),
            if (i != rows.length - 1) const SizedBox(height: 9),
          ],
          if (byList.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '谁发现的 · ${fmtInt(sum['distinct'])} 个不同值',
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF6E778F),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var i = 0; i < byList.length; i++)
                      Expanded(
                        flex: math.max(1, asInt(byList[i].value)),
                        child: Container(
                          color: _palette[i % _palette.length],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              children: [
                for (var i = 0; i < byList.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _byNames[byList[i].key] ?? byList[i].key,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        fmtInt(byList[i].value),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '共 ${fmtInt(byTotal)} 个不同值',
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF6E778F)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ledgerRow(Map<String, dynamic> row, int index, int maxN) {
    final isOther = row['name'] == '__other';
    final name = isOther ? '其他' : _kindName(row['name'] as String? ?? '');
    final n = asInt(row['n']);
    final color = isOther ? const Color(0xFF6E778F) : _palette[index % _palette.length];
    final selected = !isOther && s.maskKind == row['name'];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isOther
          ? null
          : () => s.setMaskFilter(kind: selected ? '' : row['name'] as String),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                fmtInt(n),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 3,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: n / maxN),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, t, __) => LinearProgressIndicator(
                  value: t,
                  minHeight: 3,
                  backgroundColor: AppColors.surfaceHigh,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _flow(Map<String, dynamic> sum) {
    return _card(
      title: '谁发的 · 去哪里',
      subtitle: '线越粗，经过的掩码值越多',
      child: _MaskFlow(
        agents: asMapList(sum['agents']).take(3).toList(),
        providers: asMapList(sum['providers']).take(4).toList(),
        onTap: (side, name) => s.setMaskFilter(
          agent: side == 'agent' ? name : '',
          provider: side == 'provider' ? name : '',
        ),
      ),
    );
  }

  Widget _topValues(Map<String, dynamic> sum, List<Map<String, dynamic>> kinds) {
    final values = asMapList(sum['values']).take(8).toList();
    return _card(
      title: '最常掩码',
      subtitle: '点一下看原文，原文只在网关内存里',
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final v in values)
            _valueChip(
              placeholder: v['p'] as String? ?? '',
              kind: v['kind'] as String? ?? '',
              head: v['head'] as String? ?? '',
              len: asInt(v['len']),
              count: asInt(v['n']),
              kinds: kinds,
            ),
        ],
      ),
    );
  }

  Widget _valueChip({
    required String placeholder,
    required String kind,
    required String head,
    required int len,
    required int count,
    required List<Map<String, dynamic>> kinds,
  }) {
    final known = _revealed.containsKey(placeholder);
    final value = _revealed[placeholder];
    final text = known ? (value ?? '（已不在内存）') : _shape(head, len);

    return GestureDetector(
      onTap: () => _toggleReveal(placeholder),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: known
              ? AppColors.seed.withValues(alpha: 0.16)
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: known ? AppColors.seed.withValues(alpha: 0.6) : AppColors.outline,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _kindColor(kind, kinds),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _kindName(kind),
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF6E778F)),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: known ? const Color(0xFFD9C7EA) : AppColors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '×$count',
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF6E778F)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _records(List<Map<String, dynamic>> kinds) {
    final rows = s.maskingRecords;
    final filtering = s.maskKind.isNotEmpty ||
        s.maskBy.isNotEmpty ||
        s.maskAgent.isNotEmpty ||
        s.maskProvider.isNotEmpty;

    return _card(
      title: '逐条记录',
      subtitle: '页面打开时每 15 秒刷新',
      trailing: filtering
          ? GestureDetector(
              onTap: () => s.setMaskFilter(),
              child: const Text(
                '清除筛选',
                style: TextStyle(fontSize: 11, color: AppColors.seed),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (filtering) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (s.maskKind.isNotEmpty) _filterTag(_kindName(s.maskKind)),
                if (s.maskBy.isNotEmpty)
                  _filterTag(_byNames[s.maskBy] ?? s.maskBy),
                if (s.maskAgent.isNotEmpty) _filterTag(s.maskAgent),
                if (s.maskProvider.isNotEmpty) _filterTag(s.maskProvider),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (s.maskingRecordsLoading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (rows.isEmpty)
            EmptyHint(filtering ? '没有符合条件的记录' : '还没有被掩码的请求')
          else
            for (var i = 0; i < rows.length; i++) ...[
              _record(rows[i], kinds),
              if (i != rows.length - 1) const SizedBox(height: 8),
            ],
          if (s.maskingMore) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: s.maskingRecordsLoading
                  ? null
                  : () => s.loadMaskingRecords(more: true),
              child: const Text('再看 40 条', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
      ),
    );
  }

  Widget _record(Map<String, dynamic> r, List<Map<String, dynamic>> kinds) {
    final key = asInt(r['key']);
    final open = _open.contains(key);
    final values = asMapList(r['values']);
    final blocked = r['blocked'] == true;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => setState(() {
            if (open) {
              _open.remove(key);
            } else {
              _open.add(key);
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
                            '${_hhmm(r['t'])} · ${_whatNames[r['what']] ?? r['what'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF6E778F),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${r['agent'] ?? '未知'} → ${r['provider'] ?? '未知'}'
                            '${r['model'] == null ? '' : ' · ${r['model']}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: [
                              for (final v in values)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceHigh,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '${_kindName(v['k'] as String? ?? '')} ×${asInt(v['n'])}',
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              if (blocked)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: const Text(
                                    '已拦截',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: Color(0xFFF0A5A5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ExpandChevron(open: open),
                  ],
                ),
                if (open) ...[
                  const SizedBox(height: 9),
                  Divider(color: AppColors.outline.withValues(alpha: 0.6)),
                  const SizedBox(height: 7),
                  for (final v in values)
                    _recordValue(v, kinds),
                  if ((r['snips'] as Map?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '供应商看到的原文',
                      style: TextStyle(fontSize: 9.5, color: Color(0xFF6E778F)),
                    ),
                    const SizedBox(height: 5),
                    ..._snips(r, kinds),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordValue(Map<String, dynamic> v, List<Map<String, dynamic>> kinds) {
    final p = v['p'] as String? ?? '';
    final known = _revealed.containsKey(p);
    final value = _revealed[p];
    final head = v['h'] as String? ?? '';
    final len = asInt(v['l']);
    return GestureDetector(
      onTap: () => _toggleReveal(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(Icons.circle, size: 5, color: _kindColor(v['k'] as String? ?? '', kinds)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_kindName(v['k'] as String? ?? '')} · ${_byNames[v['b']] ?? v['b'] ?? ''}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              known ? (value ?? '（已不在内存）') : _shape(head, len),
              style: TextStyle(
                fontSize: 10.5,
                color: known ? const Color(0xFFD9C7EA) : AppColors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 原文片段：把 {{XXX}} 用类型色标出来，点一下换成原文
  List<Widget> _snips(Map<String, dynamic> r, List<Map<String, dynamic>> kinds) {
    final snips = (r['snips'] as Map).cast<String, dynamic>();
    final seen = <String>{};
    final out = <Widget>[];
    for (final entry in snips.entries) {
      final text = entry.value;
      if (text is! String || !seen.add(entry.key)) continue;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.55,
                  color: AppColors.onSurfaceVariant,
                ),
                children: _snipSpans(text, kinds),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  List<InlineSpan> _snipSpans(String text, List<Map<String, dynamic>> kinds) {
    final re = RegExp(r'\{\{[^{}\s]{1,64}\}\}');
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > at) {
        spans.add(TextSpan(text: text.substring(at, m.start)));
      }
      final p = m.group(0)!;
      final known = _revealed.containsKey(p);
      spans.add(
        TextSpan(
          text: known ? (_revealed[p] ?? '（已不在内存）') : p,
          style: TextStyle(
            color: known ? const Color(0xFFA9E5C8) : const Color(0xFFD9C7EA),
            backgroundColor:
                (known ? const Color(0xFF7BC9A6) : AppColors.seed)
                    .withValues(alpha: 0.16),
          ),
        ),
      );
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }

  // ---------- 交互 ----------

  Future<void> _toggleReveal(String placeholder) async {
    if (_revealed.containsKey(placeholder)) {
      setState(() => _revealed.remove(placeholder));
      return;
    }
    final v = await s.maskValue(placeholder);
    if (!mounted) return;
    setState(() => _revealed[placeholder] = v);
  }

  // ---------- 状态页 ----------

  Widget _loading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _unsupported() {
    return _card(
      title: '隐私统计不可用',
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text('🔒', style: TextStyle(fontSize: 26)),
            SizedBox(height: 8),
            Text(
              '当前网关版本不支持隐私统计',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              '升级 magpie 到最新版后，这里会显示每个请求被掩码了什么',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFF6E778F)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyMasking() {
    return _card(
      title: '本机掩码',
      subtitle: '还没有任何请求被掩码',
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              '在网关的「设置 → 隐私」里打开\n「掩码密钥」或「掩码个人数据」',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
            SizedBox(height: 6),
            Text(
              '之后每个被换掉的值都会记在这里',
              style: TextStyle(fontSize: 11, color: Color(0xFF6E778F)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- 通用卡片外壳 ----------

Widget _card({
  required String title,
  String? subtitle,
  Widget? trailing,
  required Widget child,
}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
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
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

Widget _metaBit(String text, {Color? color}) {
  return Text(
    text,
    style: TextStyle(
      fontSize: 11,
      color: color ?? AppColors.onSurfaceVariant,
    ),
  );
}

String _dayLabel(String? day) {
  if (day == null || day.length < 10) return '';
  return '${day.substring(5, 7)}/${day.substring(8, 10)}';
}

String _hhmm(dynamic iso) {
  final s = iso?.toString();
  if (s == null || s.isEmpty) return '';
  final d = DateTime.tryParse(s)?.toLocal();
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

// ---------- 流向图：每个客户端 → 网关 → 每个供应商 ----------

class _MaskFlow extends StatefulWidget {
  final List<Map<String, dynamic>> agents;
  final List<Map<String, dynamic>> providers;
  final void Function(String side, String name) onTap;

  const _MaskFlow({
    required this.agents,
    required this.providers,
    required this.onTap,
  });

  @override
  State<_MaskFlow> createState() => _MaskFlowState();
}

class _MaskFlowState extends State<_MaskFlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  static const _leftW = 84.0;
  static const _rightW = 90.0;
  static const _rowH = 34.0;
  static const _nodeH = 28.0;

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduced) {
      _anim.stop();
    } else if (!_anim.isAnimating) {
      _anim.repeat();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  double get _height =>
      math.max(widget.agents.length, widget.providers.length) * _rowH + 12;

  double _yOf(int i, int count) => _height / 2 + (i - (count - 1) / 2) * _rowH;

  @override
  Widget build(BuildContext context) {
    final h = _height;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => CustomPaint(
                    painter: _MaskFlowPainter(
                      agents: widget.agents,
                      providers: widget.providers,
                      leftW: _leftW,
                      rightW: _rightW,
                      height: h,
                      width: w,
                      phase: (_anim.value * 60).round() / 60,
                      animate: !_reduced,
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < widget.agents.length; i++)
              Positioned(
                left: 0,
                top: _yOf(i, widget.agents.length) - _nodeH / 2,
                width: _leftW,
                height: _nodeH,
                child: _node(widget.agents[i], 'agent'),
              ),
            for (var i = 0; i < widget.providers.length; i++)
              Positioned(
                right: 0,
                top: _yOf(i, widget.providers.length) - _nodeH / 2,
                width: _rightW,
                height: _nodeH,
                child: _node(widget.providers[i], 'provider'),
              ),
            Positioned(
              left: w / 2 - 23,
              top: h / 2 - 23,
              child: _hub(),
            ),
          ],
        ),
      );
    });
  }

  Widget _node(Map<String, dynamic> x, String side) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(side, x['name']?.toString() ?? ''),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.outline, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                x['name']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              fmtInt(x['n']),
              style: const TextStyle(fontSize: 9, color: Color(0xFF6E778F)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hub() {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final p = _reduced
            ? 0.5
            : 0.5 + 0.5 * math.sin(_anim.value * 2 * math.pi);
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF191E2C),
            border: Border.all(
              color: AppColors.seed.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.seed.withValues(alpha: 0.2 + 0.12 * p),
                blurRadius: 18 + 6 * p,
                spreadRadius: 2,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.shield_outlined,
            size: 20,
            color: Color(0xFFB79ED0),
          ),
        );
      },
    );
  }
}

class _MaskFlowPainter extends CustomPainter {
  final List<Map<String, dynamic>> agents;
  final List<Map<String, dynamic>> providers;
  final double leftW;
  final double rightW;
  final double height;
  final double width;
  final double phase;
  final bool animate;

  _MaskFlowPainter({
    required this.agents,
    required this.providers,
    required this.leftW,
    required this.rightW,
    required this.height,
    required this.width,
    required this.phase,
    required this.animate,
  });

  double _yOf(int i, int count) => height / 2 + (i - (count - 1) / 2) * 34.0;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...agents, ...providers];
    final maxN = all.fold<int>(
      1,
      (a, x) => math.max(a, asInt(x['n'])),
    );
    const hubR = 30.0;
    final cy = height / 2;

    for (var i = 0; i < agents.length; i++) {
      final n = asInt(agents[i]['n']);
      final y = _yOf(i, agents.length);
      _edge(
        canvas,
        Offset(leftW, y),
        Offset(width / 2 - hubR, cy),
        n / maxN,
        phase + i * 0.31,
        false,
      );
    }
    for (var i = 0; i < providers.length; i++) {
      final n = asInt(providers[i]['n']);
      final y = _yOf(i, providers.length);
      _edge(
        canvas,
        Offset(width / 2 + hubR, cy),
        Offset(width - rightW, y),
        n / maxN,
        phase + i * 0.37 + 0.5,
        true,
      );
    }
  }

  void _edge(
    Canvas canvas,
    Offset a,
    Offset b,
    double ratio,
    double t0,
    bool fromHub,
  ) {
    final dx = (b.dx - a.dx).abs() * 0.5;
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(
        fromHub ? a.dx + dx : a.dx + dx,
        a.dy,
        fromHub ? b.dx - dx : b.dx - dx,
        b.dy,
        b.dx,
        b.dy,
      );

    final widthPx = 0.9 + 2.9 * ratio;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = widthPx;

    final rect = Rect.fromPoints(a, b);
    final safeRect = (rect.width.abs() < 0.5 || rect.height.abs() < 0.5)
        ? Rect.fromLTRB(a.dx, a.dy - 0.5, b.dx, b.dy + 0.5)
        : rect;
    try {
      paint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: fromHub
            ? [AppColors.seed, AppColors.seed.withValues(alpha: 0.35)]
            : [AppColors.seed.withValues(alpha: 0.35), AppColors.seed],
      ).createShader(safeRect);
    } catch (_) {
      paint.color = AppColors.seed;
    }
    canvas.drawPath(path, paint);

    if (!animate) return;

    // 光点
    final it = path.computeMetrics();
    if (it.isEmpty) return;
    final m = it.first;
    if (m.length <= 0) return;
    for (var k = 0; k < 2; k++) {
      final t = (t0 + k / 2) % 1.0;
      final fade = math
          .min(1.0, math.min(t / 0.16, (1 - t) / 0.16))
          .clamp(0.0, 1.0)
          .toDouble();
      if (fade <= 0.02) continue;
      final tan = m.getTangentForOffset(m.length * t);
      if (tan == null) continue;
      final pos = tan.position;
      canvas.drawCircle(
        pos,
        4.5,
        Paint()..color = AppColors.seed.withValues(alpha: 0.16 * fade),
      );
      canvas.drawCircle(
        pos,
        2.0,
        Paint()..color = AppColors.seed.withValues(alpha: 0.85 * fade),
      );
      canvas.drawCircle(
        pos,
        1.0,
        Paint()..color = Colors.white.withValues(alpha: 0.7 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MaskFlowPainter old) =>
      old.phase != phase ||
      old.agents != agents ||
      old.providers != providers ||
      old.width != width ||
      old.height != height;
}
