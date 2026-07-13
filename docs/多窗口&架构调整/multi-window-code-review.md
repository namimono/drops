# 多收集框重构代码 Review

> Review 日期：2026-07-13  
> Review 范围：当前 `new-multi` 工作区实现  
> 需求依据：[multi-window-refactoring-plan.md](./multi-window-refactoring-plan.md)  
> 进度依据：[multi-window-dev-progress.md](./multi-window-dev-progress.md)

## 1. 总体结论

当前实现的整体架构方向基本符合重构方案：

- macOS 主窗口已调整为隐藏的应用宿主。
- 快捷键、菜单栏和全局拖放检测已迁移到应用级协调器。
- `ShelfManager` 统一管理收集框创建、数量限制和关闭流程。
- 每个收集框使用独立 Flutter Engine / Dart isolate。
- 窗口级 Channel、拖放、拖出、进程和 Quick Look 能力集中到了 `WindowRuntime`。
- 手动收集框、晃动临时收集框和最多 20 个窗口的生命周期规则已有 Dart、Swift 单元测试。

但是，当前代码仍有 **2 个 P0 问题和 1 个 P1 问题**。其中两个 P0 会直接影响晃动与拖入这一核心流程，因此目前不建议将“macOS 多收集框核心能力”判定为验收通过。

## 2. Review Findings

### 2.1 P0：Flutter ready 后窗口会失去拖放能力

相关代码：

- `macos/Runner/WindowRuntime/WindowRuntime.swift:110`
- `lib/widgets/drop_target.dart:88`
- `macos/Runner/Input/GlobalInputCoordinator.swift:41`

`WindowRuntime` 在收到 `shelfReady` 后会立即移除启动阶段的全窗口 `earlyDropTarget`：

```swift
func markFlutterReady() {
  isFlutterReady = true
  if let early = earlyDropTarget {
    early.removeFromSuperview()
    dropTargets.removeAll { $0 === early }
    earlyDropTarget = nil
  }
  flushPendingDrops()
}
```

Flutter 的普通 DropTarget 并不会在首帧主动调用 `setDropTarget()`。当前只有以下两个回调会安装原生 DropTarget：

- `DragDropListener.onDragStart()`
- `DragDropListener.shakeDetected()`

但新的 `GlobalInputCoordinator` 只调用 `ShelfManager`，不再向 shelf Flutter Engine 发送 `dragStart` 或 `shakeDetected` 消息。因此在 `shelfReady` 之后，窗口通常没有任何原生 DropTarget。

预期影响：

- 快捷键或菜单创建的收集框无法正常拖入文件。
- 晃动创建的收集框只可能在 Flutter ready 前的短暂时间内接收 drop。
- Flutter ready 前排队、ready 后正常拖放的完整链路不成立。
- 直接违反方案中的“现有拖入能力保持可用”和“Flutter Engine 启动前完成拖放，内容不会丢失”。

建议：

1. 增加 `dropTargetReady` 握手，由 Flutter 在完成首帧布局并成功调用 `setDropTarget()` 后通知原生，再移除 `earlyDropTarget`；或
2. 让全窗口 DropTarget 常驻，由 Flutter DropTarget 只负责 UI hover 与业务区域判断；或
3. 恢复明确的窗口级 `dragStart` 定向事件，但不能向全部 Engine 广播。

建议优先采用显式 `dropTargetReady` 握手，避免依赖固定延迟。

### 2.2 P0：晃动框初始化完成后会激活应用并抢走 Finder 焦点

相关代码：

- `lib/shelf/shelf_bootstrap.dart:45`
- `macos/Runner/WindowRuntime/WindowRuntime.swift:276`
- `macos/Runner/Shelf/ShelfWindow.swift:121`

原生创建晃动框时正确使用了：

```swift
func showWithoutActivating() {
  alphaValue = 1
  orderFrontRegardless()
}
```

