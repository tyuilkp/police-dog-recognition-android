import 'package:flutter/material.dart';

import '../models/backend_models.dart';

/// 任务阶段小标签。
class StageChip extends StatelessWidget {
  const StageChip({super.key, required this.stage, this.compact = false});

  final TaskStage stage;
  final bool compact;

  static const Map<TaskStage, IconData> _icons = {
    TaskStage.queued: Icons.schedule,
    TaskStage.openingInput: Icons.folder_open,
    TaskStage.decoding: Icons.image,
    TaskStage.detecting: Icons.search,
    TaskStage.estimatingPose: Icons.psychology,
    TaskStage.classifying: Icons.category,
    TaskStage.rendering: Icons.draw,
    TaskStage.persisting: Icons.save,
    TaskStage.finished: Icons.check_circle,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(_icons[stage] ?? Icons.more_horiz, size: compact ? 14 : 16),
      label: Text(stage.zh, style: TextStyle(fontSize: compact ? 11 : 13)),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      backgroundColor: scheme.surfaceContainerHighest,
      side: BorderSide(color: scheme.outlineVariant),
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8, vertical: 2),
    );
  }
}
