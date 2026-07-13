# 多收集框重构 · 开发进度

> 更新日期：2026-07-13  
> 对应方案：[multi-window-refactoring-plan.md](./multi-window-refactoring-plan.md)  
> 故障排查：[multi-window-troubleshooting.md](./multi-window-troubleshooting.md)  
> 代码 Review：[multi-window-code-review.md](./multi-window-code-review.md)  
> 基线分支：`dev`  
> 平台范围：macOS 多收集框；Windows 保持单窗口

---

## 1. 总体进度

| 阶段 | 方案内容 | 状态 | 说明 |
|------|----------|------|------|
| A / 阶段 0 | 领域模型与单测基线 | **已完成** | Dart + Swift 生命周期状态机与单测 |
| B / 阶段 1 | AppHost + WindowRuntime 抽取 | **基本完成** | 能力已拆出；未再拆成多个 `*Module.swift` 文件 |
| C / 阶段 2 | 手动多收集框（快捷键/菜单） | **已完成** | 独立 Engine、`shelfMain`、上限 20、关闭销毁 |
| D / 阶段 3 | 晃动临时收集框 | **已完成** | DragSession、transient→persistent、空关有留 |
| E / 阶段 4–5 | 回归、资源治理、旧路径清理 | **部分完成** | Review 指出的 P0/P1 已修；人工回归与性能/插件清单未做完 |

**综合判断：架构与核心集成缺口（拖放常驻、晃动不抢焦点、关闭清全部任务）已按 Review 修复；正式验收仍差系统人工回归与多 Engine 插件验证。**

---

## 2. 已实现能力（用户可感知）

- 全局快捷键每次新建一个 **persistent** 收集框
- 菜单栏 **New Shelf** 每次新建一个 persistent 收集框
- 手动创建的空框不会因 `items` 为空自动关闭
- 晃动鼠标：同一拖放周期最多创建一个 **transient** 框
- 晃动框未接收内容：拖放结束后自动关闭
- 晃动框成功 drop：立即转为 persistent，之后只可由用户关闭
- 同时最多 **20** 个收集框；超出拒绝创建并 `NSSound.beep()`
- 每窗独立 Flutter Engine / isolate，文件列表与模式状态天然隔离
- 关闭按钮走 `closeSelf` → `ShelfManager.closeShelf` → Engine shutdown
- Windows 路径仍使用原有 `showApp` / `hideApp` / `keepEmptyShelfVisible`

---

## 3. 已落地的架构改动

### 3.1 原生（macOS）

| 模块 | 路径 | 职责 |
|------|------|------|
| AppHost | `macos/Runner/AppHost/` | 菜单栏、快捷键入口、设置窗、设置副作用 |
| Input | `macos/Runner/Input/GlobalInputCoordinator.swift` | 拖放周期、晃动/Shift 检测 |
| Shelf | `macos/Runner/Shelf/` | 生命周期存储、Manager、ShelfWindow |
| WindowRuntime | `macos/Runner/WindowRuntime/` | 每窗 Channel / Drop / Drag / Process / QL 等 |
| Host 窗口 | `macos/Runner/MainFlutterWindow.swift` | 隐藏宿主：settings / tray / 插件宿主，**不再是收集框** |

关键行为接线：

- `AppHostController` 启动时注册菜单栏 + `GlobalHotkeyManager` + `GlobalInputCoordinator`
- `ShelfManager` 统一 `createShelf` / `markDropAccepted` / `endExternalDrag` / `closeShelf`
- `ShelfWindow`：`FlutterDartProject.dartEntrypointArguments` 传入 `shelfId` + source，`run(withEntrypoint: "shelfMain")`
- **常驻拖放**：`ShelfWindow` 自身注册 `NSDraggingDestination`，不再依赖 `shelfReady` 后拆除 `earlyDropTarget`；ready 前入队、ready 后 flush 仍保留
- Drop 成功以原生 `performDragOperation` 为准，先 `markDropAccepted` 再投递给 Flutter（`pastePerform`）
- **进程任务**：`ProcessHandler` 按 `taskId` 注册表管理，`dispose`/`cancelProcess` 终止该窗全部任务；销毁后不再向 Engine 发 cli 输出

