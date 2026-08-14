import 'dart:async';

import '../models/backend_models.dart';
import 'backend_api.dart';

/// Dart 内嵌 Mock，行为镜像 pdr `MockRecognitionEngine` 的文档约定
/// （docs/BACKEND_HANDOFF.md）：
///
/// - 包含 `standing`/`stand`：站立；
/// - 包含 `sitting`/`sit`：坐下；
/// - 包含 `lying`/`lie`：趴下；
/// - 包含 `nodog`：无犬错误；
/// - 包含 `multidog`：多犬错误；
/// - 包含 `broken`：输入读取失败；
/// - 其他：UNKNOWN。
///
/// 用途：Android 之外的平台（桌面预览、单元测试）联调页面与交互，
/// 不参与 Android 真机构建。
class FakeBackendApi implements BackendApi {
  FakeBackendApi({this.stageDelay = const Duration(milliseconds: 10)});

  final Duration stageDelay;

  BackendLifecycle _lifecycle = BackendLifecycle.uninitialized;
  BackendError? _error;

  final Map<String, TaskEvent> _taskEvents = {};
  final Map<String, BatchEvent> _batchEvents = {};
  final List<RecognitionRecord> _records = [];
  final Map<String, StreamController<TaskEvent>> _taskControllers = {};
  final Map<String, StreamController<BatchEvent>> _batchControllers = {};

  bool get _ready => _lifecycle == BackendLifecycle.ready;

  @override
  Future<BackendState> getState() async =>
      BackendState(lifecycle: _lifecycle, error: _error);

  @override
  Future<BackendResult<void>> initialize({
    int maxBatchSize = 50,
    bool persistResults = true,
  }) async {
    if (_lifecycle == BackendLifecycle.ready ||
        _lifecycle == BackendLifecycle.initializing) {
      return BackendResult.failure(BackendError(
        code: ErrorCode.backendAlreadyInitialized,
        message: '后端已初始化',
      ));
    }
    _lifecycle = BackendLifecycle.initializing;
    await Future<void>.delayed(stageDelay);
    _lifecycle = BackendLifecycle.ready;
    _error = null;
    return const BackendResult.success(null);
  }

  @override
  Future<BackendResult<TaskId>> submit(RecognitionRequest request) async {
    if (!_ready) {
      return BackendResult.failure(BackendError(
        code: ErrorCode.backendNotInitialized,
        message: '后端未初始化',
      ));
    }
    if (request.source.trim().isEmpty) {
      return BackendResult.failure(BackendError(
        code: ErrorCode.invalidRequest,
        message: '图片源不能为空',
      ));
    }
    final taskId = 'mock-${DateTime.now().microsecondsSinceEpoch}';
    _taskEvents[taskId] = TaskEvent(
      taskId: taskId,
      state: TaskState.queued,
      stage: TaskStage.queued,
      progressPercent: 0,
    );
    _taskControllers[taskId] = StreamController<TaskEvent>.broadcast();
    unawaited(_runTask(taskId, request));
    return BackendResult.success(TaskId(taskId));
  }

  @override
  Future<BackendResult<BatchId>> submitBatch(BatchRecognitionRequest request) async {
    if (!_ready) {
      return BackendResult.failure(BackendError(
        code: ErrorCode.backendNotInitialized,
        message: '后端未初始化',
      ));
    }
    if (request.requests.isEmpty || request.requests.any((r) => r.source.trim().isEmpty)) {
      return BackendResult.failure(BackendError(
        code: ErrorCode.invalidRequest,
        message: '批量任务必须包含非空图片源',
      ));
    }
    final batchId = 'mock-batch-${DateTime.now().microsecondsSinceEpoch}';
    final taskIds = <String>[];
    for (var i = 0; i < request.requests.length; i++) {
      final taskId = '$batchId-$i';
      taskIds.add(taskId);
      _taskEvents[taskId] = TaskEvent(
        taskId: taskId,
        state: TaskState.queued,
        stage: TaskStage.queued,
        progressPercent: 0,
      );
      _taskControllers[taskId] = StreamController<TaskEvent>.broadcast();
    }
    _batchEvents[batchId] = BatchEvent(
      batchId: batchId,
      state: BatchState.queued,
      total: taskIds.length,
      completed: 0,
      failed: 0,
      cancelled: 0,
      taskIds: taskIds,
    );
    _batchControllers[batchId] = StreamController<BatchEvent>.broadcast();
    unawaited(_runBatch(batchId, request.requests));
    return BackendResult.success(BatchId(batchId));
  }

