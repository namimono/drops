# Drops macOS 原生化 · 开发进度

> 更新日期：2026-07-16
> 对应方案：[README.md](./README.md)  
> 产品依据：[Drops-PRD.md](../Drops-PRD.md)  
> 阶段 0 实施：[stage-0-requirements-and-validation.md](./stage-0-requirements-and-validation.md)  
> 阶段 1 实施：[stage-1-shelf-domain-and-window.md](./stage-1-shelf-domain-and-window.md)  
> 阶段 2 实施：[stage-2-drag-drop-and-pasteboard.md](./stage-2-drag-drop-and-pasteboard.md)  
> 阶段 3 实施：[stage-3-native-interactions.md](./stage-3-native-interactions.md)  
> 阶段 3 手工验收：[stage-3-manual-acceptance.md](./stage-3-manual-acceptance.md)  
> 阶段 4 实施：[stage-4-product-polish.md](./stage-4-product-polish.md)  
> 阶段 5 实施：[stage-5-release-readiness.md](./stage-5-release-readiness.md)  
> 阶段 0 审查：[stage-0-review-issues.md](./stage-0-review-issues.md)<br>
> 阶段 1 审查：[stage-1-review-issues.md](./stage-1-review-issues.md)<br>
> 阶段 2 审查：[stage-2-review-issues.md](./stage-2-review-issues.md)<br>
> 阶段 3 审查：[stage-3-review-issues.md](./stage-3-review-issues.md)<br>
> 基线分支：当前工作区（原生工程位于 `macos-native/`）  
> 平台 / 范围：仅 macOS 13.0+；阶段 3 已完成；**当前阶段 4 产品打磨**

---

## 1. 总体进度

