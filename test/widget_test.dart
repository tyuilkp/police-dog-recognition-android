import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:police_dog_recognition_frontend/main.dart';
import 'package:police_dog_recognition_frontend/models/backend_models.dart';
import 'package:police_dog_recognition_frontend/services/app_state.dart';
import 'package:police_dog_recognition_frontend/services/backend_api.dart';
import 'package:police_dog_recognition_frontend/services/fake_backend_api.dart';

void main() {
  testWidgets('首页渲染并完成后端初始化', (tester) async {
    final api = FakeBackendApi();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BackendApi>.value(value: api),
          ChangeNotifierProvider(create: (_) => AppState(api)..init()),
        ],
        child: const PoliceDogApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('警犬姿态识别'), findsWidgets);
    expect(find.text('识别后端已就绪（离线）'), findsOneWidget);
    expect(find.text('单图识别'), findsOneWidget);
    expect(find.text('批量识别'), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);
  });

  test('FakeBackendApi 遵循 mock 输入约定', () async {
    final api = FakeBackendApi();
    await api.initialize();

    final standing = await api.submit(const RecognitionRequest(source: '/tmp/standing_dog.jpg'));
    expect(standing.success, isTrue);
    final event = await api
        .observeTask(standing.value!.value)
        .firstWhere((e) => e.isTerminal);
    expect(event.state, TaskState.completed);
    expect(event.result!.action, ActionLabel.standing);
    expect(event.result!.keypoints.length, 39);

    final nodog = await api.submit(const RecognitionRequest(source: '/tmp/nodog.jpg'));
    final nodogEvent = await api
        .observeTask(nodog.value!.value)
        .firstWhere((e) => e.isTerminal);
    expect(nodogEvent.state, TaskState.failed);
    expect(nodogEvent.error!.code, ErrorCode.noDogDetected);

    final broken = await api.submit(const RecognitionRequest(source: '/tmp/broken.jpg'));
    final brokenEvent = await api
        .observeTask(broken.value!.value)
        .firstWhere((e) => e.isTerminal);
    expect(brokenEvent.error!.code, ErrorCode.inputOpenFailed);

    final history = await api.queryHistory();
    expect(history.total, 1); // 只有 standing 成功并入库
  });

  test('批量识别汇总计数', () async {
    final api = FakeBackendApi();
    await api.initialize();
    final batch = await api.submitBatch(BatchRecognitionRequest(
      requests: const [
        RecognitionRequest(source: '/tmp/sitting_1.jpg'),
        RecognitionRequest(source: '/tmp/nodog_2.jpg'),
        RecognitionRequest(source: '/tmp/lying_3.jpg'),
      ],
    ));
    expect(batch.success, isTrue);
    final done = await api
        .observeBatch(batch.value!.value)
        .firstWhere((e) =>
            e.state == BatchState.completed ||
            e.state == BatchState.cancelled ||
            e.state == BatchState.failed);
    expect(done.state, BatchState.completed);
    expect(done.total, 3);
    expect(done.completed, 2);
    expect(done.failed, 1);
    expect(done.progressPercent, 100);
  });
}
