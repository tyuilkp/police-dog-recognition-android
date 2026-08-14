import 'package:flutter/material.dart';

import '../models/backend_models.dart';
import '../widgets/result_view.dart';

/// 识别结果详情页（历史记录 / 批量结果跳转）。
class ResultDetailPage extends StatelessWidget {
  const ResultDetailPage({super.key, required this.result, this.localImagePath});

  final RecognitionResult result;
  final String? localImagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('识别详情')),
      body: ResultView(result: result, localImagePath: localImagePath),
    );
  }
}
