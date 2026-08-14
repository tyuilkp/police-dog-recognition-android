import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/backend_models.dart';
import '../services/app_state.dart';
import '../services/backend_api.dart';
import 'result_detail_page.dart';

class BatchRecognitionPage extends StatefulWidget {
  const BatchRecognitionPage({super.key});

  @override
  State<BatchRecognitionPage> createState() => _BatchRecognitionPageState();
}

enum _BatchPhase { selecting, running, done }

class _BatchRecognitionPageState extends State<BatchRecognitionPage> {
  final ImagePicker _picker = ImagePicker();

  _BatchPhase _phase = _BatchPhase.selecting;
  final List<XFile> _images = [];
  String? _batchId;
  StreamSubscription<BatchEvent>? _batchSub;

  BatchEvent? _batchEvent;
  final Map<String, TaskEvent> _taskEvents = {};
  /// 后端返回的有序任务 ID 列表（与提交顺序一致），来自 BatchEvent.taskIds。
  List<String> _taskIds = [];
  String? _errorText;

  @override
  void dispose() {
    _batchSub?.cancel();
    super.dispose();
  }

  Future<void> _pickMany() async {
    if (_phase == _BatchPhase.running) return;
    final files = await _picker.pickMultiImage(maxWidth: 1920);
    if (files.isEmpty) return;
    setState(() => _images.addAll(files));
  }

  Future<void> _start() async {
    if (_images.isEmpty || _phase == _BatchPhase.running) return;
    final api = context.read<BackendApi>();
    if (!context.read<AppState>().ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('识别后端尚未就绪，请返回首页重试初始化')),
      );
      return;
    }

    setState(() {
      _phase = _BatchPhase.running;
      _taskEvents.clear();
      _taskIds = [];
      _batchEvent = null;
      _errorText = null;
    });

    final submitted = await api.submitBatch(BatchRecognitionRequest(
      requests: [
        for (final f in _images)
          RecognitionRequest(source: f.path, saveOverlay: true, priority: TaskPriority.batch),
      ],
    ));
    if (!mounted) return;

    if (submitted.failed) {
      setState(() {
        _phase = _BatchPhase.done;
        _errorText = '${submitted.error!.code.zh}：${submitted.error!.message}';
      });
      return;
    }

    final batchId = submitted.value!.value;
    _batchId = batchId;
    _batchSub = api.observeBatch(batchId).listen((event) {
      if (!mounted) return;
      setState(() {
        _batchEvent = event;
        // 批次事件始终携带有序 taskIds，首次到达时按顺序订阅子任务
        if (_taskIds.isEmpty && event.taskIds.isNotEmpty) {
          _taskIds = event.taskIds;
          for (final taskId in _taskIds) {
            api.observeTask(taskId).listen((taskEvent) {
              if (!mounted) return;
              setState(() => _taskEvents[taskId] = taskEvent);
            });
          }
        }
      });
      if (event.state == BatchState.completed ||
          event.state == BatchState.cancelled ||
          event.state == BatchState.failed) {
        setState(() => _phase = _BatchPhase.done);
        _batchSub?.cancel();
      }
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _phase = _BatchPhase.done;
        _errorText = '批次事件流异常：$e';
      });
    });
  }

  String? _taskIdFor(int index) =>
      _taskIds.length > index ? _taskIds[index] : null;

  Future<void> _cancelBatch() async {
    final batchId = _batchId;
    if (batchId == null) return;
    final api = context.read<BackendApi>();
    final result = await api.cancelBatch(batchId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已请求取消：${result.zh}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('批量识别')),
      body: switch (_phase) {
        _BatchPhase.selecting => _buildSelecting(scheme),
        _BatchPhase.running => _buildRunning(scheme),
        _BatchPhase.done => _buildDone(scheme),
      },
    );
  }

  // ---------- 选图 ----------

  Widget _buildSelecting(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('批量选择图片', style: TextStyle(color: scheme.outline, fontSize: 12)),
                const SizedBox(height: 8),
                const Text(
                  '一次选择多张警犬图片，后端将按顺序逐张识别。单张失败不会中断整个批次。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickMany,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text('选择图片（已选 ${_images.length} 张）'),
                ),
              ],
            ),
          ),
        ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _images.length,
            itemBuilder: (context, index) {
              final f = _images[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(f.path), fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => setState(() => _images.removeAt(index)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: Text('开始批量识别（${_images.length} 张）'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ],
    );
  }

  // ---------- 识别中 ----------

  Widget _buildRunning(ColorScheme scheme) {
    final event = _batchEvent;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  event == null
                      ? '正在提交批次…'
                      : '批次${event.state.zh}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '${event?.completed ?? 0} / ${event?.total ?? _images.length}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (event?.progressPercent ?? 0) / 100,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '完成 ${event?.completed ?? 0} · 失败 ${event?.failed ?? 0} · 取消 ${event?.cancelled ?? 0}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _cancelBatch,
                  icon: const Icon(Icons.stop),
                  label: const Text('取消整个批次'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _images.length; i++) _taskTile(context, scheme, i),
      ],
    );
  }

  // ---------- 完成 ----------

  Widget _buildDone(ColorScheme scheme) {
    if (_errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: scheme.error),
              const SizedBox(height: 12),
              const Text('批次提交失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorText!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() => _phase = _BatchPhase.selecting),
                child: const Text('返回选图'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  _batchEvent?.state == BatchState.cancelled
                      ? Icons.cancel_outlined
                      : Icons.check_circle,
                  size: 40,
                  color: _batchEvent?.state == BatchState.cancelled
                      ? Colors.grey
                      : Colors.green,
                ),
                const SizedBox(height: 8),
                Text(
                  '批次${_batchEvent?.state.zh ?? '完成'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '完成 ${_batchEvent?.completed ?? 0} · 失败 ${_batchEvent?.failed ?? 0} · 取消 ${_batchEvent?.cancelled ?? 0}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _phase = _BatchPhase.selecting;
                    _images.clear();
                  }),
                  child: const Text('再来一批'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _images.length; i++) _taskTile(context, scheme, i),
      ],
    );
  }

  // ---------- 任务行 ----------

  Widget _taskTile(BuildContext context, ColorScheme scheme, int index) {
    final file = _images[index];
    final taskId = _taskIdFor(index);
    final event = taskId == null ? null : _taskEvents[taskId];
    final result = event?.result;

    final (IconData icon, Color color, String status) = switch (event?.state) {
      TaskState.completed => (
          Icons.check_circle,
          Colors.green,
          result == null ? '完成' : '识别结果：${result.action.zh}',
        ),
      TaskState.failed => (Icons.error, scheme.error, '失败：${event?.error?.message ?? ''}'),
      TaskState.cancelled => (Icons.cancel, Colors.grey, '已取消'),
      TaskState.cancelRequested => (Icons.hourglass_bottom, Colors.orange, '取消中…'),
      TaskState.running => (Icons.sync, Colors.blue, '${event?.stage.zh} ${event?.progressPercent ?? 0}%'),
      _ => (Icons.schedule, Colors.grey, '排队中'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Image.file(File(file.path), fit: BoxFit.cover),
          ),
        ),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        trailing: event?.state == TaskState.completed
            ? TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ResultDetailPage(
                      result: result!,
                      localImagePath: file.path,
                    ),
                  ),
                ),
                child: const Text('详情'),
              )
            : null,
      ),
    );
  }
}
