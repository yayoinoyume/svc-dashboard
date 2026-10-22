import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 流向图节点
class FlowNode {
  final String key;
  final String label;
  final String sub;
  final Color dot;
  final int count;
  final bool live;
  final bool err;

  const FlowNode({
    required this.key,
    required this.label,
    required this.sub,
    required this.dot,
    required this.count,
    this.live = false,
    this.err = false,
  });
}

/// 一条连线（客户端 → 目标）
class FlowLink {
  final String from;
  final String to;
  final int count;
  final bool live;
  final bool err;

  const FlowLink({
    required this.from,
    required this.to,
    required this.count,
    this.live = false,
    this.err = false,
  });
}

/// 三列流向图：客户端 → 网关 → 目标。
/// 激活链路高亮并带流动虚线，不播放额外动画元素。
class FlowDiagram extends StatefulWidget {
  final List<FlowNode> clients;
  final List<FlowNode> targets;
  final List<FlowLink> links;
  final String? selectedKey;
  final void Function(FlowNode node, bool isClient) onTap;

  const FlowDiagram({
    super.key,
    required this.clients,
    required this.targets,
    required this.links,
    required this.onTap,
    this.selectedKey,
  });

  @override
  State<FlowDiagram> createState() => _FlowDiagramState();
}

class _FlowDiagramState extends State<FlowDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final lay = _Layout.compute(
        box.maxWidth,
        widget.clients.length,
        widget.targets.length,
      );

      return SizedBox(
        height: lay.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => CustomPaint(
                    painter: _FlowPainter(
                      lay: lay,
                      clients: widget.clients,
                      targets: widget.targets,
                      links: widget.links,
                      phase: _anim.value,
                      animate: !_reduced,
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < widget.clients.length; i++)
              _node(
                node: widget.clients[i],
                isClient: true,
                cy: lay.clientY[i],
                height: lay.clientH,
                width: lay.leftW,
                left: 0,
              ),
            for (var i = 0; i < widget.targets.length; i++)
              _node(
                node: widget.targets[i],
                isClient: false,
                cy: lay.targetY[i],
                height: lay.targetH,
                width: lay.rightW,
                left: lay.w - lay.rightW,
              ),
            _hub(lay),
          ],
        ),
      );
    });
  }

  Widget _node({
    required FlowNode node,
    required bool isClient,
    required double cy,
    required double height,
    required double width,
    required double left,
  }) {
    final selected = widget.selectedKey == node.key;
    return Positioned(
      left: left,
      top: cy - height / 2,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(node, isClient),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceHigh : AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? AppColors.seed : AppColors.outline,
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: node.dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      node.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
              if (height >= 40) ...[
                const SizedBox(height: 2),
                Text(
                  node.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8.5,
                    color: AppColors.onSurfaceVariant,
                    height: 1.15,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hub(_Layout lay) {
    return Positioned(
      left: lay.hubCx - 18,
      top: lay.hubCy - 26,
      width: 36,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8E6CA8), Color(0xFF5E4574)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.seed.withValues(alpha: 0.10),
                  blurRadius: 0,
                  spreadRadius: 6,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'M',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '网关',
              style: TextStyle(
                fontSize: 8,
                color: Color(0xFF6E778F),
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Layout {
  final double w;
  final double height;
  final double leftW;
  final double rightW;
  final double hubCx;
  final double hubR;
  final double hubCy;
  final List<double> clientY;
  final List<double> targetY;
  final double clientH;
  final double targetH;

  const _Layout({
    required this.w,
    required this.height,
    required this.leftW,
    required this.rightW,
    required this.hubCx,
    required this.hubR,
    required this.hubCy,
    required this.clientY,
    required this.targetY,
    required this.clientH,
    required this.targetH,
  });

  static _Layout compute(double w, int nc, int nt) {
    final width = w <= 0 ? 338.0 : w;
    final h = (width * 0.633).clamp(190.0, 232.0).toDouble();
    final sc = _spread(nc, h);
    final st = _spread(nt, h);
    return _Layout(
      w: width,
      height: h,
      leftW: width * 0.278,
      rightW: width * 0.373,
      hubCx: width * 0.453,
      hubR: 18,
      hubCy: h / 2,
      clientY: sc.$1,
      targetY: st.$1,
      clientH: sc.$2,
      targetH: st.$2,
    );
  }

  static (List<double>, double) _spread(int n, double h) {
    if (n <= 0) return (<double>[], 0);
    final nh = math.min(46.0, math.max(30.0, (h - (n + 1) * 10) / n));
    final gap = (h - n * nh) / (n + 1);
    return (
      List<double>.generate(n, (i) => gap + nh / 2 + i * (nh + gap)),
      nh,
    );
  }
}

class _FlowPainter extends CustomPainter {
  final _Layout lay;
  final List<FlowNode> clients;
  final List<FlowNode> targets;
  final List<FlowLink> links;
  final double phase;
  final bool animate;

  _FlowPainter({
    required this.lay,
    required this.clients,
    required this.targets,
    required this.links,
    required this.phase,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ci = <String, int>{};
    for (var i = 0; i < clients.length; i++) {
      ci[clients[i].key] = i;
    }
    final ti = <String, int>{};
    for (var i = 0; i < targets.length; i++) {
      ti[targets[i].key] = i;
    }

    const idle = Color(0x33A9B0C6);
    const live = Color(0xFF9B7BB8);
    const err = Color(0xFFE57373);
    const glow = Color(0xFFCDB8E2);

    for (final l in links) {
      final a = ci[l.from];
      final b = ti[l.to];
      if (a == null || b == null) continue;

      final y1 = lay.clientY[a];
      final y2 = lay.targetY[b];
      final p1 = _curve(
        Offset(lay.leftW, y1),
        Offset(lay.hubCx - lay.hubR - 5, lay.hubCy),
      );
      final p2 = _curve(
        Offset(lay.hubCx + lay.hubR + 5, lay.hubCy),
        Offset(lay.w - lay.rightW, y2),
      );

      final color = l.err
          ? err
          : l.live
              ? live
              : idle;
      final width =
          1 + math.min(1.8, math.log(l.count + 1) / math.ln2 * 0.34);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = color;

      canvas.drawPath(p1, paint);
      canvas.drawPath(p2, paint);

      if (l.live) {
        final dash = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.6
          ..color = glow;
        final offset = animate ? phase * 12 : 0.0;
        canvas.drawPath(_dash(p1, 3, 9, offset), dash);
        canvas.drawPath(_dash(p2, 3, 9, offset), dash);
      }
    }
  }

  Path _curve(Offset a, Offset b) {
    final dx = math.max(14.0, (b.dx - a.dx) * 0.5);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
  }

  Path _dash(Path src, double dash, double gap, double offset) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var d = offset % (dash + gap);
      while (d < m.length) {
        out.addPath(
          m.extractPath(d, math.min(d + dash, m.length)),
          Offset.zero,
        );
        d += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) =>
      old.phase != phase ||
      old.links != links ||
      old.clients != clients ||
      old.targets != targets;
}
