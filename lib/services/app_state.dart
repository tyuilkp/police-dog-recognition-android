import 'package:flutter/foundation.dart';

import '../models/backend_models.dart';
import 'backend_api.dart';

/// 全局后端生命周期状态：启动时初始化、失败重试、手动释放重置。
class AppState extends ChangeNotifier {
  AppState(this.api);

  final BackendApi api;

  BackendLifecycle lifecycle = BackendLifecycle.uninitialized;
  BackendError? backendError;
  bool initializing = false;

  bool get ready => lifecycle == BackendLifecycle.ready;

  Future<void> init() async {
    if (initializing || lifecycle == BackendLifecycle.ready) return;
    initializing = true;
    notifyListeners();
    final result = await api.initialize();
    lifecycle = result.success
        ? BackendLifecycle.ready
        : BackendLifecycle.failed;
    backendError = result.error;
    initializing = false;
    notifyListeners();
  }

  Future<void> retry() async {
    if (lifecycle == BackendLifecycle.ready) return;
    await init();
  }

  Future<void> reset() async {
    await api.release();
    lifecycle = BackendLifecycle.uninitialized;
    backendError = null;
    notifyListeners();
    await init();
  }
}
