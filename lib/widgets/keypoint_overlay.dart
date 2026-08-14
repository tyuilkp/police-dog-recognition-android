import 'package:flutter/material.dart';

import '../models/backend_models.dart';

/// 在图片上绘制检测框 + 39 关键点覆盖图。
///
/// 坐标均为 0..1 归一化坐标（与 backend-core 的 BoundingBox / Keypoint 一致），
/// 通过 [Image.file] 的 FittedBox 缩放后叠加绘制。
class KeypointOverlay extends StatelessWidget {
  const KeypointOverlay({
    super.key,
    required this.dogBox,
    required this.keypoints,
    this.showLabels = false,
  });

  final BoundingBox? dogBox;
  final List<Keypoint> keypoints;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _KeypointPainter(
          dogBox: dogBox,
          keypoints: keypoints,
          showLabels: showLabels,
        ),
      ),
    );
  }
}

class _KeypointPainter extends CustomPainter {
  _KeypointPainter({
    required this.dogBox,
    required this.keypoints,
    required this.showLabels,
  });

  final BoundingBox? dogBox;
  final List<Keypoint> keypoints;
  final bool showLabels;

  static const Color _boxColor = Color(0xFFFFC107); // 琥珀色检测框
  static const Color _dotColor = Color(0xFF00E5FF); // 青色关键点

  @override
  void paint(Canvas canvas, Size size) {
    // 检测框
    if (dogBox != null) {
      final box = dogBox!;
      final rect = Rect.fromLTRB(
        box.left * size.width,
        box.top * size.height,
        box.right * size.width,
        box.bottom * size.height,
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _boxColor;
      canvas.drawRect(rect, paint);
      final label = '犬只 ${(box.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: _boxColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0x99000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, (rect.top - 18).clamp(0, size.height - 18)));
    }

    // 关键点
    for (final kp in keypoints) {
      final center = Offset(kp.x * size.width, kp.y * size.height);
      // 置信度高的点更实心
      final alpha = (kp.confidence.clamp(0.2, 1.0) * 255).round();
      canvas.drawCircle(
        center,
        3.0,
        Paint()..color = _dotColor.withAlpha(alpha),
      );
      canvas.drawCircle(
        center,
        5.0,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = _dotColor.withAlpha(alpha),
      );
      if (showLabels) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${kp.index}',
            style: const TextStyle(color: Colors.white, fontSize: 8),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, center + const Offset(4, 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KeypointPainter oldDelegate) =>
      oldDelegate.dogBox != dogBox ||
      oldDelegate.keypoints != keypoints ||
      oldDelegate.showLabels != showLabels;
}