| 阶段 | 方案内容 | 状态 | 说明 |
|---|---|---|---|
| 阶段 0 | 需求冻结与技术验证 | **已完成** | S0-01～S0-10 通过 |
| 阶段 1 | 内容架领域与窗口骨架 | **已完成** | REV-S1 已关闭 |
| 阶段 2 | 拖放与剪贴板主链路 | **已完成** | REV-S2 已关闭 |
| 阶段 3 | 原生交互完善 | **已完成** | REV-S3 已关闭；S3-01～S3-14 全部通过（自动化 + 手工验收）；退出条件已满足 |
| 阶段 4 | 产品打磨 | **进行中** | 首批 P0（图标/命名/唤起动画）已落地；其余见 [stage-4 需求池](./stage-4-product-polish.md) |
| 阶段 5 | 发布准备 | **未开始** | 依赖阶段 4 封版；见 [stage-5 §9](./stage-5-release-readiness.md#9-发布接入点规划阶段-3-预埋) |

**综合判断：阶段 3 已退出。当前处于阶段 4 产品打磨；图标/命名/唤起动画三项 P0 代码已实现，自动化通过，Dock 隐藏与动画仍建议手工确认。**

## 2. 已实现能力

### 阶段 0–2（基线）

- 内容架领域、生命周期、拖入/拖出、剪贴板物化、摇动唤起、保留清理等。

### 阶段 3

- 网格 / 列表、图标与缩略图、打开 / 定位 / Quick Look、右键、文本合并、Settings / About / Logs。
- **收起态重叠堆**：最多露出 3 个图标 + 数量文案；拖动整堆；双击展开。
- **本地化**：`Localizable.xcstrings`（en + zh-Hans）；设置语言覆盖立即生效；不支持系统语言回退英文。
- **无障碍**：内容架 / 列表 / 网格 / 收起堆 / 按钮 / 菜单栏 VoiceOver 标签；临时架不抢焦点。
- **深浅色**：HUD `NSVisualEffectView` 跟随系统外观。
- **发布接入点预埋**：Sandbox / Developer ID / 公证接入点与切换顺序已写入阶段 5 文档。

### 阶段 4

- **菜单栏工具形态**：`LSUIElement` + `.accessory`，Dock 不显示图标；菜单栏使用自定义 `MenuBarIcon`。
- **产品图标**：`AppIcon` 资产（架上内容块隐喻）。
- **应用名**：英文 Shelf / 中文 内容架（Info.plist、InfoPlist.strings、UI 文案）。
- **唤起动画**：收集框 show 时淡入 + 轻微缩放（0.22s ease-out）；尊重「减少动态效果」。

## 3. 已落地的架构改动

| 模块 | 路径 | 职责 |
|---|---|---|
| 本地化 | `Resources/Localizable.xcstrings` + `Services/AppLocalization.swift` | Catalog + 运行时语言解析 / `L10n`；`app.name` |
| 应用身份 | `Resources/Info.plist` + `en|zh-Hans.lproj/InfoPlist.strings` | Shelf / 内容架显示名；`LSUIElement` |
| 图标 | `Resources/Assets.xcassets` | AppIcon + MenuBarIcon |
| 宿主 | `Application/ApplicationController.swift` | `.accessory` 激活策略 |
| 收起堆 | `ShelfUI/CollapsedStackView.swift` | 最多 3 图标重叠堆 |
| 内容 UI | `ShelfUI/ShelfContentViewController.swift` | 收起堆 / 展开网格列表 / 本地化 / a11y |
| 窗口 | `ShelfUI/ShelfWindowController.swift` | 唤起淡入缩放动画 |
| 设置 | `Application/SettingsWindowController.swift` | 语言切换驱动 `AppLocalization` |
| 打磨阶段 | `docs/macos-native/stage-4-product-polish.md` | 产品打磨需求池 |
| 发布规划 | `docs/macos-native/stage-5-release-readiness.md` §9 | Sandbox / 签名 / 公证接入点 |

## 4. 已知偏差 / 限制

1. **App Sandbox 仍关闭**：阶段 5 按文档启用并补 bookmark。
2. **部分系统对话框**：语言覆盖立即作用于 UI；极少数系统级对话框可能需重启后完全跟随（设置页已提示）。
3. **Prototype 未编译**：仅作历史参考。
4. **图标/动画手工观感**：自动化覆盖命名与窗口里程碑；Dock 隐藏与唤起动画质感待日常试用确认。

## 5. 验证与修复记录

| 类型 / 级别 | 场景或问题 | 状态 | 证据 / 修复 |
|---|---|---|---|
| 构建 / 单测 | Debug 测试 90/90 | **通过** | `xcodebuild test -scheme Drops -destination 'platform=macOS'` |
| 自动化 | en / zh-Hans 应用名 Shelf / 内容架 | **通过** | `AppLocalizationTests` |
| 自动化 | 收起堆显示 / 展开隐藏 | **通过** | `CollapsedStackViewTests` |
| 阶段 4 P0 | 隐藏 Dock、命名、唤起动画 | **代码已实现，待手工确认** | Info.plist + accessory；show 动画；见变更文件 |
| 手工反馈修复 | 详情框过大；单击选中框突然变大；Space 无法 Quick Look / 误触 Finder 预览 | **已验证** | 展开尺寸随数量增长；选区轻量同步；Space 转发 + `acceptsPreviewPanelControl` + 点击时激活 |
| 手工反馈修复 | 拖放文本合并无感知 | **已验证** | 停留/就绪用灰白与选中蓝提示 + 底部文案 + 触感 |
| 手工反馈修复 | 合并成功后拖影先回弹再消失；零尺寸拖影崩溃；就绪提示呼吸缩放 | **已验证** | 就绪即藏源项；松手直接 `replaceItems`；结果项轻脉冲 |
| 手工反馈修复 | 禁用架内重排后拖放合并失效 | **已验证** | 合并源用 `dragOutItemIDs`；相关单测通过 |
| 手工反馈修复 | 粘贴后旧首项仍被选中；框内拖放误触发“排序” | **已验证** | `insertItems` 仅选中新项；拒绝同源架内 drop |
| 手工反馈修复 | 详情右上角网格/列表切换图标难辨认；切换无动画 | **已验证** | 模式图标加大 + 选中浅灰底；内容区交叉淡入淡出 |
| 自动化 | 合并相关聚焦单测 | **通过** | `TextMergeServiceTests` + `ShelfItemDomainTests` + `ShelfStage3InteractionTests` |
| 自动化 | 展开尺寸随数量增长并封顶 | **通过** | `testExpandedSizeGrowsWithItemCountAndCapsAtMax` |
| 自动化 | 插入后选区仅为新项 | **通过** | `testInsertedItemsBecomeSoleSelection` |
| 审查 | REV-S3-001～005 | **已关闭** | 见 stage-3-review-issues.md |
| 手工 | S3-01～S3-14 | **已通过** | [stage-3-manual-acceptance.md](./stage-3-manual-acceptance.md)（2026-07-15） |
| 文档 | 插入阶段 4 产品打磨；原发布准备顺延为阶段 5 | **已完成** | stage-4-product-polish.md；stage-5-release-readiness.md |

## 6. 未完成 / 待办

### 阶段 3

无。S3-01～S3-14 与手工复验项均已关闭。

### 阶段 4（当前）

- [x] 产品图标 / 菜单栏图标 / 隐藏 Dock（p0）— 代码完成，待手工确认 Dock 与菜单栏观感。
- [x] 应用名统一 Shelf / 内容架（p0）— 自动化通过。
- [x] 收集框唤起动画（p0）— 代码完成，待手工确认动画质感。
- [ ] 文件观察（p0）
- [ ] 直接行动能力建设（p0）
- [ ] 设置页面优化（p1）
- [ ] 下拉菜单删除调试选项（p2）
- [ ] 需求收敛后封版，再进入阶段 5。

### 阶段 5（其后）

- [ ] 按 [stage-5-release-readiness.md](./stage-5-release-readiness.md) 启用 Sandbox → Developer ID → 公证。
- [ ] 发布级回归、性能与稳定性、迁移与构建收口。

## 7. 验收对照

| 验收项 | 状态 |
|---|---|
| S3-01～S3-14 | **已通过**（见阶段 3 手工清单） |
| 阶段 4：图标 / Dock 隐藏 | **代码已实现，待手工确认** |
| 阶段 4：应用名 Shelf / 内容架 | **已实现**（自动化断言） |
| 阶段 4：唤起动画 | **代码已实现，待手工确认** |
| 阶段 4 其余需求池 | **进行中** |

## 8. 建议下一迭代顺序

1. 手工确认：Dock 无图标、菜单栏图标、唤起动画与「减少动态效果」。
2. 继续 [stage-4-product-polish.md](./stage-4-product-polish.md) 剩余 P0（文件观察、直接行动）。
3. 需求收敛、产品封版后进入 [stage-5-release-readiness.md](./stage-5-release-readiness.md)。

## 9. 变更文件速查

**本轮（阶段 4 P0：图标 / 命名 / 唤起动画）**

- `macos-native/Drops/Resources/Info.plist`
- `macos-native/Drops/Resources/en.lproj/InfoPlist.strings`
- `macos-native/Drops/Resources/zh-Hans.lproj/InfoPlist.strings`
- `macos-native/Drops/Resources/Localizable.xcstrings`
- `macos-native/Drops/Resources/Assets.xcassets/`（AppIcon、MenuBarIcon）
- `macos-native/Drops/Application/ApplicationController.swift`
- `macos-native/Drops/Application/MenuBarController.swift`
- `macos-native/Drops/Application/AboutWindowController.swift`
- `macos-native/Drops/Application/ShelfManager.swift`
- `macos-native/Drops/ShelfUI/ShelfWindowController.swift`
- `macos-native/Drops/Services/AppLocalization.swift`
- `macos-native/DropsTests/AppLocalizationTests.swift`
- `macos-native/Drops.xcodeproj/project.pbxproj`
- `docs/macos-native/stage-4-product-polish.md`
- `docs/macos-native/development-progress.md`

**上轮（插入阶段 4 产品打磨，发布准备顺延为阶段 5）**

- `docs/macos-native/stage-4-product-polish.md`（新增）
- `docs/macos-native/stage-5-release-readiness.md`
- `docs/macos-native/README.md`
- `docs/macos-native/development-progress.md`
- `docs/macos-native/stage-3-native-interactions.md`
- `docs/macos-native/stage-3-review-issues.md`
- `docs/macos-native/stage-0-requirements-and-validation.md`
