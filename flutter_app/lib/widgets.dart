import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'util.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
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
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class AnimatedNumber extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle? style;

  const AnimatedNumber({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

class KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? foot;
  final Widget? valueWidget;

  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.foot,
    this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 5),
          valueWidget ??
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          const SizedBox(height: 3),
          Text(
            foot ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF6E778F)),
          ),
        ],
      ),
    );
  }
}

class RankRow extends StatelessWidget {
  final int index;
  final String name;
  final String subtitle;
  final String value;
  final double progress;
  final Color? color;

  const RankRow({
    super.key,
    required this.index,
    required this.name,
    required this.subtitle,
    required this.value,
    required this.progress,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: index == 0 ? scheme.primary : const Color(0xFF6E778F),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0,
                    end: progress.clamp(0.0, 1.0).toDouble(),
                  ),
                  duration: Duration(milliseconds: 420 + index * 55),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceHigh,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        color ?? scheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool dot;

  const StatusPill({
    super.key,
    required this.text,
    required this.color,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final String text;
  const EmptyHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6E778F)),
        ),
      ),
    );
  }
}

class StatStrip extends StatelessWidget {
  final List<(String, String)> items;

  const StatStrip({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.outline, width: 0.8),
              ),
              child: Column(
                children: [
                  Text(
                    items[i].$2,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$1,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class TrendChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final bool money;
  final double height;

  const TrendChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.money = false,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: const EmptyHint('暂无趋势数据'),
      );
    }
    final signature = values.fold<double>(0, (a, b) => a + b) + values.length;
    return TweenAnimationBuilder<double>(
      key: ValueKey(signature.toStringAsFixed(2)),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 680),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox(
        height: height,
        child: CustomPaint(
          painter: _TrendPainter(
            values: values,
            labels: labels,
            color: color,
            textColor: AppColors.onSurfaceVariant,
            gridColor: AppColors.outline,
            money: money,
            progress: t,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final Color textColor;
  final Color gridColor;
  final bool money;
  final double progress;

  _TrendPainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.textColor,
    required this.gridColor,
    required this.money,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 6.0;
    const padR = 6.0;
    const padT = 22.0;
    const padB = 24.0;
    final w = size.width;
    final h = size.height;
    final chartW = w - padL - padR;
    final chartH = h - padT - padB;

    var maxV = 1.0;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;
    for (var i = 0; i < 4; i++) {
      final y = padT + chartH * i / 3;
      canvas.drawLine(Offset(padL, y), Offset(w - padR, y), gridPaint);
    }

    double xAt(int i) => padL + chartW * (values.length == 1 ? 0.5 : i / (values.length - 1));
    double yAt(double v) => padT + chartH * (1 - v / maxV);

    final linePath = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(xAt(i), yAt(values[i]));
      if (i == 0) {
        linePath.moveTo(p.dx, p.dy);
      } else {
        linePath.lineTo(p.dx, p.dy);
      }
    }

    final areaPath = Path.from(linePath)
      ..lineTo(xAt(values.length - 1), h - padB)
      ..lineTo(xAt(0), h - padB)
      ..close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * progress, h));

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, padT, w, chartH));
    canvas.drawPath(areaPath, areaPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    canvas.restore();

    var maxIdx = 0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > values[maxIdx]) maxIdx = i;
    }
    final peak = Offset(xAt(maxIdx), yAt(values[maxIdx]));
    final peakAlpha = ((progress - 0.55) / 0.45).clamp(0.0, 1.0).toDouble();
    if (peakAlpha > 0) {
      canvas.drawCircle(
        peak,
        8,
        Paint()..color = color.withValues(alpha: 0.16 * peakAlpha),
      );
      canvas.drawCircle(
        peak,
        3.2,
        Paint()
          ..color = color.withValues(alpha: peakAlpha)
          ..style = PaintingStyle.fill,
      );
    }

    final peakText = money ? fmtMoney(maxV) : fmtCompact(maxV);
    final tp = TextPainter(
      text: TextSpan(
        text: peakText,
        style: TextStyle(
          color: textColor.withValues(alpha: peakAlpha),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final px = (peak.dx - tp.width / 2).clamp(2.0, w - tp.width - 2);
    tp.paint(canvas, Offset(px, math.max(2.0, peak.dy - 16)));

    final step = math.max(1, (values.length / 5).ceil());
    for (var i = 0; i < values.length; i += step) {
      if (i >= labels.length) break;
      final label = labels[i];
      if (label.isEmpty) continue;
      final t = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: textColor, fontSize: 9.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (xAt(i) - t.width / 2).clamp(2.0, w - t.width - 2);
      t.paint(canvas, Offset(lx, h - padB + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress;
  }
}

class RingChart extends StatelessWidget {
  final double percent;
  final Color color;
  final String center;
  final String caption;
  final double size;

  const RingChart({
    super.key,
    required this.percent,
    required this.color,
    required this.center,
    required this.caption,
    this.size = 112,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: percent.clamp(0, 100).toDouble(),
            ),
            duration: const Duration(milliseconds: 760),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                percent: v,
                color: color,
                bg: AppColors.surfaceHigh,
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 620),
            curve: Curves.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color color;
  final Color bg;

  _RingPainter({required this.percent, required this.color, required this.bg});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final bgPaint = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * (percent / 100);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.color != color;
  }
}

class ChainNode extends StatelessWidget {
  final String label;
  final Color color;
  final bool pulse;

  const ChainNode({
    super.key,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.26), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: color, on: pulse),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool on;
  const _PulseDot({required this.color, required this.on});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.on) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.on && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final glow = widget.on ? 0.25 + 0.35 * (1 - _c.value) : 0.0;
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              if (glow > 0)
                BoxShadow(
                  color: widget.color.withValues(alpha: glow),
                  blurRadius: 4,
                  spreadRadius: 2,
                ),
            ],
          ),
        );
      },
    );
  }
}

class ExpandChevron extends StatelessWidget {
  final bool open;
  const ExpandChevron({super.key, required this.open});

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: open ? 0.5 : 0,
      duration: const Duration(milliseconds: 220),
      child: const Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 18,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}

class LiveDot extends StatelessWidget {
  final bool ok;
  const LiveDot({super.key, required this.ok});

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      text: ok ? '实时' : '重连中',
      color: ok ? AppColors.success : AppColors.error,
      dot: true,
    );
  }
}

class ElapsedText extends StatefulWidget {
  final DateTime start;
  const ElapsedText({super.key, required this.start});

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sec = math.max(
      0.0,
      DateTime.now().difference(widget.start).inMilliseconds / 1000.0,
    );
    return Text(
      ' ${fmtDuration(sec)}',
      style: const TextStyle(
        color: Color(0xFF7FA6C9),
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
