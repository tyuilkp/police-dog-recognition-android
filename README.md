# police-dog-recognition-frontend — 警犬姿态与动作识别（Android 前端）

基于 [police-dog-recognition](https://github.com/tyuilkp/police-dog-recognition) 仓库提供的
`backend-core`（`RecognitionBackend` 接口 + Mock 实现）开发的 Flutter Android 前端。

> 后端仓库由他人独立维护，本仓库不包含其源码目录；本仓库通过内嵌的
> `backend-core` 源码副本（见下方架构图）进行构建，接口变更时需从上游同步。

识别目标：单只警犬的 **站立 / 坐下 / 趴下** 动作与 **39 个 SuperAnimal-Quadruped 关键点**。
当前阶段后端为 Mock 引擎（联调版），端侧模型转换验证后通过同一接口接入。

## 架构

```
┌─────────────────────────── Flutter (Dart) ───────────────────────────┐
│  lib/pages/        首页 · 单图识别 · 批量识别 · 历史记录 · 详情 · 关于  │
│  lib/widgets/      关键点覆盖图 · 动作徽章 · 置信度条 · 阶段标签        │
│  lib/models/       backend-core 领域模型镜像（BackendModels.kt）       │
│  lib/services/     BackendApi 抽象 + MethodChannel / Fake 两种实现     │
└──────────────────────────────┬───────────────────────────────────────┘
                               │ MethodChannel / EventChannel
┌──────────────────────────────┴───────────────────────────────────────┐
│  android/app/.../bridge/     BackendBridge · BackendJson · BackendHolder│
│  android/app/.../backend/    pdr backend-core 源码副本（11 个 .kt）     │
│                              MockBackendFactory → RecognitionBackend   │
└───────────────────────────────────────────────────────────────────────┘
```

- Flutter 侧只依赖 pdr 的 `api` 与 `mock` 包，符合 `docs/BACKEND_HANDOFF.md`
  的前端依赖边界约定；
- 事件（任务进度 / 批次进度）通过动态注册的 EventChannel 推送，对应
  `observeTask / observeBatch` 的 `Flow<TaskEvent> / Flow<BatchEvent>`；
- 除 Android 外（桌面预览 / 单元测试）自动使用 `FakeBackendApi`，
  其行为镜像 Mock 输入约定（`standing/sit/lie/nodog/multidog/broken`）。

## 页面

| 页面 | 说明 |
|---|---|
| 首页 | 后端状态卡片 + 功能入口（单图 / 批量 / 历史 / 关于） |
| 单图识别 | 拍照或相册选图 → 阶段进度 → 动作结论 + 关键点覆盖图 + 概率/耗时/模型信息 |
| 批量识别 | 多选图片 → 队列顺序识别 → 批次汇总 + 逐任务状态 → 详情跳转 |
| 历史记录 | 分页查询、下拉刷新、多选删除、导出 JSON/CSV/PDF 报告 |
| 关于系统 | 接口契约清单、模型方案与许可声明 |

## 构建

环境要求：Flutter 3.47+、JDK 17（AGP 9 的 `JdkImageTransform` 在 JDK 26 下会失败，
需 `flutter config --jdk-dir=/path/to/jdk17`）、Android SDK 36。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 模板 release 使用 debug 签名（可直接安装）；正式分发需替换签名配置。

## 接口契约速览（RecognitionBackend）

`initialize` · `submit` / `submitBatch` · `observeTask` / `observeBatch` ·
`cancelTask` / `cancelBatch` · `getResult` / `queryHistory` ·
`deleteRecords` · `exportReport` · `release`

详见 [BACKEND_HANDOFF.md](https://github.com/tyuilkp/police-dog-recognition/blob/master/docs/BACKEND_HANDOFF.md)。

## 许可提醒

SuperAnimal 模型由 DeepLabCut 官方声明仅供研究、非商业用途，正式交付前需甲方确认并留档。
