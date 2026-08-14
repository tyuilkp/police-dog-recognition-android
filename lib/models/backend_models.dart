/// Dart 侧对 pdr 仓库 `BackendModels.kt` 的镜像。
///
/// 字段名与语义一一对应 `com.policedog.recognition.backend.api`，
/// 序列化格式与 Android 桥接层（BackendJson.kt）保持一致。
library;

// ---------------------------------------------------------------------------
// 后端生命周期与错误
// ---------------------------------------------------------------------------

enum BackendLifecycle {
  uninitialized('未初始化'),
  initializing('初始化中'),
  ready('就绪'),
  failed('失败'),
  releasing('释放中'),
  released('已释放');

  const BackendLifecycle(this.zh);
  final String zh;

  static BackendLifecycle fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => uninitialized);
}

enum ErrorCode {
  backendNotInitialized('后端未初始化'),
  backendAlreadyInitialized('后端已初始化'),
  backendReleased('后端已释放'),
  modelFileMissing('模型文件缺失'),
  modelHashMismatch('模型哈希不匹配'),
  modelLoadFailed('模型加载失败'),
  unsupportedDevice('不支持的设备'),
  inputOpenFailed('输入文件打开失败'),
  unsupportedImageFormat('不支持的图片格式'),
  imageTooLarge('图片过大'),
  noDogDetected('未检测到警犬'),
  multipleDogsDetected('检测到多只警犬'),
  inferenceFailed('推理失败'),
  storageFull('存储空间不足'),
  queueFull('推理队列已满'),
  batchTooLarge('批量数量超限'),
  invalidRequest('无效请求'),
  taskNotFound('任务不存在'),
  batchNotFound('批次不存在'),
  taskCancelled('任务已取消'),
  reportExportFailed('报告导出失败'),
  internalError('内部错误');

  const ErrorCode(this.zh);
  final String zh;

  static ErrorCode fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => internalError);
}

class BackendError {
  const BackendError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.diagnostic,
  });

  final ErrorCode code;
  final String message;
  final bool retryable;
  final String? diagnostic;

  factory BackendError.fromJson(Map<String, dynamic> json) => BackendError(
        code: ErrorCode.fromName(json['code'] as String? ?? ''),
        message: json['message'] as String? ?? '',
        retryable: json['retryable'] as bool? ?? false,
        diagnostic: json['diagnostic'] as String?,
      );

  @override
  String toString() => '[${code.name}] $message';
}

class BackendState {
  const BackendState({required this.lifecycle, this.error});

  final BackendLifecycle lifecycle;
  final BackendError? error;

  factory BackendState.fromJson(Map<String, dynamic> json) => BackendState(
        lifecycle: BackendLifecycle.fromName(json['lifecycle'] as String? ?? ''),
        error: json['error'] == null
            ? null
            : BackendError.fromJson(json['error'] as Map<String, dynamic>),
      );
}

/// 命令调用的统一返回包装，对应 Kotlin 侧 `BackendResult<T>`。
class BackendResult<T> {
  const BackendResult.success(T this.value)
      : success = true,
        error = null;
  const BackendResult.failure(BackendError this.error)
      : success = false,
        value = null;
  const BackendResult._(this.success, this.value, this.error);

  final bool success;
  final T? value;
  final BackendError? error;

  bool get failed => !success;
}

/// 解析桥接层返回的 `{"success": bool, "value": ..., "error": ...}` JSON。
/// （Dart 静态方法不允许携带类型参数，故实现为顶层函数）
BackendResult<T> decodeBackendResult<T>(
  Map<String, dynamic> json,
  T? Function(Map<String, dynamic>? value) decode,
) {
  final ok = json['success'] as bool? ?? false;
  if (ok) {
    final v = json['value'];
    return BackendResult<T>._(
      true,
      decode(v is Map ? Map<String, dynamic>.from(v) : null),
      null,
    );
  }
  return BackendResult<T>._(
    false,
    null,
    BackendError.fromJson(Map<String, dynamic>.from(json['error'] as Map)),
  );
}

// ---------------------------------------------------------------------------
// 任务 / 批次
// ---------------------------------------------------------------------------

class TaskId {
  const TaskId(this.value);
  final String value;
  @override
  String toString() => value;
}