### 3.2 Flutter / Dart

| 模块 | 路径 | 职责 |
|------|------|------|
| 入口 | `lib/main.dart` 内 `shelfMain` | 必须与 `main` 同库；macOS 无 libraryURI |
| Bootstrap | `lib/shelf/shelf_bootstrap.dart` | 窗级依赖初始化；不上 autoUpdater / tray；**不再 `setVisible(true)`** |
| Context | `lib/shelf/shelf_context.dart` | `shelfId` / source / `isShelfEngine` |
| 生命周期模型 | `lib/shelf/shelf_lifecycle.dart` | 与原生规则对齐的纯逻辑 |
| 宿主入口 | `lib/main.dart` | macOS 跑 `HostApp`；Windows 仍跑 `MainApp` |
| 收集 UI | `lib/app/main_drop_app.dart` | macOS shelf 引擎忽略 shake/hotkey 创建与空框自动 hide |
| 关闭 | `lib/app/main_drop/drop_section.dart` | macOS 调用 `dropChannel.closeSelf()` |
| Channel | `lib/utils/drop_channel.dart` | `shelfReady` / `closeSelf` / `setVisibleWithoutActivating`；listener 查找失败安全处理 |

晃动框显示策略：

- 原生：`shake` → `showWithoutActivating()`（`orderFrontRegardless`）
- Dart bootstrap：**不**调用会触发 `NSApp.activate` 的 `setVisible(true)`；hotkey/menu 仅 `orderFront()`，shake 完全交给原生首次显示

### 3.3 测试与文档

- Dart：`test/shelf_lifecycle_test.dart`（方案 §13.1 主要用例）
- Swift：`macos/RunnerTests/ShelfLifecycleStoreTests.swift`
- `RunnerTests.TEST_HOST` 已改为 `ShakePin.app/.../ShakePin`（可直接跑宿主测试）
- 排查文档：`docs/multi-window-troubleshooting.md`
- Review 文档：`docs/multi-window-code-review.md`

---

## 4. 相对方案的简化 / 偏差（已知）

这些不是“没做”，而是实现时做了合并或折中，后续可再拆：

1. **WindowRuntime 未拆成多个 `*Module.swift`**  
   能力集中在 `WindowRuntime.swift` + `WindowHelpers.swift`，避免复制第二套 Channel switch，但文件仍偏大。

2. **未单独建 `ShakeDetector` / `DragSessionTracker` 文件**  
   逻辑合入 `GlobalInputCoordinator`。

3. **未单独建 `shelf_app.dart` / `ShelfSession.swift`**  
   UI 直接复用 `MainDropApp`；会话数据为 `ShelfSessionRecord`（在 `ShelfModels.swift`）。

4. **Shelf Engine 仍调用完整 `RegisterGeneratedPlugins`**  
   尚未做「宿主专用插件 / 窗口安全插件子集」分流；`auto_updater` / `tray_manager` 虽在 Dart 侧未在 shelf bootstrap 初始化，但原生插件仍会注册到每个 Engine。

5. **Settings 通知仍可能通过宿主 `MainFlutterWindow` 找 messenger**  
   已改为走 `AppHostController.handleSettingChange`，不再把主窗当收集框，但「找宿主窗」的形态还在。

6. **拖放结束有 50ms 延迟归并**  
   用于对齐 mouseUp 与 `performDragOperation` 时序；状态仍由 `ShelfManager` 裁决，不是用延迟代替状态机。

7. **常驻拖放落在 Window，而非 Flutter 区域 DropTarget 握手**  
   Review 建议的 `dropTargetReady` 与「全窗口常驻」二选一后，采用窗口级 `NSDraggingDestination`；Flutter `setDropTarget` 仍可用于拖放过程中的 hover 区域，但不再是唯一可用落点。