但是所有 shelf 在 Dart bootstrap 中都会再次执行：

```dart
await dropChannel.setVisible(true);
```

`WindowRuntime` 对 `setVisible(true)` 的处理包含：

```swift
window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```

因此，只要晃动框在用户仍然拖拽时完成 Dart 初始化，就会重新激活 ShakePin，覆盖 `showWithoutActivating()` 的保护。

预期影响：

- Finder 可能失去当前拖放源的焦点。
- 正在进行的外部拖放可能被中断或取消。
- 晃动框可能显示出来，但无法成功接收原本正在拖动的内容。
- 直接违反方案中“晃动框创建时不能强制激活应用”的要求。

建议：

- 根据 `ShelfContext.instance.source` 区分显示策略。
- `hotkey`、`menu` 来源可以调用激活版本的显示接口。
- `shake` 来源只能调用 `orderFront` 或新增的 `setVisibleWithoutActivating`。
- 最好由原生创建流程统一决定首次显示方式，Dart bootstrap 不再重复调用 `setVisible(true)`。

### 2.3 P1：关闭窗口不能清理该窗口的全部进程任务

相关代码：

- `macos/Runner/WindowRuntime/WindowHelpers.swift:96`
- `macos/Runner/WindowRuntime/WindowRuntime.swift:151`

`ProcessHandler` 目前只保存一个进程：

```swift
private var currentProcess: Process?
private var currentOutputPipe: Pipe?
private var currentErrorPipe: Pipe?
```

每次调用 `startProcess()` 都会覆盖上述引用。若同一收集框启动了多个任务，`cleanup()` 只能终止最后启动的一个进程。

预期影响：

- 较早启动的任务会在窗口关闭后继续运行，形成孤儿进程。
- 任务结束后可能尝试向已经销毁的 Flutter Engine 返回结果。
- `isProcessRunning()` 只能反映最后一个进程的状态。
- 不满足方案中“关闭窗口前取消属于该窗口的全部任务”的要求。

当前将 CLI 工具可用性检测改为串行，只解决了启动检测阶段的竞争，不能覆盖业务处理中可能出现的并发任务。

建议：

- 为每个任务生成 `taskId`。
- 使用 `[taskId: ProcessRecord]` 保存进程、输出管道和错误管道。
- `cancelProcess` 支持取消指定任务或全部任务。
- `WindowRuntime.dispose()` 遍历并终止当前窗口的全部任务。
- 终止回调执行前检查 runtime 是否仍有效，避免向已销毁 Engine 发送消息。

## 3. 验收项对照

| 验收项 | Review 结论 | 说明 |
|---|---|---|
| 快捷键每次创建新窗口 | 代码符合 | `AppHostController` 每次调用 `ShelfManager.createShelf` |
| 菜单每次创建新窗口 | 代码符合 | `New Shelf` 直接创建新的 menu shelf |
| 手动空窗口保持显示 | 代码符合 | macOS shelf 的 `itemListener` 不再因空列表隐藏窗口 |
| 晃动框空关、有内容保留 | 状态机符合，集成链路有风险 | DropTarget 和激活问题会影响实际 drop 是否成功 |
| 同一拖放周期最多一个晃动框 | 代码符合 | `dragSession.shakeShelfId` 防止重复创建 |
| 最多 20 个窗口 | 代码符合 | 第 20 个允许，第 21 个拒绝并提示音 |
| 各窗口业务状态隔离 | 基本符合 | 依赖独立 Engine / isolate；仍需实机回归插件和任务行为 |
| Flutter ready 前的 drop 不丢失 | 部分符合 | ready 前有队列，但 ready 后 DropTarget 被提前移除 |
| 晃动框不抢拖放源焦点 | 不符合 | Dart bootstrap 会再次激活应用 |
| 关闭窗口回收全部任务 | 不符合 | 只能追踪并终止最后一个进程 |
| 设置、更新不重复初始化 | 部分符合 | Dart bootstrap 已区分；插件仍对每个 Engine 完整注册 |
| Windows 保持原单窗口行为 | 代码分支保留 | 尚未进行本轮 Windows 实机回归 |

