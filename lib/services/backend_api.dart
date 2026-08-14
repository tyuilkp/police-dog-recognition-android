import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/backend_models.dart';
import 'fake_backend_api.dart';

/// 对 pdr `RecognitionBackend` 接口的 Dart 侧抽象。
///
/// Android 上由 [MethodChannelBackendApi] 桥接真实的 Kotlin backend-core；
/// 其他平台（开发预览 / 单元测试）使用 [FakeBackendApi]。
abstract class BackendApi {
  Future<BackendState> getState();

  Future<BackendResult<void>> initialize({
    int maxBatchSize = 50,
    bool persistResults = true,
  });

  Future<BackendResult<TaskId>> submit(RecognitionRequest request);

  Future<BackendResult<BatchId>> submitBatch(BatchRecognitionRequest request);

  Stream<TaskEvent> observeTask(String taskId);

  Stream<BatchEvent> observeBatch(String batchId);

  Future<CancelResult> cancelTask(String taskId);

  Future<CancelResult> cancelBatch(String batchId);

  Future<RecognitionResult?> getResult(String taskId);

  Future<Page<RecognitionRecord>> queryHistory({int offset = 0, int limit = 50});

  Future<BackendResult<void>> deleteRecords(List<String> recordIds);

  Future<BackendResult<ReportResult>> exportReport(ReportRequest request);

  Future<BackendResult<void>> release();
}

/// 平台选择：Android 走真实桥接，其余平台走 Dart 内嵌 Mock。
BackendApi createBackendApi() {
  if (!kIsWeb && Platform.isAndroid) {
    return MethodChannelBackendApi();
  }
  return FakeBackendApi();
}

/// 通过 MethodChannel / EventChannel 调用 Android 桥接层（BackendBridge.kt）。
class MethodChannelBackendApi implements BackendApi {
  MethodChannelBackendApi({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.policedog.recognition/backend');

  static const String _tag = 'MethodChannelBackendApi';

  final MethodChannel _channel;

  Future<Map<String, dynamic>> _invoke(String method, [Map<String, dynamic>? args]) async {
    final raw = await _channel.invokeMethod<String>(method, args);
    return Map<String, dynamic>.from(jsonDecode(raw ?? '{"success":false}') as Map);
  }

  @override
  Future<BackendState> getState() async {
    try {
      final json = Map<String, dynamic>.from(
          jsonDecode(await _channel.invokeMethod<String>('getState') ?? '{}') as Map);
      return BackendState.fromJson(json);
    } on PlatformException catch (e) {
      debugPrint('$_tag getState failed: ${e.message}');
      return const BackendState(lifecycle: BackendLifecycle.failed);
    }
  }

  @override
  Future<BackendResult<void>> initialize({
    int maxBatchSize = 50,
    bool persistResults = true,
  }) async {
    final json = await _invoke('initialize', {
      'maxBatchSize': maxBatchSize,
      'persistResults': persistResults,
    });
    return decodeBackendResult<void>(json, (_) {});
  }

  @override
  Future<BackendResult<TaskId>> submit(RecognitionRequest request) async {
    final json = await _invoke('submit', request.toJson());
    return decodeBackendResult<TaskId>(json, (v) => TaskId(v!['taskId'] as String));
  }

  @override
  Future<BackendResult<BatchId>> submitBatch(BatchRecognitionRequest request) async {
    final json = await _invoke('submitBatch', {
      'requests': request.requests.map((r) => r.toJson()).toList(),
    });
    return decodeBackendResult<BatchId>(json, (v) => BatchId(v!['batchId'] as String));
  }

  @override
  Stream<TaskEvent> observeTask(String taskId) =>
      _observe('task', taskId).map(TaskEvent.fromJson);

  @override
  Stream<BatchEvent> observeBatch(String batchId) =>
      _observe('batch', batchId).map(BatchEvent.fromJson);

  Stream<Map<String, dynamic>> _observe(String kind, String id) async* {
    final channelName = await _channel.invokeMethod<String>(
      'registerEventObserver',
      {'kind': kind, 'id': id},
    );
    if (channelName == null) {
      throw StateError('注册事件观察者失败：$kind/$id');
    }
    yield* EventChannel(channelName)
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(jsonDecode(e as String) as Map));
  }

  @override
  Future<CancelResult> cancelTask(String taskId) async {
    final raw = await _channel.invokeMethod<String>('cancelTask', {'taskId': taskId});
    return CancelResult.fromName(raw ?? '');
  }

  @override
  Future<CancelResult> cancelBatch(String batchId) async {
    final raw = await _channel.invokeMethod<String>('cancelBatch', {'batchId': batchId});
    return CancelResult.fromName(raw ?? '');
  }

  @override
  Future<RecognitionResult?> getResult(String taskId) async {
    final raw = await _channel.invokeMethod<String>('getResult', {'taskId': taskId});
    if (raw == null || raw == 'null') return null;
    return RecognitionResult.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  @override
  Future<Page<RecognitionRecord>> queryHistory({int offset = 0, int limit = 50}) async {
    final raw = await _channel.invokeMethod<String>(
      'queryHistory',
      {'offset': offset, 'limit': limit},
    );
    return Page.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw ?? '{"items":[]}') as Map),
      RecognitionRecord.fromJson,
    );
  }

  @override
  Future<BackendResult<void>> deleteRecords(List<String> recordIds) async {
    final json = await _invoke('deleteRecords', {'recordIds': recordIds});
    return decodeBackendResult<void>(json, (_) {});
  }

  @override
  Future<BackendResult<ReportResult>> exportReport(ReportRequest request) async {
    final json = await _invoke('exportReport', {
      'recordIds': request.recordIds,
      'format': request.format.name,
    });
    return decodeBackendResult<ReportResult>(json, (v) => v == null ? null : ReportResult.fromJson(v));
  }

  @override
  Future<BackendResult<void>> release() async {
    final json = await _invoke('release');
    return decodeBackendResult<void>(json, (_) {});
  }
}
