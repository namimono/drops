# Drops macOS 原生化 · 开发进度

> 更新日期：2026-07-14  
> 对应方案：[README.md](./README.md)  
> 产品依据：[Drops-PRD.md](../Drops-PRD.md)  
> 阶段 0 实施：[stage-0-requirements-and-validation.md](./stage-0-requirements-and-validation.md)  
> 阶段 1 实施：[stage-1-shelf-domain-and-window.md](./stage-1-shelf-domain-and-window.md)  
> 范围清单：[stage-0-scope.md](./stage-0-scope.md)  
> 决策记录：[stage-0-decisions.md](./stage-0-decisions.md)  
> 风险结论：[stage-0-risks.md](./stage-0-risks.md)  
> 验证记录：[stage-0-validation.md](./stage-0-validation.md)  
> 审查问题：[stage-0-review-issues.md](./stage-0-review-issues.md)  
> 基线分支：当前工作区（原生工程位于 `macos-native/`）  
> 平台 / 范围：仅 macOS 13.0+；阶段 1 内容架领域与窗口骨架

---

## 1. 总体进度

| 阶段 | 方案内容 | 状态 | 说明 |
|---|---|---|---|
| 阶段 0 | 需求冻结与技术验证 | **已完成** | S0-01～S0-10 通过；可进入阶段 1 |
| 阶段 1 | 内容架领域与窗口骨架 | **代码已实现，待验证** | 领域/多窗/入口已落地；自动化 35/35；手工 S1-01/07/08/10 待做 |
| 阶段 2 | 拖放与剪贴板主链路 | **未开始** | — |
| 阶段 3 | 原生交互完善 | **未开始** | — |
| 阶段 4 | 图片与视频压缩 | **未开始** | — |
| 阶段 5 | 发布准备 | **未开始** | — |

**综合判断：阶段 1 主链路代码与生命周期自动化已齐备（35/35），尚未完成快捷键/菜单近鼠标创建、圆角截图、多屏边缘与 20 窗稳定性的手工验收；通过后即可退出阶段 1。**

## 2. 已实现能力

- 内容架领域：`Shelf` / 生命周期 / 展示态 / 选择集合 / 模拟内容项。
- `ShelfLifecycleStore`：主动持久、摇动临时、接收晋升、未接收关闭、上限 20、关闭后忽略迟到事件。
- `ShelfManager` + `ShelfWindowController`：多窗独立创建/关闭，空态/收起/展开骨架与尺寸切换。
- 菜单栏 **New Shelf** 与默认全局快捷键 **⌘⌥Space** 创建持久内容架；达上限时 `NSSound.beep()`。
- 菜单提供临时架 Demo（模拟拖拽会话），可用 **Simulate Drop** 验证晋升。
- Stage 0 窗口焦点契约已迁入正式 `ShelfWindowController`；Prototype 已从 Target 排除。

## 3. 已落地的架构改动

| 模块 | 路径 | 职责 |
|---|---|---|
| 领域模型 | `macos-native/Drops/Domain/ShelfModels.swift` | 打开来源、生命周期、展示、内容项 |
| 生命周期库 | `macos-native/Drops/Domain/ShelfLifecycleStore.swift` | 纯领域、可单测的创建/晋升/关闭规则 |
| 管理器 | `macos-native/Drops/Application/ShelfManager.swift` | 领域 + 窗口集合、迟到事件门禁 |
| 窗口 | `macos-native/Drops/ShelfUI/ShelfWindowController.swift` | 无边框浮窗、焦点、圆角、尺寸 |
| 内容骨架 | `macos-native/Drops/ShelfUI/ShelfContentViewController.swift` | 空/收起/展开占位 UI |
| 几何 | `macos-native/Drops/ShelfUI/ShelfWindowGeometry.swift` | 近鼠标定位与可见区夹紧 |
| 应用宿主 | `macos-native/Drops/Application/ApplicationController.swift` | 启动、菜单与快捷键接线 |
| 菜单栏 | `macos-native/Drops/Application/MenuBarController.swift` | New Shelf / Demo / Close All |
| 快捷键 | `macos-native/Drops/Input/GlobalHotkeyManager.swift` | Carbon ⌘⌥Space |

## 4. 已知偏差 / 限制

