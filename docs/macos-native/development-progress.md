# Drops macOS 原生化 · 开发进度

> 更新日期：2026-07-14  
> 对应方案：[README.md](./README.md)  
> 产品依据：[Drops-PRD.md](../Drops-PRD.md)  
> 阶段 0 实施：[stage-0-requirements-and-validation.md](./stage-0-requirements-and-validation.md)  
> 范围清单：[stage-0-scope.md](./stage-0-scope.md)  
> 决策记录：[stage-0-decisions.md](./stage-0-decisions.md)  
> 风险结论：[stage-0-risks.md](./stage-0-risks.md)  
> 验证记录：[stage-0-validation.md](./stage-0-validation.md)  
> 审查问题：[stage-0-review-issues.md](./stage-0-review-issues.md)  
> 基线分支：当前工作区（原生工程位于 `macos-native/`）  
> 平台 / 范围：仅 macOS 13.0+；阶段 0 需求冻结与关键能力验证

---

## 1. 总体进度

| 阶段 | 方案内容 | 状态 | 说明 |
|---|---|---|---|
| 阶段 0 | 需求冻结与技术验证 | **部分完成** | 构建与临时文件单测通过；P0 启动缺陷导致窗口、拖放和性能验收不可执行 |
| 阶段 1 | 内容架领域与窗口骨架 | **未开始** | 等待阶段 0 P0/P1 问题修复及退出评审 |
| 阶段 2 | 拖放与剪贴板主链路 | **未开始** | — |
| 阶段 3 | 原生交互完善 | **未开始** | — |
| 阶段 4 | 图片与视频压缩 | **未开始** | — |
| 阶段 5 | 发布准备 | **未开始** | — |

**综合判断：阶段 0 的工程骨架、范围冻结、受管临时文件安全删除与构建/单测证据已齐备；但运行时 `NSApplication.shared.delegate` 为 `nil`，启动逻辑未执行，状态栏和浮窗均未创建。该 P0 缺陷以及 persistent panel 类型、性能测量点问题修复前，S0-04～S0-07、S0-09、S0-10 不能通过，也不能进入阶段 1。**

## 2. 已实现能力

- PRD 第 8 章边界已写成可执行范围清单与非目标表（含 Windows / 归档 / 裁剪 / 辅助工具排除）。
- 独立原生工程 `macos-native/Drops.xcodeproj` 可 Debug / Release 构建，测试 Target 可运行，二进制无 Flutter 链接。
- Stage 0 已包含菜单栏、主动/临时/多窗口内容架的原型代码，但当前启动入口未安装 `AppDelegate`，运行时不可达。
- `ShelfPanelController` 已包含无边框 `NSPanel`、VisualEffect 圆角和拖放代码；persistent/transient 当前均带 `.nonactivatingPanel`，焦点策略待修复。
- `ShelfDropView` 已包含 Finder 文件拖入和 copy/move/cancel 日志代码，待启动缺陷修复后完成跨应用验证。
- `ManagedTemporaryFileStore` 使用 Application Support 受管目录；拒绝根外路径与符号链接逃逸；覆盖保留期、引用保护、自动/手动清理规则的单元测试 **8/8 通过**。
- 性能预算保留为主动首帧 P95 < 300 ms、临时可拖放 P95 < 200 ms；当前 `show()` 前后采样不能代表首帧或 drag-ready，测量实现待修复。

## 3. 已落地的架构改动

| 模块 | 路径 | 职责 |
|---|---|---|
| XcodeGen 工程定义 | `macos-native/project.yml` | Bundle ID、部署版本、Debug/Release、测试 Host |
| 应用入口 | `macos-native/Drops/Application/` | 菜单栏 Demo、性能采样 |
| 窗口/拖放原型 | `macos-native/Drops/Prototype/` | 无边框面板、拖入拖出 |
| 临时文件领域 | `macos-native/Drops/Domain/TemporaryFileModels.swift` | 记录、保留策略、错误类型 |
| 受管临时存储 | `macos-native/Drops/Services/ManagedTemporaryFileStore.swift` | 创建、清理、路径安全校验 |
| 单元测试 | `macos-native/DropsTests/` | 删除边界与保留规则 |

## 4. 已知偏差 / 限制

1. **App Sandbox 关闭**：阶段 0 为降低拖放验证噪声关闭 Sandbox；发布前（阶段 5）需启用并补齐权限/书签方案。
2. **启动链路阻断**：无 storyboard/nib 时未显式设置并强持有 `AppDelegate`；进程存活但 `NSApp.delegate == nil`、`NSApp.windows.count == 0`。
3. **窗口类型偏差**：persistent panel 也包含 `.nonactivatingPanel`，主动窗焦点能力与设计不符。
4. **手工交互未闭环**：M-01～M-06 受启动缺陷阻断，尚无窗口、跨应用焦点与拖放演示证据。
5. **性能测量无效**：当前采样只覆盖 `show()` 同步耗时，需改到真实首帧/drag-ready 事件点后重新采样。
6. **测试覆盖不足**：原生 8 个测试只覆盖受管临时文件，没有启动和窗口回归保护。
7. **非日用产品**：Stage 0 原型无完整 UI、剪贴板物化、压缩或设置页。

## 5. 验证与修复记录