class BatchId {
  const BatchId(this.value);
  final String value;
  @override
  String toString() => value;
}

enum TaskPriority { interactive, batch }

class RecognitionRequest {
  const RecognitionRequest({
    required this.source,
    this.clientRequestId,
    this.saveOriginal = false,
    this.saveOverlay = true,
    this.priority = TaskPriority.interactive,
  });

  final String source;
  final String? clientRequestId;
  final bool saveOriginal;
  final bool saveOverlay;
  final TaskPriority priority;

  Map<String, dynamic> toJson() => {
        'source': source,
        'clientRequestId': clientRequestId,
        'saveOriginal': saveOriginal,
        'saveOverlay': saveOverlay,
        'priority': priority.name,
      };
}

class BatchRecognitionRequest {
  const BatchRecognitionRequest({required this.requests});
  final List<RecognitionRequest> requests;
}

enum TaskState {
  queued('排队中'),
  running('识别中'),
  cancelRequested('取消请求中'),
  completed('已完成'),
  failed('失败'),
  cancelled('已取消');

  const TaskState(this.zh);
  final String zh;

  static TaskState fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => queued);
}

enum TaskStage {
  queued('排队'),
  openingInput('打开图片'),
  decoding('解码图片'),
  detecting('犬只检测'),
  estimatingPose('关键点估计'),
  classifying('动作分类'),
  rendering('结果渲染'),
  persisting('结果保存'),
  finished('完成');

  const TaskStage(this.zh);
  final String zh;

  static TaskStage fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => queued);
}

class TaskEvent {
  const TaskEvent({
    required this.taskId,
    required this.state,
    required this.stage,
    required this.progressPercent,
    this.result,
    this.error,
    this.updatedAtEpochMillis = 0,
  });

  final String taskId;
  final TaskState state;
  final TaskStage stage;
  final int progressPercent;
  final RecognitionResult? result;
  final BackendError? error;
  final int updatedAtEpochMillis;

  bool get isTerminal =>
      state == TaskState.completed ||
      state == TaskState.failed ||
      state == TaskState.cancelled;

  TaskEvent copyWith({
    TaskState? state,
    TaskStage? stage,
    int? progressPercent,
    RecognitionResult? result,
    BackendError? error,
    int? updatedAtEpochMillis,
  }) =>
      TaskEvent(
        taskId: taskId,
        state: state ?? this.state,
        stage: stage ?? this.stage,
        progressPercent: progressPercent ?? this.progressPercent,
        result: result ?? this.result,
        error: error ?? this.error,
        updatedAtEpochMillis: updatedAtEpochMillis ?? this.updatedAtEpochMillis,
      );

  factory TaskEvent.fromJson(Map<String, dynamic> json) => TaskEvent(
        taskId: json['taskId'] as String? ?? '',
        state: TaskState.fromName(json['state'] as String? ?? ''),
        stage: TaskStage.fromName(json['stage'] as String? ?? ''),
        progressPercent: json['progressPercent'] as int? ?? 0,
        result: json['result'] == null
            ? null
            : RecognitionResult.fromJson(
                Map<String, dynamic>.from(json['result'] as Map)),
        error: json['error'] == null
            ? null
            : BackendError.fromJson(Map<String, dynamic>.from(json['error'] as Map)),
        updatedAtEpochMillis: json['updatedAtEpochMillis'] as int? ?? 0,
      );
}

enum BatchState {
  queued('排队中'),
  running('识别中'),
  completed('已完成'),
  cancelled('已取消'),
  failed('失败');

  const BatchState(this.zh);
  final String zh;

  static BatchState fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => queued);
}

class BatchEvent {
  const BatchEvent({
    required this.batchId,
    required this.state,
    required this.total,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.taskIds,
    this.error,
    this.updatedAtEpochMillis = 0,
  });

  final String batchId;
  final BatchState state;
  final int total;
  final int completed;
  final int failed;
  final int cancelled;
  final List<String> taskIds;
  final BackendError? error;
  final int updatedAtEpochMillis;

  int get finished => completed + failed + cancelled;
  int get progressPercent => total == 0 ? 100 : finished * 100 ~/ total;

