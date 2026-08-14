import 'dart:io';

import 'package:flutter/material.dart';

import '../models/backend_models.dart';
import 'action_badge.dart';
import 'keypoint_overlay.dart';
import 'score_bar.dart';

/// 识别结果的完整展示组件（单图页 / 详情页共用）。
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.result,
    this.localImagePath,
  });

  final RecognitionResult result;
  final String? localImagePath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _heroCard(context, scheme),
        const SizedBox(height: 12),
        if (localImagePath != null) _imageCard(context, scheme),
        const SizedBox(height: 12),
        _scoresCard(context, scheme),
        const SizedBox(height: 12),
        _detailCard(context, scheme),
        const SizedBox(height: 12),
        _metaCard(context, scheme),
      ],
    );
  }

  // 动作结论
  Widget _heroCard(BuildContext context, ColorScheme scheme) {
    final qualityColor = switch (result.quality) {
      QualityStatus.accepted => Colors.green,
      QualityStatus.lowConfidence => Colors.orange,
      QualityStatus.insufficientKeypoints => Colors.orange,
      QualityStatus.unknownPose => Colors.grey,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ActionBadge(action: result.action, large: true),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '识别结论',
                    style: TextStyle(color: scheme.outline, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.action.zh,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    icon: Icons.verified_user,
                    label: '质量状态',
                    value: result.quality.zh,
                    valueColor: qualityColor,
                  ),
                  _infoRow(
                    icon: Icons.linear_scale,
                    label: '关键点',
                    value: '${result.keypoints.length} / 39',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 图片 + 关键点覆盖图
  Widget _imageCard(BuildContext context, ColorScheme scheme) {
    final path = localImagePath;
    if (path == null) return const SizedBox.shrink();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('结果可视化', style: TextStyle(color: scheme.outline, fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  Image.file(File(path), fit: BoxFit.contain),
                  Positioned.fill(
                    child: KeypointOverlay(
                      dogBox: result.dogBox,
                      keypoints: result.keypoints,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (result.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: result.warnings
                    .map((w) => Chip(
                          avatar: const Icon(Icons.warning_amber, size: 16),
                          label: Text(w.zh, style: const TextStyle(fontSize: 12)),
                          backgroundColor: Colors.amber.withValues(alpha: 0.15),
                          side: BorderSide(color: Colors.amber.withValues(alpha: 0.6)),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  // 动作概率
  Widget _scoresCard(BuildContext context, ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('动作分类概率', style: TextStyle(color: scheme.outline, fontSize: 12)),
            const SizedBox(height: 8),
            for (final entry in result.actionScores.entries)
              ScoreBar(
                label: entry.key.zh,
                score: entry.value,
                color: switch (entry.key) {
                  ActionLabel.standing => const Color(0xFF2E7D32),
                  ActionLabel.sitting => const Color(0xFF1565C0),
                  ActionLabel.lying => const Color(0xFF6A1B9A),
                  ActionLabel.unknown => const Color(0xFF757575),
                },
              ),
          ],
        ),
      ),
    );
  }

  // 检测与耗时明细
  Widget _detailCard(BuildContext context, ColorScheme scheme) {
    final t = result.timing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('检测与耗时', style: TextStyle(color: scheme.outline, fontSize: 12)),
            const SizedBox(height: 8),
            if (result.dogBox != null)
              _infoRow(
                icon: Icons.crop_free,
                label: '检测框置信度',
                value: '${(result.dogBox!.confidence * 100).toStringAsFixed(1)}%',
              ),
            _infoRow(
              icon: Icons.timelapse,
              label: '总耗时',
              value: '${t.totalMillis} ms',
            ),
            _infoRow(
              icon: Icons.search,
              label: '检测耗时',
              value: '${t.detectionMillis} ms',
            ),
            _infoRow(
              icon: Icons.psychology,
              label: '姿态耗时',
              value: '${t.poseMillis} ms',
            ),
            _infoRow(
              icon: Icons.category,
              label: '分类耗时',
              value: '${t.classificationMillis} ms',
            ),
          ],
        ),
      ),
    );
  }

  // 模型与记录信息
  Widget _metaCard(BuildContext context, ColorScheme scheme) {
    final m = result.modelInfo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('模型与记录信息', style: TextStyle(color: scheme.outline, fontSize: 12)),
            const SizedBox(height: 8),
            _infoRow(icon: Icons.memory, label: '检测模型', value: m.detectorName),
            _infoRow(icon: Icons.accessibility_new, label: '姿态模型', value: m.poseModelName),
            _infoRow(icon: Icons.category, label: '动作模型', value: m.actionModelName),
            _infoRow(icon: Icons.tag, label: '模型版本', value: m.version),
            const Divider(height: 16),
            _infoRow(icon: Icons.receipt_long, label: '记录编号', value: result.recordId),
            _infoRow(
              icon: Icons.schedule,
              label: '创建时间',
              value: _formatTime(result.createdAtEpochMillis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int epochMillis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