  @override
  Stream<TaskEvent> observeTask(String taskId) {
    final controller = _taskControllers[taskId];
    if (controller == null) {
      return Stream.value(TaskEvent(
        taskId: taskId,
        state: TaskState.failed,
        stage: TaskStage.finished,
        progressPercent: 100,
        error: BackendError(code: ErrorCode.taskNotFound, message: '任务不存在'),
      ));
    }
    return controller.stream;
  }

  @override
  Stream<BatchEvent> observeBatch(String batchId) {
    final controller = _batchControllers[batchId];
    if (controller == null) {
      return Stream.value(BatchEvent(
        batchId: batchId,
        state: BatchState.failed,
        total: 0,
        completed: 0,
        failed: 0,
        cancelled: 0,
        taskIds: const [],
        error: BackendError(code: ErrorCode.batchNotFound, message: '批次不存在'),
      ));
    }
    return controller.stream;
  }

  @override
  Future<CancelResult> cancelTask(String taskId) async {
    final event = _taskEvents[taskId];
    if (event == null) return CancelResult.notFound;
    if (event.isTerminal) return CancelResult.alreadyFinished;
    if (event.state == TaskState.cancelRequested) return CancelResult.requested;
    _emitTask(taskId, event.copyWith(state: TaskState.cancelRequested));
    return CancelResult.requested;
  }

  @override
  Future<CancelResult> cancelBatch(String batchId) async {
    final batch = _batchEvents[batchId];
    if (batch == null) return CancelResult.notFound;
    var anyRequested = false;
    for (final taskId in batch.taskIds) {
      final res = await cancelTask(taskId);
      if (res == CancelResult.requested) anyRequested = true;
    }
    return anyRequested ? CancelResult.requested : CancelResult.alreadyFinished;
  }

  @override
  Future<RecognitionResult?> getResult(String taskId) async {
    final event = _taskEvents[taskId];
    return event?.result;
  }

  @override
  Future<Page<RecognitionRecord>> queryHistory({int offset = 0, int limit = 50}) async {
    final sorted = [..._records]
      ..sort((a, b) => b.result.createdAtEpochMillis.compareTo(a.result.createdAtEpochMillis));
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(1, 200);
    return Page(
      items: sorted.skip(safeOffset).take(safeLimit).toList(),
      offset: safeOffset,
      limit: safeLimit,
      total: sorted.length,
    );
  }

  @override
  Future<BackendResult<void>> deleteRecords(List<String> recordIds) async {
    _records.removeWhere((r) => recordIds.contains(r.result.recordId));
    return const BackendResult.success(null);
  }

  @override
  Future<BackendResult<ReportResult>> exportReport(ReportRequest request) async {
    final count = _records
        .where((r) => request.recordIds.contains(r.result.recordId))
        .length;
    return BackendResult.success(ReportResult(
      location: 'memory://reports/${DateTime.now().microsecondsSinceEpoch}.${request.format.name.toLowerCase()}',
      mimeType: request.format.mimeType,
      recordCount: count,
    ));
  }

  @override
  Future<BackendResult<void>> release() async {
    if (_lifecycle == BackendLifecycle.released) {
      return const BackendResult.success(null);
    }
    _lifecycle = BackendLifecycle.releasing;
    for (final c in _taskControllers.values) {
      await c.close();
    }
    for (final c in _batchControllers.values) {
      await c.close();
    }
    _taskControllers.clear();
    _batchControllers.clear();
    _lifecycle = BackendLifecycle.released;
    return const BackendResult.success(null);
  }

  // -------------------------------------------------------------------------