  BatchEvent copyWith({
    BatchState? state,
    int? completed,
    int? failed,
    int? cancelled,
    BackendError? error,
    int? updatedAtEpochMillis,
  }) =>
      BatchEvent(
        batchId: batchId,
        state: state ?? this.state,
        total: total,
        completed: completed ?? this.completed,
        failed: failed ?? this.failed,
        cancelled: cancelled ?? this.cancelled,
        taskIds: taskIds,
        error: error ?? this.error,
        updatedAtEpochMillis: updatedAtEpochMillis ?? this.updatedAtEpochMillis,
      );

  factory BatchEvent.fromJson(Map<String, dynamic> json) => BatchEvent(
        batchId: json['batchId'] as String? ?? '',
        state: BatchState.fromName(json['state'] as String? ?? ''),
        total: json['total'] as int? ?? 0,
        completed: json['completed'] as int? ?? 0,
        failed: json['failed'] as int? ?? 0,
        cancelled: json['cancelled'] as int? ?? 0,
        taskIds: (json['taskIds'] as List? ?? []).map((e) => e.toString()).toList(),
        error: json['error'] == null
            ? null
            : BackendError.fromJson(Map<String, dynamic>.from(json['error'] as Map)),
        updatedAtEpochMillis: json['updatedAtEpochMillis'] as int? ?? 0,
      );
}

enum CancelResult {
  cancelled('已取消'),
  requested('取消请求已发出'),
  alreadyFinished('任务已结束'),
  notFound('未找到');

  const CancelResult(this.zh);
  final String zh;

  static CancelResult fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => notFound);
}

// ---------------------------------------------------------------------------
// 识别结果
// ---------------------------------------------------------------------------

enum ActionLabel {
  standing('站立', 'STANDING'),
  sitting('坐下', 'SITTING'),
  lying('趴下', 'LYING'),
  unknown('未知姿态', 'UNKNOWN');

  const ActionLabel(this.zh, this.en);
  final String zh;
  final String en;

  static ActionLabel fromName(String name) =>
      values.firstWhere((e) => e.en == name, orElse: () => unknown);
}

class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;

  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        left: (json['left'] as num?)?.toDouble() ?? 0,
        top: (json['top'] as num?)?.toDouble() ?? 0,
        right: (json['right'] as num?)?.toDouble() ?? 0,
        bottom: (json['bottom'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
}

class Keypoint {
  const Keypoint({
    required this.index,
    required this.name,
    required this.x,
    required this.y,
    required this.confidence,
  });

  final int index;
  final String name;
  final double x;
  final double y;
  final double confidence;

  factory Keypoint.fromJson(Map<String, dynamic> json) => Keypoint(
        index: json['index'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
}

enum QualityStatus {
  accepted('质量合格'),
  lowConfidence('低置信度'),
  insufficientKeypoints('关键点不足'),
  unknownPose('未知姿态');

  const QualityStatus(this.zh);
  final String zh;

  static QualityStatus fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => accepted);
}

enum RecognitionWarning {
  lowDetectionConfidence('检测置信度低'),
  lowKeypointConfidence('关键点置信度低'),
  lowActionConfidence('动作置信度低'),
  partialBodyVisible('身体部分可见');

  const RecognitionWarning(this.zh);
  final String zh;

  static RecognitionWarning fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => lowDetectionConfidence);
}

class InferenceTiming {
  const InferenceTiming({
    required this.totalMillis,
    required this.detectionMillis,
    required this.poseMillis,
    required this.classificationMillis,
  });

  final int totalMillis;
  final int detectionMillis;
  final int poseMillis;
  final int classificationMillis;

  factory InferenceTiming.fromJson(Map<String, dynamic> json) => InferenceTiming(
        totalMillis: json['totalMillis'] as int? ?? 0,
        detectionMillis: json['detectionMillis'] as int? ?? 0,
        poseMillis: json['poseMillis'] as int? ?? 0,
        classificationMillis: json['classificationMillis'] as int? ?? 0,
      );
}

class ModelInfo {
  const ModelInfo({
    required this.detectorName,
    required this.poseModelName,
    required this.actionModelName,
    required this.version,
  });

  final String detectorName;
  final String poseModelName;
  final String actionModelName;
  final String version;

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
        detectorName: json['detectorName'] as String? ?? '',
        poseModelName: json['poseModelName'] as String? ?? '',
        actionModelName: json['actionModelName'] as String? ?? '',
        version: json['version'] as String? ?? '',
      );
}

