# Drops macOS 原生化 · 开发进度

> 更新日期：2026-07-14  
> 对应方案：[README.md](./README.md)  
> 产品依据：[Drops-PRD.md](../Drops-PRD.md)  
> 阶段 0 实施：[stage-0-requirements-and-validation.md](./stage-0-requirements-and-validation.md)  
> 阶段 1 实施：[stage-1-shelf-domain-and-window.md](./stage-1-shelf-domain-and-window.md)  
> 阶段 2 实施：[stage-2-drag-drop-and-pasteboard.md](./stage-2-drag-drop-and-pasteboard.md)  
> 阶段 0 审查：[stage-0-review-issues.md](./stage-0-review-issues.md)<br>
> 阶段 1 审查：[stage-1-review-issues.md](./stage-1-review-issues.md)<br>
> 阶段 2 审查：[stage-2-review-issues.md](./stage-2-review-issues.md)<br>
> 基线分支：当前工作区（原生工程位于 `macos-native/`）  
> 平台 / 范围：仅 macOS 13.0+；阶段 2 拖放与剪贴板主链路

---

## 1. 总体进度

| 阶段 | 方案内容 | 状态 | 说明 |
|---|---|---|---|
| 阶段 0 | 需求冻结与技术验证 | **已完成** | S0-01～S0-10 通过；可进入阶段 1 |
| 阶段 1 | 内容架领域与窗口骨架 | **已完成** | REV-S1-001～005 已关闭；自动化 42/42；手工 S1-01/07/08/10 通过 |
| 阶段 2 | 拖放与剪贴板主链路 | **已完成** | REV-S2-001～009 已关闭；自动化 69/69；手工 S2-01/05/06/13 通过 |
| 阶段 3 | 原生交互完善 | **未开始** | — |
| 阶段 4 | 图片与视频压缩 | **未开始** | — |
| 阶段 5 | 发布准备 | **未开始** | — |

**综合判断：阶段 2 已完成。审查缺陷已关闭，自动化 69/69，手工验收 S2-01/05/06/13 通过；S2-01～S2-13 全部满足退出条件，可进入阶段 3。**

## 2. 已实现能力

- 内容架领域：`Shelf` / 生命周期 / 展示态 / 选择集合 / 真实内容项（文件、文件夹、链接、受管临时文件）。
- `ShelfLifecycleStore`：主动持久、摇动临时、接收晋升、未接收关闭、上限 20、关闭后忽略迟到事件；拖拽会话同 ID 幂等、异 ID 抢占并回收 orphan 临时架；晋升按会话 ID 门禁。
- `ShelfManager` + `ShelfWindowController`：多窗独立创建/关闭；真实拖入/粘贴接入；拖出 copy/move/cancel；临时文件引用在移除与关窗时释放；退出时协调引用清理。
- `PasteboardMaterializer` + `ManagedTemporaryFileStore`：文件引用直入；跨内容架保留受管 ID；纯文本/图片/RTF/HTML/PDF 等落盘；批次失败回滚；同批重名追加序号。
- 去重与排序：按路径/URL `identityKey`；新内容置顶；重复加入前移不造副本；新内容加入选择集。
- 选择：单击 / ⌘单击 / Shift 范围（锚点跨刷新稳定）；单项/多选/收起态整堆拖出。
- `GlobalInputCoordinator` + `ShakeDetector`：外部拖拽会话、摇动/Shift 唤起临时架；`dragReady` 里程碑恢复。
- `SettingsStore` + `RetentionScheduler`：保留天数 1…120；菜单入口与非法输入提示；启动与每日清理；手动清理二次确认。
- 菜单栏 **New Shelf**、**Retention Days…**、临时架 Demo、**Clean Temporary Files Now…**；默认全局快捷键 **⌘⌥Space**。

## 3. 已落地的架构改动