1. **App Sandbox 关闭**：沿用阶段 0；阶段 5 再启用。
2. **真实拖放未接入**：临时架晋升/关闭靠模拟事件；真实 Finder 拖入属阶段 2。
3. **String Catalog 未建**：骨架文案仍为英文硬编码；阶段 3 再统一本地化。
4. **Prototype 保留未编译**：`Drops/Prototype/` 排除出 Target，仅作历史参考。

## 5. 验证与修复记录

| 类型 / 级别 | 场景或问题 | 状态 | 证据 / 修复 |
|---|---|---|---|
| 构建 / 单测 | Debug 测试 35/35 | **通过** | `xcodebuild test -scheme Drops -destination 'platform=macOS'`（2026-07-14） |
| 自动化 S1-02/03/04/05/06/09 | 多窗、上限、持久空架、临时晋升/关闭、展示切换、迟到事件 | **通过** | `ShelfLifecycleStoreTests` + `ShelfManagerWindowTests` |
| 手工 S1-01 | 快捷键与菜单栏近鼠标创建 | **待验证** | 启动 App 后试 ⌘⌥Space / New Shelf |
| 手工 S1-07 | 圆角/阴影浅色深色截图 | **待验证** | — |
| 手工 S1-08 | 多屏与边缘定位 | **待验证** | 几何单测已覆盖夹紧公式 |
| 手工 S1-10 | 20 空架创建/展开/收起/关闭与 CPU | **待验证** | 管理器可创建满 20；需目视与活动监视器 |

## 6. 未完成 / 待办

### P0 · 正确性或稳定性

- [ ] 完成阶段 1 手工验收：S1-01、S1-07、S1-08、S1-10，并回写验证记录。
- [ ] 阶段 1 退出评审通过后，再启动阶段 2 真实拖放与剪贴板。

### P1 · 治理、性能或维护性

- [ ] 规划阶段 5 的 Sandbox / Developer ID / 公证接入点（不阻塞阶段 1）。
- [ ] 将骨架硬编码文案迁入 String Catalog（阶段 3）。

## 7. 验收对照

| 验收项 | 状态 |
|---|---|
| S1-01 快捷键/菜单近鼠标创建持久架 | **代码已实现，待手工验证** |
| S1-02 多窗独立标识/状态/关闭 | **已验证（自动化）** |
| S1-03 第 20 允许、第 21 拒绝并提示音 | **已验证（自动化 + beep 代码）** |
| S1-04 主动空架不因失焦自动关闭 | **已验证（领域：无自动关闭路径）** |
| S1-05 临时架等待/晋升/未接收关闭 | **已验证（模拟事件自动化）** |
| S1-06 空/收起/展开稳定切换 | **已验证（快速切换自动化）** |
| S1-07 圆角阴影无灰底泄漏 | **代码已迁入正式窗，待截图** |
| S1-08 多屏/边缘保持在可见区 | **夹紧逻辑已测，待多屏手工** |
| S1-09 关闭后迟到事件忽略 | **已验证（自动化）** |
| S1-10 20 空架稳定性 | **代码支持，待手工性能观察** |

## 8. 建议下一迭代顺序

1. 手工跑通 S1-01 / S1-07 / S1-08 / S1-10 并记入验证文档。
2. 阶段 1 退出后实施 [stage-2-drag-drop-and-pasteboard.md](./stage-2-drag-drop-and-pasteboard.md)。
3. 将 `ManagedTemporaryFileStore` 正式接到剪贴板物化。

## 9. 变更文件速查

**阶段 1 首轮实现**

- `macos-native/Drops/Domain/ShelfModels.swift`
- `macos-native/Drops/Domain/ShelfLifecycleStore.swift`
- `macos-native/Drops/Application/ShelfManager.swift`
- `macos-native/Drops/Application/ApplicationController.swift`
- `macos-native/Drops/Application/MenuBarController.swift`
- `macos-native/Drops/Application/AppDelegate.swift`
- `macos-native/Drops/Input/GlobalHotkeyManager.swift`
- `macos-native/Drops/ShelfUI/ShelfWindowController.swift`
- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`
- `macos-native/Drops/ShelfUI/ShelfWindowGeometry.swift`
- `macos-native/DropsTests/ShelfLifecycleStoreTests.swift`
- `macos-native/DropsTests/ShelfManagerWindowTests.swift`
- `macos-native/DropsTests/Stage0LaunchAndWindowTests.swift`
- `macos-native/project.yml`（排除 `Prototype/**`）
- 删除：`macos-native/Drops/Application/Stage0DemoController.swift`