class RecognitionResult {
  const RecognitionResult({
    required this.recordId,
    required this.taskId,
    required this.source,
    required this.action,
    required this.actionScores,
    required this.dogBox,
    required this.keypoints,
    required this.quality,
    required this.warnings,
    this.originalLocation,
    this.overlayLocation,
    required this.timing,
    required this.modelInfo,
    this.createdAtEpochMillis = 0,
  });

  final String recordId;
  final String taskId;
  final String source;
  final ActionLabel action;
  final Map<ActionLabel, double> actionScores;
  final BoundingBox? dogBox;
  final List<Keypoint> keypoints;
  final QualityStatus quality;
  final List<RecognitionWarning> warnings;
  final String? originalLocation;
  final String? overlayLocation;
  final InferenceTiming timing;
  final ModelInfo modelInfo;
  final int createdAtEpochMillis;

  factory RecognitionResult.fromJson(Map<String, dynamic> json) {
    final rawScores = json['actionScores'] as Map? ?? {};
    final scores = <ActionLabel, double>{};
    rawScores.forEach((k, v) {
      scores[ActionLabel.fromName(k.toString())] = (v as num).toDouble();
    });
    return RecognitionResult(
      recordId: json['recordId'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      source: json['source'] as String? ?? '',
      action: ActionLabel.fromName(json['action'] as String? ?? ''),
      actionScores: scores,
      dogBox: json['dogBox'] == null
          ? null
          : BoundingBox.fromJson(Map<String, dynamic>.from(json['dogBox'] as Map)),
      keypoints: (json['keypoints'] as List? ?? [])
          .map((e) => Keypoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      quality: QualityStatus.fromName(json['quality'] as String? ?? ''),
      warnings: (json['warnings'] as List? ?? [])
          .map((e) => RecognitionWarning.fromName(e.toString()))
          .toList(),
      originalLocation: json['originalLocation'] as String?,
      overlayLocation: json['overlayLocation'] as String?,
      timing: InferenceTiming.fromJson(
          Map<String, dynamic>.from(json['timing'] as Map? ?? {})),
      modelInfo: ModelInfo.fromJson(
          Map<String, dynamic>.from(json['modelInfo'] as Map? ?? {})),
      createdAtEpochMillis: json['createdAtEpochMillis'] as int? ?? 0,
    );
  }
}

class RecognitionRecord {
  const RecognitionRecord({required this.result});
  final RecognitionResult result;

  factory RecognitionRecord.fromJson(Map<String, dynamic> json) =>
      RecognitionRecord(
        result: RecognitionResult.fromJson(
            Map<String, dynamic>.from(json['result'] as Map)),
      );
}

class HistoryQuery {
  const HistoryQuery({this.offset = 0, this.limit = 50});
  final int offset;
  final int limit;
}

class Page<T> {
  const Page({required this.items, required this.offset, required this.limit, required this.total});
  final List<T> items;
  final int offset;
  final int limit;
  final int total;

  factory Page.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) decode,
  ) =>
      Page(
        items: (json['items'] as List? ?? [])
            .map((e) => decode(Map<String, dynamic>.from(e as Map)))
            .toList(),
        offset: json['offset'] as int? ?? 0,
        limit: json['limit'] as int? ?? 50,
        total: json['total'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// 报告
// ---------------------------------------------------------------------------

enum ReportFormat {
  json('JSON', 'application/json'),
  csv('CSV', 'text/csv'),
  pdf('PDF', 'application/pdf');

  const ReportFormat(this.zh, this.mimeType);
  final String zh;
  final String mimeType;

  static ReportFormat fromName(String name) =>
      values.firstWhere((e) => e.name == name, orElse: () => json);
}

class ReportRequest {
  const ReportRequest({required this.recordIds, required this.format});
  final List<String> recordIds;
  final ReportFormat format;
}

class ReportResult {
  const ReportResult({
    required this.location,
    required this.mimeType,
    required this.recordCount,
  });

  final String location;
  final String mimeType;
  final int recordCount;

  factory ReportResult.fromJson(Map<String, dynamic> json) => ReportResult(
        location: json['location'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? '',
        recordCount: json['recordCount'] as int? ?? 0,
      );
}