| 模块 | 路径 | 职责 |
|---|---|---|
| 领域模型 | `macos-native/Drops/Domain/ShelfModels.swift` | 打开来源、生命周期、展示、内容项、选择与拖出规则 |
| 内容草稿 | `macos-native/Drops/Domain/ShelfItemModels.swift` | `ShelfItemKind` / `ShelfItemDraft` |
| 生命周期库 | `macos-native/Drops/Domain/ShelfLifecycleStore.swift` | 纯领域创建/晋升/关闭/会话规则 |
| 管理器 | `macos-native/Drops/Application/ShelfManager.swift` | 领域 + 窗口 + 剪贴板接入 + 引用提交/释放 |
| 窗口 | `macos-native/Drops/ShelfUI/ShelfWindowController.swift` | 无边框浮窗、焦点、圆角、尺寸、`dragReady` |
| 内容视图 | `macos-native/Drops/ShelfUI/ShelfContentViewController.swift` | 拖入高亮、列表、选择锚点、拖出受管类型、粘贴 |
| 剪贴板 | `macos-native/Drops/Services/PasteboardMaterializer.swift` | Pasteboard → `ShelfItemDraft`（事务批次） |
| 临时文件 | `macos-native/Drops/Services/ManagedTemporaryFileStore.swift` | 受管落盘、引用、启动清陈旧引用、安全删除 |
| 保留策略 | `macos-native/Drops/Services/SettingsStore.swift` / `RetentionScheduler.swift` | 设置与清理调度 |
| 输入 | `macos-native/Drops/Input/GlobalInputCoordinator.swift` / `ShakeDetector.swift` | 外部拖拽与摇动 |
| 应用宿主 | `macos-native/Drops/Application/ApplicationController.swift` | 启动、菜单、快捷键、确认清理、退出接线 |

## 4. 已知偏差 / 限制

1. **App Sandbox 关闭**：沿用阶段 0；阶段 5 再启用。
2. **String Catalog 未建**：骨架与菜单文案仍为英文硬编码；阶段 3 再统一本地化。
3. **Prototype 保留未编译**：`Drops/Prototype/` 排除出 Target，仅作历史参考。
4. **收起态宽度**：collapsed 与 empty 同宽 280；Stage 3 UI 可再收窄。
5. **完整网格/列表视觉、Quick Look、右键菜单、文本合并**：属阶段 3，本阶段仅列表骨架 + 拖放闭环。
6. **保留天数 UI**：阶段 2 提供菜单对话框最小入口；完整设置页属阶段 3。

## 5. 验证与修复记录

| 类型 / 级别 | 场景或问题 | 状态 | 证据 / 修复 |
|---|---|---|---|
| 构建 / 单测 | Debug 测试 69/69 | **通过** | 修复后 `xcodebuild test -scheme Drops -destination 'platform=macOS'`（2026-07-14） |
| 构建 / 静态分析 | Release 构建、Xcode Analyze | **修复前通过；修复后待复跑** | 独立 DerivedData + `CODE_SIGNING_ALLOWED=NO`（2026-07-14 review） |
| 代码审查 / P0 | 跨内容架受管引用丢失 | **已修复** | 私有 pasteboard 类型 + `addReference`；`testCrossShelfManagedDragAddsReferenceAndProtectsCleanup` |
| 代码审查 / P1-P2 | REV-S2-002～009 | **已修复** | 见 [阶段 2 审查清单](./stage-2-review-issues.md) |
| 自动化 S2-02 | 去重前移与新内容置顶 | **通过** | `ShelfItemDomainTests` |
| 自动化 S2-03 | 文本/图片/链接/RTF/PDF 物化 | **通过** | `PasteboardMaterializerTests`（显式 RTF 优先于合成 plain text） |
| 自动化 S2-04 | 选择与拖出载荷 / Shift 锚点 | **通过** | `ShelfItemDomainTests` + `testSelectionAnchorSurvivesApplyRefresh` |
| 自动化 S2-07 | 接收晋升 / 未接收关闭 | **通过** | 既有生命周期测试 + `ShelfManagerContentTests` |
| 自动化 S2-08/09/10/11/12 | 保留天数、引用保护、清理确认、路径边界 | **通过** | Settings / Store / Manager 回归（含跨架引用与重启清引用） |
| 自动化 dragReady | 临时窗注册拖放类型 | **通过** | `Stage0LaunchAndWindowTests` |
| 手工 S2-01 | Finder/第三方拖入识别 | **通过** | 人工验收（2026-07-14） |
| 手工 S2-05 | 复制保留 / 移动移除 / 取消保持 | **通过** | 人工验收（2026-07-14） |
| 手工 S2-06 | 临时架会话、焦点、可接收时限 | **通过** | 人工验收（2026-07-14） |
| 手工 S2-13 | 快速拖入拖出取消关窗压力 | **通过** | 人工验收（2026-07-14） |