---

## 5. Code Review 修复记录（2026-07-13）

依据 [multi-window-code-review.md](./multi-window-code-review.md) 完成：

| 级别 | 问题 | 状态 | 修复要点 |
|------|------|------|----------|
| P0 | `shelfReady` 后移除 `earlyDropTarget`，窗口失去拖放能力 | **已修复** | `ShelfWindow` 常驻注册拖放；去掉 ready 时拆除 early 目标的路径 |
| P0 | Dart bootstrap `setVisible(true)` 激活应用，晃动框抢 Finder 焦点 | **已修复** | bootstrap 不再 `setVisible(true)`；shake 仅原生非激活显示；新增 `setVisibleWithoutActivating` |
| P1 | `ProcessHandler` 只保留最后一个进程，关闭清不干净 | **已修复** | `[taskId: ProcessRecord]` 注册表；`cleanup` 终止全部；dispose 后跳过 cli 回调 |
| 构建 | `RunnerTests.TEST_HOST` 指向错误的 `shakepin.app` | **已修复** | 改为 `ShakePin.app/.../ShakePin` |

---

## 6. 未完成 / 待办（跟踪用）

### P0 · 影响正确性或稳定性（建议优先）

- [ ] **人工核心回归**（尚未系统跑完；Review 修复后需重点复验下列项）
  - [ ] 快捷键连续开多个空框，互不关闭，且可正常拖入
  - [ ] 菜单 New Shelf / Settings / About / Quit
  - [ ] 晃动：空关、有内容保留、同一次拖放只出一个
  - [ ] **晃动创建过程中 Finder 焦点不丢、拖放不被中断**
  - [ ] **Flutter ready 前 drop 入队，ready 后仍可继续拖入**
  - [ ] 拖到已有 persistent 窗：只投递文件，不新建、不误关晃动框
  - [ ] 粘贴只进当前 key window
  - [ ] 关闭一窗不影响其他窗的 items / 模式 / 进度
  - [ ] 压缩 / 归档 / Quick Look / 拖出 在单窗内可用
  - [ ] **关闭有进行中任务的窗口：全部子进程被终止、无孤儿进程**
  - [ ] 达 20 上限行为与不崩溃
- [ ] **多 Engine 插件实机验证**
  - [ ] 列出宿主-only vs shelf 可用插件
  - [ ] 对不支持多 Engine 的能力改为宿主代理或 shelf 侧禁用
  - [ ] 收敛 shelf 的 `RegisterGeneratedPlugins` 为安全子集（若验证有问题）
- [x] **关闭时任务清理（代码）**
  - [x] `ProcessHandler.cleanup` 覆盖该窗全部进行中任务
  - [ ] 关闭有进行中压缩/归档时的用户提示（方案建议取消任务）

### P1 · 方案已写但未实现的治理项

- [ ] 重型任务**应用级并发上限**（防止 20 窗同时打满 CPU）
- [ ] 1 / 5 / 10 / 20 窗的**内存与创建耗时**记录
- [ ] 连续创建/关闭 100 次检查 Engine / Timer / Channel 泄漏
- [ ] 系统睡眠恢复、应用退出、自动更新场景回归
- [ ] 将 WindowRuntime 按模块文件再拆（可选，利于维护）
- [ ] 抽出独立 `ShakeDetector` / `DragSessionTracker`（可选）

### P2 · 代码残留与清理

- [ ] macOS shelf 路径上，`crop_app` / `minify_settings` 仍调用 `showApp()`——需确认在多窗下是否只影响当前窗尺寸，必要时改为只 `setFrame`/`setVisible` 当前 runtime
- [ ] `keepEmptyShelfVisible` / `showApp` / `resetFrameAndHide` 仍保留给 Windows；可加注释或 `#` 分区，避免 macOS 误用回流
- [ ] About 从菜单打开时用「新建窗 + 延迟 invoke menu tag」——可改为更稳妥的 ready 后回调
- [x] 早期 DropTarget 与 ready 后拖放空窗问题——已改为窗口级常驻拖放（见 §5）