| 类型 / 级别 | 场景或问题 | 状态 | 证据 / 修复 |
|---|---|---|---|
| 构建 | Debug `xcodebuild -scheme Drops -configuration Debug` | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| 构建 | Release 同方案 | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| 单测 | `ManagedTemporaryFileStoreTests` 8 cases | **通过** | `TEST SUCCEEDED`（2026-07-14） |
| 依赖 | 产物 Flutter 链接检查 | **通过** | `otool -L` 无 Flutter |
| MainActor | `AppDelegate` 属性初始化隔离错误 | **已修复** | 改为 `applicationDidFinishLaunching` 内创建 |
| 独占访问 | `updateRetentionDays` overlapping access | **已修复** | 本地 `var record` 再写回 |
| 代码审查 / P0 | AppDelegate 未安装，应用无窗口 | **待修复** | 运行时 `NSApp.delegate == nil`、`NSApp.windows.count == 0`；REV-S0-001 |
| 代码审查 / P1 | persistent panel 错用 `.nonactivatingPanel` | **待修复** | `ShelfPanelController` style mask 无条件包含该标志；REV-S0-002 |
| 代码审查 / P1 | 性能测量点不代表首帧/drag-ready | **待修复** | 仅统计 `show()` 前后同步耗时；REV-S0-003 |
| 代码审查 / P1 | 启动和窗口自动化覆盖缺失 | **待补测试** | 现有 8 个原生测试均为临时文件领域测试；REV-S0-004 |
| 手工 | 浮窗/焦点/拖放/多窗/性能 | **被 P0 阻断** | [stage-0-validation.md](./stage-0-validation.md) M-01–M-06 |

## 6. 未完成 / 待办

### P0 · 正确性或稳定性

- [ ] 修复 REV-S0-001：显式安装并强持有 `AppDelegate`，确认启动后状态栏和 persistent shelf 可见。
- [ ] 修复 REV-S0-002：仅 transient panel 使用 `.nonactivatingPanel`，persistent panel 可激活并成为 key window。
- [ ] 完成 M-01～M-05 手工演示并写入验证记录（浅色/深色、不抢焦点、Finder 与至少一第三方拖出、多窗关闭独立）。
- [ ] 阶段 0 退出评审确认后，再启动阶段 1 领域模型与正式 `ShelfWindowController`。

### P1 · 治理、性能或维护性

- [ ] 修复 REV-S0-003：使用真实首帧可见与 drag-ready 事件点采样，再执行 M-06。
- [ ] 补充 REV-S0-004：AppDelegate 启动、窗口类型和多窗口生命周期自动化检查。
- [ ] 规划阶段 5 的 Sandbox / Developer ID / 公证接入点（不阻塞阶段 1）。

## 7. 验收对照

| 验收项 | 状态 |
|---|---|
| S0-01 范围冻结（含非目标） | **已实现并文档化** |
| S0-02 最低系统 / Bundle ID / Debug-Release / 签名策略 | **已实现并文档化**（签名正式发布留阶段 5） |
| S0-03 干净 Debug/Release + 测试 + 无 Flutter | **已验证**（本机 xcodebuild / otool） |
| S0-04 无边框内容架无灰底泄漏 | **被 REV-S0-001 阻断**；当前无窗口 |
| S0-05 主动可交互 / 临时不抢焦点 | **被 REV-S0-001 阻断，且 REV-S0-002 待修复** |
| S0-06 Finder 拖入拖出 copy/move/cancel | **被 REV-S0-001 阻断**；仅有未验证原型代码 |
| S0-07 多窗口独立关闭 | **被 REV-S0-001 阻断**；仅有未验证原型代码 |
| S0-08 受管目录清理与符号链接逃逸防护 | **已验证**（单测 8/8） |
| S0-09 性能基准口径 | **预算已确认，测量实现无效**；REV-S0-003 待修复 |
| S0-10 关键风险均有结论 | **未通过**；存在 P0/P1 未解决问题 |

## 8. 建议下一迭代顺序

1. 按 [stage-0-review-issues.md](./stage-0-review-issues.md) 修复 REV-S0-001 和 REV-S0-002，恢复可观察、可交互的窗口链路。
2. 完成 M-01～M-05 手工演示；修复性能标记后完成 M-06。
3. 补齐启动和窗口测试，更新风险及验收状态。
4. 阶段 0 退出评审通过后，实施 [stage-1-shelf-domain-and-window.md](./stage-1-shelf-domain-and-window.md)。
5. 将 `ManagedTemporaryFileStore` 保留为阶段 2 正式接入点，避免重复实现删除边界。

## 9. 变更文件速查

**阶段 0 实施产物（当前工作区）**

- `macos-native/`（工程、源码、测试、README、project.yml）
- `docs/macos-native/stage-0-scope.md`
- `docs/macos-native/stage-0-decisions.md`
- `docs/macos-native/stage-0-risks.md`
- `docs/macos-native/stage-0-validation.md`
- `docs/macos-native/development-progress.md`

**修改**

- `docs/macos-native/stage-0-requirements-and-validation.md`（状态更新）
- `docs/macos-native/README.md`（进度与阶段 0 产物链接）

**2026-07-14 审查文档修订**

- 新增 `docs/macos-native/stage-0-review-issues.md`。
- 修正 `development-progress.md`、阶段 0 需求/决策/风险/验证文档及 `macos-native/README.md` 中过早的通过结论。
- 本次仅修改文档，未修复 Swift 代码；所有 REV-S0-001～REV-S0-005 状态以问题清单为准。