## 6. 未完成 / 待办

### P0 · 正确性或稳定性

- [x] 实施阶段 2 真实拖放与剪贴板（代码 + 自动化）。
- [x] 修复 REV-S2-001～009 并补充针对性回归。
- [x] 完成阶段 2 手工验收：S2-01、S2-05、S2-06、S2-13。
- [x] 阶段 2 退出条件：S2-01～S2-13 全部通过。

### P1 · 治理、性能或维护性

- [ ] 规划阶段 5 的 Sandbox / Developer ID / 公证接入点（不阻塞阶段 3）。
- [ ] 将硬编码文案迁入 String Catalog（阶段 3）。
- [ ] 完整设置页承载保留天数编辑（当前为菜单对话框最小入口）。

## 7. 验收对照

| 验收项 | 状态 |
|---|---|
| S2-01 Finder/第三方拖入识别 | **已验证（手工）** |
| S2-02 新内容置顶与去重前移 | **已验证（自动化）** |
| S2-03 粘贴文本/图片/链接/RTF/PDF | **已验证（自动化；显式 RTF 保留）** |
| S2-04 单项/多选/区间/收起整堆拖出 | **已验证（领域 + UI 锚点自动化）** |
| S2-05 复制保留 / 移动移除 / 取消保持 | **已验证（自动化 + 手工）** |
| S2-06 单会话临时架 + 不抢焦点 + 及时可接收 | **已验证（自动化 + 手工）** |
| S2-07 接收晋升 / 未接收关闭 | **已验证（自动化）** |
| S2-08 保留天数 1…120 非法不覆盖 | **已验证（服务 + 菜单入口提示自动化）** |
| S2-09 改天数后重算到期 | **已验证（自动化）** |
| S2-10 引用保护延迟清理 | **已验证（跨架引用 + 重启清陈旧引用自动化）** |
| S2-11 手动清理跳过引用并计数 | **已验证（服务 + 二次确认门禁自动化）** |
| S2-12 不删原始/外链/逃逸路径 | **已验证（自动化；存储不可用时禁用物化）** |
| S2-13 快速拖入拖出取消关窗压力 | **已验证（失败回滚自动化 + 压力手工）** |

## 8. 建议下一迭代顺序

1. 进入 [stage-3-native-interactions.md](./stage-3-native-interactions.md)：完整原生交互、网格/列表视觉、Quick Look、右键菜单等。
2. 阶段 3 内将硬编码文案迁入 String Catalog，并视需要扩展完整设置页。

## 9. 变更文件速查

**阶段 2 审查修复（本轮）**

- `macos-native/Drops/Services/PasteboardMaterializer.swift`
- `macos-native/Drops/Services/ManagedTemporaryFileStore.swift`
- `macos-native/Drops/Application/ShelfManager.swift`
- `macos-native/Drops/Application/ApplicationController.swift`
- `macos-native/Drops/Application/MenuBarController.swift`
- `macos-native/Drops/Application/AppDelegate.swift`
- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`
- `macos-native/DropsTests/PasteboardMaterializerTests.swift`
- `macos-native/DropsTests/ShelfManagerContentTests.swift`
- `docs/macos-native/stage-2-review-issues.md`
- `docs/macos-native/development-progress.md`