### 明确不在本期（方案非目标）

- Windows 多窗口
- 应用重启后恢复全部收集框
- 跨窗口拖文件迁移任务状态
- 换语言/SwiftUI 重写
- 20 窗无限并发重型媒体任务

---

## 7. 验收对照（相对方案 §14 + Review）

| 验收项 | 状态 |
|--------|------|
| 快捷键/菜单每次新建 | 代码已实现，待人工确认 |
| 手动空窗不自动关 | 代码已实现（macOS shelf） |
| 晃动空关 / 有内容保留 | 代码已实现，待人工确认（含拖放链路） |
| 同拖放周期最多一个晃动框 | 状态机 + Input 已实现 |
| 最多 20 个 | 已实现 |
| 各窗状态隔离 | 依赖独立 isolate，待多窗实机确认 |
| Flutter ready 前 drop 不丢失 / ready 后仍可拖入 | **代码已修**（窗口常驻拖放 + 队列 flush），待人工确认 |
| 晃动框不抢拖放源焦点 | **代码已修**（bootstrap 不 activate），待人工确认 |
| 关闭窗口回收全部任务 | **代码已修**（任务注册表），待人工确认；用户提示未做 |
| 设置/更新不因多 Engine 重复初始化 | Dart bootstrap 已区分；插件注册仍待验证 |
| 关闭不崩溃、资源可回收 | 有关闭路径，缺压测 |
| Windows 单窗不破坏 | 代码分支保留，未在本轮重点验证 |

---

## 8. 建议下一迭代顺序

1. 按 §6 P0 做一轮 macOS 人工回归，**优先复验 Review 三项修复**（常驻拖放、晃动焦点、关闭清任务）  
2. 根据失败点再修插件 / 时序边角  
3. 补插件清单与 shelf 插件子集  
4. 做 5/10/20 窗内存抽样与关闭泄漏检查  
5. 再处理 P2 残留 API、关闭任务用户提示、About 打开时序  

---

## 9. 变更文件速查（本轮主要）

**新增**

- `macos/Runner/AppHost/*`
- `macos/Runner/Input/GlobalInputCoordinator.swift`
- `macos/Runner/Shelf/*`
- `macos/Runner/WindowRuntime/*`
- `lib/shelf/*`
- `test/shelf_lifecycle_test.dart`
- `macos/RunnerTests/ShelfLifecycleStoreTests.swift`
- `docs/multi-window-troubleshooting.md`
- `docs/multi-window-code-review.md`
- 本文档

**大幅修改**

- `macos/Runner/MainFlutterWindow.swift`（宿主化）
- `macos/Runner/AppDelegate.swift`
- `macos/Runner/DropTarget.swift`（drop accepted 回调）
- `macos/Runner/SettingsWindow.swift`（SettingsBridge）
- `macos/Runner/Shelf/ShelfWindow.swift`（窗口级常驻拖放）
- `macos/Runner/WindowRuntime/WindowRuntime.swift`（ready 不再拆 early；非激活显示；任务取消）
- `macos/Runner/WindowRuntime/WindowHelpers.swift`（ProcessHandler 任务注册表）
- `lib/main.dart`
- `lib/app/main_drop_app.dart`
- `lib/app/main_drop/drop_section.dart`
- `lib/shelf/shelf_bootstrap.dart`（去掉会抢焦点的 `setVisible(true)`）
- `lib/utils/drop_channel.dart`（`setVisibleWithoutActivating`）
- `lib/utils/handle_menu_item.dart`
- `macos/Runner.xcodeproj/project.pbxproj`（含 `TEST_HOST` → ShakePin）
