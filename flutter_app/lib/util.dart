import 'dart:math' as math;

int asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  return <Map<String, dynamic>>[];
}

String fmtInt(dynamic v) {
  final n = asInt(v);
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String fmtCompact(dynamic v) {
  final n = asDouble(v);
  if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return n.round().toString();
}

String fmtMoney(dynamic v) {
  final n = asDouble(v);
  if (n > 0 && n < 0.01) return '\$${n.toStringAsFixed(4)}';
  if (n >= 10000) return '\$${(n / 1000).toStringAsFixed(1)}K';
  return '\$${n.toStringAsFixed(2)}';
}

String fmtMs(dynamic v) {
  final n = asDouble(v);
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}s';
  return '${n.round()}ms';
}

String _pad2(int n) => n < 10 ? '0$n' : '$n';

String fmtClock(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  return '${_pad2(d.hour)}:${_pad2(d.minute)}:${_pad2(d.second)}';
}

String fmtUntil(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final diff = d.difference(DateTime.now());
  if (diff.isNegative) return '即将重置';
  if (diff.inDays >= 1) return '${diff.inDays} 天 ${diff.inHours % 24} 小时';
  if (diff.inHours > 0) return '${diff.inHours} 小时 ${diff.inMinutes % 60} 分';
  return '${math.max(1, diff.inMinutes)} 分钟';
}

String fmtDuration(double seconds) {
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  final m = seconds ~/ 60;
  final s = (seconds % 60).floor();
  return '${m}m${s}s';
}

String maskAccount(String? raw) {
  final s = raw ?? '';
  final at = s.indexOf('@');
  if (at > 0) {
    final user = s.substring(0, at);
    final domain = s.substring(at + 1);
    if (user.length <= 2) {
      return '${user.isEmpty ? '*' : user[0]}***@$domain';
    }
    return '${user.substring(0, 2)}***${user.substring(user.length - 1)}@$domain';
  }
  if (RegExp(r'^1\d{10}$').hasMatch(s)) {
    return '${s.substring(0, 3)}****${s.substring(s.length - 4)}';
  }
  if (s.length > 14) {
    return '${s.substring(0, 6)}…${s.substring(s.length - 4)}';
  }
  return s;
}

String shortId(String? raw) {
  final s = raw ?? '';
  if (s.length > 12) {
    return '${s.substring(0, 8)}…${s.substring(s.length - 4)}';
  }
  return s;
}

String routeKey(Map<String, dynamic> r) {
  final id = r['id'];
  if (id != null) return id.toString();
  return (r['seq'] ?? '').toString();
}

String periodLabel(String p) {
  switch (p) {
    case 'today':
      return '今日';
    case '7d':
      return '7 天';
    case '30d':
      return '30 天';
    default:
      return '全部';
  }
}

String decodePartKind(String? kind) {
  switch (kind) {
    case 'system':
      return '系统';
    case 'tools':
      return '工具';
    case 'memory':
      return '记忆';
    case 'files':
      return '文件';
    case 'messages':
      return '消息';
    case 'history':
      return '历史';
    case 'results':
      return '结果';
    case 'chat':
      return '对话';
    case 'user':
      return '用户';
    case 'assistant':
      return '助手';
    case 'tool_results':
      return '工具结果';
    case 'context':
      return '上下文';
    default:
      return kind ?? '其它';
  }
}
