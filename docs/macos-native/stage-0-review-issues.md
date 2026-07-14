# 阶段 0 · 代码审查问题清单

> 审查日期：2026-07-14  
> 审查范围：`macos-native/` 原生工程、阶段 0 方案/进度/验证文档  
> 当前结论：**阶段 0 部分完成，存在阻断窗口原型验收的 P0 缺陷；阶段 1 尚未开始。**

## 1. 审查证据

| 检查项 | 结果 | 说明 |
|---|---|---|
| Debug 构建 | **通过** | `xcodebuild ... build` 返回 `BUILD SUCCEEDED` |
| 原生单元测试 | **通过** | `ManagedTemporaryFileStoreTests` 8/8；仅覆盖受管临时文件领域 |
| Xcode 静态分析 | **通过** | `xcodebuild analyze` 返回成功 |
| 实际启动 | **失败** | Drops 进程存活，但 WindowServer 中没有 Drops 窗口 |
| 运行时对象检查 | **失败** | `NSApplication.shared.delegate == nil`，`NSApp.windows.count == 0` |
| 阶段 1 实现核对 | **未开始** | 未发现正式 `ShelfManager`、生命周期/展示状态、20 窗口限制、快捷键入口及相应原生测试 |

构建、测试与静态分析通过只能证明现有代码可编译且受管临时文件测试通过，不能证明应用启动链路或窗口能力可用。

## 2. 待处理问题

| 编号 | 级别 | 问题 | 影响 | 状态 |
|---|---|---|---|---|
| REV-S0-001 | **P0** | 无 storyboard/nib 的工程未显式创建、强持有并设置 `AppDelegate`；运行时 `NSApp.delegate` 为 `nil` | `applicationDidFinishLaunching` 不执行，状态栏和浮窗均不会创建；阻断 M-01～M-06 | **待修复** |
| REV-S0-002 | **P1** | `ShelfPanelController` 对 persistent/transient 均无条件使用 `.nonactivatingPanel` | 持久内容架无法可靠成为 key window，与 S0-05 主动可交互要求冲突 | **待修复** |
| REV-S0-003 | **P1** | 性能采样只统计 `show()` 同步调用前后耗时 | 不能代表首帧已显示或窗口已可接收拖放，现有 P95 结果不具备验收效力 | **待修复** |
| REV-S0-004 | **P1** | 原生测试仅覆盖 `ManagedTemporaryFileStore` | 启动代理、窗口类型、多窗口生命周期和性能标记回归无法被自动发现 | **待补测试** |
| REV-S0-005 | **范围/状态** | 阶段 1 交付物尚未实现 | 不具备正式领域模型、生命周期、20 窗口上限、快捷键和空/收起/展开态；不能宣称阶段 1 完成 | **未开始** |
| REV-S0-006 | **P2** | 阶段 0 风险、验证和运行说明曾把未执行的窗口能力描述为已通过或启动即显示 | 进度与验收结论失真 | **本次已修正文档** |

## 3. 修复与关闭条件

### REV-S0-001 · P0 启动入口

- 显式创建并强持有 `AppDelegate`，设置到 `NSApplication.shared.delegate`；或采用能够正确安装 delegate 的等价入口。
- 启动后确认 `applicationDidFinishLaunching` 执行，状态栏可见，至少一个 persistent shelf 自动显示。
- 增加启动冒烟测试或等价自动化检查，至少能发现“进程存活但 delegate/window 均为空”。

### REV-S0-002 · P1 窗口类型

- persistent panel 不包含 `.nonactivatingPanel`，可以激活并成为 key window。
- transient panel 保留 `.nonactivatingPanel`，显示时不抢走拖拽源焦点。
- 完成 M-01、M-02，并记录浅色/深色和跨应用焦点结果。

### REV-S0-003 · P1 性能测量

- 主动窗口在实际首帧可见的事件点结束计时。
- 临时窗口在完成拖放注册并实际可接收拖放的事件点结束计时。
- 更新 D-15 和 M-06 的测量实现说明，采集足量样本后再计算 P95。

### REV-S0-004 · P1 测试缺口

- 覆盖 AppDelegate 启动链路、persistent/transient style mask、多窗口独立关闭。
- 阶段 1 开始后补充生命周期、迟到事件和第 21 个窗口拒绝的测试。

### REV-S0-005 · 阶段 1

- 仅在阶段 0 的 S0-01～S0-10 全部通过后启动。
- 按 [stage-1-shelf-domain-and-window.md](./stage-1-shelf-domain-and-window.md) 的 S1-01～S1-10 实施和验收。

## 4. 建议处理顺序

1. 修复 REV-S0-001，恢复可观察的应用启动链路。
2. 修复 REV-S0-002，并完成 M-01～M-05 手工回归。
3. 修复 REV-S0-003，重新采集 M-06 性能样本。
4. 补齐 REV-S0-004 的自动化保护。
5. 更新阶段 0 验证结果；S0-01～S0-10 全部通过后再进入阶段 1。
