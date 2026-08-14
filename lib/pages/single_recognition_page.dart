import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/backend_models.dart';
import '../services/app_state.dart';
import '../services/backend_api.dart';
import '../widgets/result_view.dart';
import '../widgets/stage_chip.dart';

class SingleRecognitionPage extends StatefulWidget {
  const SingleRecognitionPage({super.key});

  @override
  State<SingleRecognitionPage> createState() => _SingleRecognitionPageState();
}

enum _Phase { idle, picking, running, done }

class _SingleRecognitionPageState extends State<SingleRecognitionPage> {
  final ImagePicker _picker = ImagePicker();

  _Phase _phase = _Phase.idle;
  XFile? _image;
  String? _taskId;
  StreamSubscription<TaskEvent>? _sub;

  TaskEvent? _event;
  String? _errorText;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_phase == _Phase.running) return;
    final file = await _picker.pickImage(source: source, maxWidth: 1920);
    if (file == null) return;
    setState(() {
      _image = file;
      _phase = _Phase.picking;
      _event = null;
      _errorText = null;
    });
  }

  Future<void> _start() async {
    final image = _image;
    if (image == null || _phase == _Phase.running) return;
    final api = context.read<BackendApi>();
    final ready = context.read<AppState>().ready;

    if (!ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('识别后端尚未就绪，请返回首页重试初始化')),
      );
      return;
    }

    setState(() {
      _phase = _Phase.running;
      _event = null;
      _errorText = null;
    });

    final submitted = await api.submit(RecognitionRequest(
      source: image.path,
      saveOverlay: true,
      priority: TaskPriority.interactive,
    ));
    if (!mounted) return;

    if (submitted.failed) {
      setState(() {
        _phase = _Phase.done;
        _errorText = '${submitted.error!.code.zh}：${submitted.error!.message}';
      });
      return;
    }

    final taskId = submitted.value!.value;
    _taskId = taskId;
    _sub = api.observeTask(taskId).listen((event) {
      if (!mounted) return;
      setState(() => _event = event);
      if (event.isTerminal) {
        setState(() => _phase = _Phase.done);
        _sub?.cancel();
      }
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _errorText = '事件流异常：$e';
      });
    });
  }

  Future<void> _cancel() async {
    final taskId = _taskId;
    if (taskId == null) return;
    final api = context.read<BackendApi>();
    final result = await api.cancelTask(taskId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已请求取消：${result.zh}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('单图识别')),
      body: switch (_phase) {
        _Phase.idle || _Phase.picking => _buildPicker(scheme),
        _Phase.running => _buildRunning(scheme),
        _Phase.done => _buildDone(scheme),
      },
    );
  }

  // ---------- 选图 ----------

  Widget _buildPicker(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择警犬图片', style: TextStyle(color: scheme.outline, fontSize: 12)),
                const SizedBox(height: 8),
                const Text(
                  '支持单只警犬的全身照片。识别将输出动作类别（站立/坐下/趴下）、39 个关键点与质量提示。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _phase == _Phase.running ? null : () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('拍照'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _phase == _Phase.running ? null : () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('从相册选择'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_image != null) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.file(File(_image!.path), fit: BoxFit.contain),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _image!.name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: '移除图片',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() {
                          _image = null;
                          _phase = _Phase.idle;
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始识别'),
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
    final event = _event;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  if (event != null)
                    StageChip(stage: event.stage)
                  else
                    const StageChip(stage: TaskStage.queued),
                  const SizedBox(height: 16),
                  Text(
                    event?.progressPercent.toString() ?? '0',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  Text('%', style: TextStyle(color: scheme.outline)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (event?.progressPercent ?? 0) / 100,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '正在${event?.stage.zh ?? '排队'}…',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.stop),
            label: const Text('取消识别'),
          ),
        ],
      ),
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
              const Text('识别失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorText!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => setState(() => _phase = _Phase.picking),
                    child: const Text('更换图片'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final event = _event;
    final result = event?.result;
    if (event?.state == TaskState.cancelled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('任务已取消', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() => _phase = _Phase.picking),
                child: const Text('返回选图'),
              ),
            ],
          ),
        ),
      );
    }

    if (result == null) {
      return const Center(child: Text('未获取到识别结果'));
    }

    return ResultView(
      result: result,
      localImagePath: _image?.path,
    );
  }
}
