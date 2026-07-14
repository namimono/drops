# 阶段 1 · 代码审查问题清单

> 审查日期：2026-07-14  
> 修复回写：2026-07-14  
> 审查范围：`macos-native/Drops/Domain/`、`Application/`、`ShelfUI/`、`Input/`、`DropsTests/` 及阶段 1 验收文档  
> 对应实施：[stage-1-shelf-domain-and-window.md](./stage-1-shelf-domain-and-window.md)  
> 当前结论：**审查提出的 5 项缺陷均已关闭并通过自动化回归（42/42）。手工 S1-01 / S1-07 / S1-08 / S1-10 已通过；阶段 1 可退出。**

## 1. 审查证据

| 检查项 | 结果 | 说明 |
|---|---|---|
| Debug 构建 | **通过** | `xcodebuild ... -configuration Debug ... build` → `BUILD SUCCEEDED` |
| Release 构建 | **通过** | `xcodebuild ... -configuration Release ... build` → `BUILD SUCCEEDED` |
| 原生单元测试 | **通过（修复后 42/42）** | `xcodebuild test -scheme Drops -destination 'platform=macOS'`（2026-07-14） |
| Xcode 静态分析 | **通过** | `xcodebuild analyze ...` → `ANALYZE SUCCEEDED`（审查当日） |
| 拖拽会话异常序列 | **已修复并回归** | 抢占旧会话、错误/迟到 accept、同 ID 幂等 begin |
| 手工验收 | **通过** | S1-01 / S1-07 / S1-08 / S1-10 于 2026-07-14 手工通过 |

## 2. 问题摘要

| 编号 | 级别 | 问题 | 影响验收 | 状态 |
|---|---|---|---|---|
| REV-S1-001 | P1 | 新拖拽会话会直接覆盖旧会话，可能遗留永不自动关闭的临时架 | S1-05、S1-10 | **已关闭** |
| REV-S1-002 | P1 | 接收事件忽略拖拽会话 ID，可由错误/迟到会话错误晋升临时架 | S1-05、S1-09 | **已关闭** |
| REV-S1-003 | P1 | “快速切换”测试绕过窗口动画且不检查最终窗口尺寸 | S1-06 | **已关闭** |
| REV-S1-004 | P1 | 正式宿主沿用 Stage 0 Demo 的启动行为，启动即抢焦点并自动创建内容架 | S1-01、产品低打扰目标 | **已关闭** |
| REV-S1-005 | P2 | `dragReady` 仅等价于窗口可见，不能证明拖放目标已注册或可接收内容 | 后续 Stage 2、性能口径 | **已关闭** |

## 3. 详细问题与修复

### REV-S1-001 · 新会话覆盖后遗留旧临时架（P1）· 已关闭

**修复**

- `beginExternalDrag`：同 ID 幂等；不同 ID 先收尾旧会话并返回未接收的 transient shelf id。
- `ShelfManager` 在 begin 时关闭返回的 orphan 窗口。
- 回归：`testNewDragPreemptsOldSessionAndClosesOrphanTransient`、`testBeginSameDragSessionIsIdempotent`、`testPreemptedDragClosesOrphanTransientWindow`。

### REV-S1-002 · 错误会话可晋升临时架（P1）· 已关闭

**修复**

- `markDropAccepted` 仅对 `.transient` 生效，且要求 `dragSessionId` 与 `associatedDragSessionId`、当前 `.dragging` 会话三者一致。
- 持久架内容走 `simulateReceiveContent` / 后续 Stage 2 内容 API，不复用晋升接口。
- 回归：错误/nil ID、会话结束后迟到 accept、已晋升再 accept。

### REV-S1-003 · S1-06 自动化未覆盖真实窗口动画（P1）· 已关闭

**修复**

- 暴露 `ShelfWindowController.size(for:)`、`frame` 与 `ShelfManager.windowFrame` / `setAnimatesPresentationChanges`。
- 快速切换测试断言最终 `NSWindow.frame` 与领域展示态一致。
- 新增保留动画的集成测试，等待动画结束后断言 collapsed/expanded 尺寸。
- 收起态宽度改为 280（与空态同宽、高度 160），避免骨架按钮 Auto Layout 把窗口撑破目标宽。

### REV-S1-004 · 启动即激活并自动创建内容架（P1）· 已关闭

**修复**

- `ApplicationController.start()` 只安装菜单栏与全局快捷键，不再 `NSApp.activate` 或自动 `createPersistentShelf`。
- 与 PRD 创建入口（快捷键 / 菜单 / 摇动）及低打扰目标一致。

### REV-S1-005 · `dragReady` 就绪语义退化为“窗口可见”（P2）· 已关闭

**修复**

- 里程碑改名为 `transientWindowVisible`（Stage 1 仅表示临时窗已上屏）。
- `isDragDestinationReady` 要求窗口可见且 `registeredDraggedTypes` 非空；Stage 1 无注册故为 `false`。
- Stage 2 注册真实拖放类型后可再引入 `dragReady` 性能口径。

## 4. 处理优先级与退出建议

1. ~~修复 REV-S1-001、REV-S1-002~~ **已完成**。
2. ~~修复 REV-S1-004~~ **已完成**。
3. ~~补齐 REV-S1-003 / REV-S1-005~~ **已完成**。
4. ~~执行 S1-01、S1-07、S1-08、S1-10 手工验收~~ **已完成**；阶段 1 已退出，可开始 Stage 2。
