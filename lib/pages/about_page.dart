import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于系统')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            scheme,
            icon: Icons.pets,
            title: '警犬姿态与动作识别（Android 离线版）',
            children: const [
              Text(
                '基于 police-dog-recognition 后端核心（backend-core）接口开发的 Flutter 前端。'
                '识别目标为单只警犬的站立 / 坐下 / 趴下动作与 39 个 SuperAnimal-Quadruped 关键点，'
                '模型、推理与报告全部在手机本地离线完成。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
          _section(
            scheme,
            icon: Icons.api,
            title: '后端接口契约（RecognitionBackend）',
            children: [
              _methodRow('initialize', '初始化后端（配置批量上限与持久化）'),
              _methodRow('submit / submitBatch', '提交单图 / 批量识别任务'),
              _methodRow('observeTask / observeBatch', '订阅任务 / 批次事件流（进度、阶段、结果、错误）'),
              _methodRow('cancelTask / cancelBatch', '取消排队或运行中的任务'),
              _methodRow('getResult / queryHistory', '查询结果与本地历史记录'),
              _methodRow('deleteRecords', '删除本地识别记录'),
              _methodRow('exportReport', '导出 JSON / CSV / PDF 报告'),
              _methodRow('release', '释放后端资源'),
            ],
          ),
          _section(
            scheme,
            icon: Icons.architecture,
            title: '模型方案（SuperAnimal-Quadruped）',
            children: [
              _modelRow('姿态模型', 'superanimal_quadruped_rtmpose_s.pt', '24,394,391 B'),
              _modelRow('检测模型', 'superanimal_quadruped_ssdlite.pt', '9,144,611 B'),
              const SizedBox(height: 8),
              const Text(
                '39 关键点（头部、背部、四肢、尾部）；移动端基线合计约 31.99 MiB。'
                '当前阶段使用 Mock 引擎联调，端侧模型转换与验证完成后接入同一接口。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          ),
          _section(
            scheme,
            icon: Icons.warning_amber,
            title: '许可声明',
            children: const [
              Text(
                'SuperAnimal 模型由 DeepLabCut 官方声明仅供研究、非商业用途。'
                '本应用当前为项目组内部联调版本，正式交付使用前需由甲方确认项目使用性质并留档。',
                style: TextStyle(fontSize: 12, height: 1.5, color: Colors.orange),
              ),
            ],
          ),
          _section(
            scheme,
            icon: Icons.info_outline,
            title: '版本信息',
            children: [
              _methodRow('前端', 'police-dog-recognition-frontend v1.0.0'),
              _methodRow('后端核心', 'backend-core 0.1.0-SNAPSHOT（Mock）'),
              _methodRow('运行模式', _runtimeMode(context)),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _runtimeMode(BuildContext context) {
    final appState = context.watch<AppState>();
    return appState.ready ? '后端已就绪（${appState.lifecycle.zh}）' : appState.lifecycle.zh;
  }

  Widget _section(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _methodRow(String name, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              name,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(desc, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _modelRow(String role, String name, String size) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(role, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(size, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        ],
      ),
    );
  }
}