  Future<void> _runTask(String taskId, RecognitionRequest request) async {
    try {
      final source = request.source.toLowerCase();
      Future<void> stage(TaskStage s, int p) async {
        if (stageDelay > Duration.zero) await Future<void>.delayed(stageDelay);
        _emitTask(taskId, TaskEvent(
          taskId: taskId,
          state: TaskState.running,
          stage: s,
          progressPercent: p,
        ));
      }

      await stage(TaskStage.openingInput, 5);
      if (source.contains('broken')) {
        throw BackendError(code: ErrorCode.inputOpenFailed, message: '模拟输入打开失败');
      }
      await stage(TaskStage.decoding, 15);
      await stage(TaskStage.detecting, 40);
      if (source.contains('nodog')) {
        throw BackendError(code: ErrorCode.noDogDetected, message: '图片中未检测到警犬');
      }
      if (source.contains('multidog')) {
        throw BackendError(code: ErrorCode.multipleDogsDetected, message: '检测到多只警犬');
      }
      await stage(TaskStage.estimatingPose, 70);
      await stage(TaskStage.classifying, 85);

      final action = source.contains('stand')
          ? ActionLabel.standing
          : source.contains('sit')
              ? ActionLabel.sitting
              : source.contains('lie')
                  ? ActionLabel.lying
                  : ActionLabel.unknown;

      await stage(TaskStage.rendering, 95);
      final now = DateTime.now().millisecondsSinceEpoch;
      final result = RecognitionResult(
        recordId: taskId,
        taskId: taskId,
        source: request.source,
        action: action,
        actionScores: _scoresFor(action),
        dogBox: const BoundingBox(left: 0.15, top: 0.12, right: 0.85, bottom: 0.88, confidence: 0.94),
        keypoints: _mockKeypoints(),
        quality: action == ActionLabel.unknown ? QualityStatus.unknownPose : QualityStatus.accepted,
        warnings: action == ActionLabel.unknown
            ? const [RecognitionWarning.lowActionConfidence]
            : const [],
        originalLocation: request.saveOriginal ? request.source : null,
        overlayLocation: 'memory://overlay/$taskId.jpg',
        timing: const InferenceTiming(
          totalMillis: 60,
          detectionMillis: 10,
          poseMillis: 10,
          classificationMillis: 10,
        ),
        modelInfo: const ModelInfo(
          detectorName: 'superanimal_quadruped_ssdlite',
          poseModelName: 'superanimal_quadruped_rtmpose_s',
          actionModelName: 'mock-action-classifier',
          version: 'mock-0.1.0',
        ),
        createdAtEpochMillis: now,
      );
      _records.add(RecognitionRecord(result: result));
      _emitTask(taskId, TaskEvent(
        taskId: taskId,
        state: TaskState.completed,
        stage: TaskStage.finished,
        progressPercent: 100,
        result: result,
      ));
    } on BackendError catch (e) {
      _emitTask(taskId, TaskEvent(
        taskId: taskId,
        state: TaskState.failed,
        stage: TaskStage.finished,
        progressPercent: 100,
        error: e,
      ));
    }
  }

  Future<void> _runBatch(String batchId, List<RecognitionRequest> requests) async {
    for (var i = 0; i < requests.length; i++) {
      final taskId = '$batchId-$i';
      final before = _taskEvents[taskId]!;
      if (before.state == TaskState.cancelRequested) {
        _completeTaskCancelled(taskId);
        continue;
      }
      _emitBatch(batchId, _batchEvents[batchId]!.copyWith(state: BatchState.running));
      await _runTask(taskId, requests[i]);
      final event = _taskEvents[taskId]!;
      if (event.isTerminal) {
        final b = _batchEvents[batchId]!;
        final next = b.copyWith(
          state: BatchState.running,
          completed: b.completed + (event.state == TaskState.completed ? 1 : 0),
          failed: b.failed + (event.state == TaskState.failed ? 1 : 0),
          cancelled: b.cancelled + (event.state == TaskState.cancelled ? 1 : 0),
        );
        _batchEvents[batchId] = next;
        _emitBatch(batchId, next);
      }
    }
    final b = _batchEvents[batchId]!;
    final terminal = b.copyWith(
      state: b.cancelled == b.total ? BatchState.cancelled : BatchState.completed,
    );
    _batchEvents[batchId] = terminal;
    _emitBatch(batchId, terminal);
    await _batchControllers[batchId]?.close();
  }

  void _completeTaskCancelled(String taskId) {
    final event = TaskEvent(
      taskId: taskId,
      state: TaskState.cancelled,
      stage: TaskStage.finished,
      progressPercent: 100,
      error: BackendError(code: ErrorCode.taskCancelled, message: '任务已取消'),
    );
    _taskEvents[taskId] = event;
    _emitTask(taskId, event);
  }

  void _emitTask(String taskId, TaskEvent event) {
    _taskEvents[taskId] = event;
    _taskControllers[taskId]?.add(event);
    if (event.isTerminal) {
      _taskControllers[taskId]?.close();
    }
  }

  void _emitBatch(String batchId, BatchEvent event) {
    _batchEvents[batchId] = event;
    _batchControllers[batchId]?.add(event);
  }

  Map<ActionLabel, double> _scoresFor(ActionLabel action) {
    final result = <ActionLabel, double>{};
    for (final label in ActionLabel.values) {
      result[label] = switch ((action, label)) {
        (ActionLabel.unknown, _) => 0.25,
        (_, ActionLabel.unknown) => 0.03,
        _ when label == action => 0.91,
        _ => 0.02,
      };
    }
    return result;
  }

  List<Keypoint> _mockKeypoints() => List.generate(39, (index) => Keypoint(
        index: index,
        name: 'quadruped_keypoint_$index',
        x: 0.2 + (index % 8) * 0.075,
        y: 0.2 + (index ~/ 8) * 0.12,
        confidence: 0.9,
      ));
}
