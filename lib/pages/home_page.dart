import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/backend_models.dart';
import '../services/app_state.dart';
import 'about_page.dart';
import 'batch_recognition_page.dart';
import 'history_page.dart';
import 'single_recognition_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('警犬姿态识别'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '关于系统',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _BackendStatusCard(),
          const SizedBox(height: 16),
          _FeatureGrid(),
          const SizedBox(height: 16),
          const _OfflineNotice(),
        ],
      ),
    );
  }
}

class _BackendStatusCard extends StatelessWidget {
  const _BackendStatusCard();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    final (icon, color, text) = switch (appState.lifecycle) {
      BackendLifecycle.ready => (Icons.check_circle, Colors.green, '识别后端已就绪（离线）'),
      BackendLifecycle.initializing => (Icons.hourglass_top, Colors.orange, '正在初始化识别后端…'),
      BackendLifecycle.failed => (Icons.error, scheme.error, '后端初始化失败'),
      BackendLifecycle.releasing => (Icons.sync, Colors.orange, '正在释放后端…'),
      BackendLifecycle.released => (Icons.power_settings_new, Colors.grey, '后端已释放'),
      BackendLifecycle.uninitialized => (Icons.power, Colors.grey, '后端未初始化'),
    };

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  ),
                  if (appState.backendError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${appState.backendError!.code.zh}：${appState.backendError!.message}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (appState.lifecycle == BackendLifecycle.failed)
              TextButton(
                onPressed: () => context.read<AppState>().retry(),
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final features = [
      (
        Icons.camera_alt,
        '单图识别',
        '拍照或选择一张警犬图片，识别站立/坐下/趴下动作与关键点',
        SingleRecognitionPage(),
      ),
      (
        Icons.photo_library,
        '批量识别',
        '一次选择多张图片，按队列顺序批量识别并汇总结果',
        BatchRecognitionPage(),
      ),
      (
        Icons.history,
        '历史记录',
        '查看本地保存的识别记录，支持删除与导出报告',
        HistoryPage(),
      ),
      (
        Icons.architecture,
        '关于系统',
        '接口契约、模型信息与许可说明',
        AboutPage(),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [
        for (final (icon, title, subtitle, page) in features)
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => page),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      child: Icon(icon, color: scheme.primary),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.airplanemode_inactive, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '全部识别在手机本地离线完成：模型、推理与报告均不出设备。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
