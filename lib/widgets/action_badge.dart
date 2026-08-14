import 'package:flutter/material.dart';

import '../models/backend_models.dart';

/// 动作标签徽章：站立 / 坐下 / 趴下 / 未知姿态。
class ActionBadge extends StatelessWidget {
  const ActionBadge({super.key, required this.action, this.large = false});

  final ActionLabel action;
  final bool large;

  static const Map<ActionLabel, Color> _colors = {
    ActionLabel.standing: Color(0xFF2E7D32), // 绿
    ActionLabel.sitting: Color(0xFF1565C0), // 蓝
    ActionLabel.lying: Color(0xFF6A1B9A), // 紫
    ActionLabel.unknown: Color(0xFF757575), // 灰
  };

  static const Map<ActionLabel, IconData> _icons = {
    ActionLabel.standing: Icons.accessibility_new,
    ActionLabel.sitting: Icons.chair,
    ActionLabel.lying: Icons.hotel,
    ActionLabel.unknown: Icons.help_outline,
  };

  Color get color => _colors[action] ?? _colors[ActionLabel.unknown]!;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = large ? 64.0 : 36.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(_icons[action], color: color, size: large ? 32 : 20),
        ),
        const SizedBox(height: 6),
        Text(
          action.zh,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: large ? 20 : 14,
          ),
        ),
        if (large) ...[
          const SizedBox(height: 2),
          Text(
            action.en,
            style: TextStyle(color: scheme.outline, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