## 4. 测试与构建结果

### 4.1 Flutter 测试

执行：

```bash
flutter test
```

结果：**通过，共 14 个测试**。

其中多收集框生命周期测试覆盖：

- hotkey/menu 创建 persistent shelf。
- shake 创建 transient shelf。
- 同一拖放周期拒绝第二个 shake shelf。
- drop accepted 后 transient 转为 persistent。
- 未接收 drop 时随拖放结束关闭。
- persistent shelf 不因原拖放结束关闭。
- 新拖放周期允许再次创建 shake shelf。
- 第 20 个允许、第 21 个拒绝。
- closing/closed shelf 忽略迟到事件。

当前测试主要验证纯状态机，没有覆盖本次 Review 发现的原生 DropTarget 与窗口激活集成问题。

### 4.2 macOS 构建

执行 Debug 构建，结果：**通过**。

说明当前新增 Swift 文件、Xcode 工程引用和主要 Dart 入口能够完成构建。

### 4.3 Swift 生命周期测试

新增的 `ShelfLifecycleStoreTests` 共 9 个测试，使用正确的 `TEST_HOST` 后全部通过。

项目默认测试配置仍存在问题：

```text
TEST_HOST = $(BUILT_PRODUCTS_DIR)/shakepin.app/.../shakepin
```

实际构建产物为：

```text
ShakePin.app/Contents/MacOS/ShakePin
```

因此默认执行 `xcodebuild test` 会报告找不到 test host。建议修正 `RunnerTests` 各构建配置中的 `TEST_HOST`，确保测试无需命令行覆盖即可执行。

### 4.4 静态分析

`flutter analyze` 当前未通过，主要错误包括：

- `lib/app/license_app.dart` 引用不存在的 `lib/utils/license_service.dart`。
- Pods 构建生成目录中的 `build_tool` URI 无法解析。
- 其余已有 warning/info，包括未使用 import、`avoid_print` 等。

上述问题大部分不是本次多窗口改动直接引入，但说明项目当前没有干净的静态分析基线。建议在正式验收前恢复可重复执行的 analyze 配置，并排除生成目录。

## 5. 已知未完成项

开发进度文档中已经明确列出的以下内容，本次不重复判定为新增缺陷，但仍会影响最终交付：

- 多 Engine 插件兼容性验证和插件安全子集。
- 1 / 5 / 10 / 20 窗口性能与内存测试。
- 连续创建、关闭 100 次的泄漏测试。
- 重型任务应用级并发限制。
- 系统睡眠、退出、自动更新场景回归。
- Windows 单窗口回归。
- About ready 时序、旧 `showApp` 等残留路径清理。

## 6. 建议修复顺序

1. 修复 `earlyDropTarget` 移除时机，确保 ready 前后始终存在有效拖放目标。
2. 修复 shake shelf 的非激活显示策略。
3. 增加原生集成测试或可重复人工用例，验证 ready 前 drop、ready 后 drop 和 Finder 焦点不丢失。
4. 将 `ProcessHandler` 改为窗口级任务注册表，并验证关闭窗口能取消全部任务。
5. 修正 `RunnerTests.TEST_HOST`，让 Swift 测试可直接执行。
6. 完成开发进度文档中的 P0 人工回归和多 Engine 插件验证。

## 7. 最终判断

当前代码已经完成了多收集框所需的主要架构搭建，生命周期纯逻辑也基本符合设计；但拖放目标在 ready 后丢失、晃动框重新激活应用这两个问题会直接破坏核心用户路径。

建议当前状态标记为：

> **架构主体完成，核心集成尚未验收通过。**

修复两个 P0 并完成对应实机回归后，再重新判断阶段 2、阶段 3 是否可以正式标记为完成。
