# Drops macOS 原生化 · 开发进度

> 更新日期：2026-07-15
> 对应方案：[README.md](./README.md)  
> 产品依据：[Drops-PRD.md](../Drops-PRD.md)  
> 阶段 0 实施：[stage-0-requirements-and-validation.md](./stage-0-requirements-and-validation.md)  
> 阶段 1 实施：[stage-1-shelf-domain-and-window.md](./stage-1-shelf-domain-and-window.md)  
> 阶段 2 实施：[stage-2-drag-drop-and-pasteboard.md](./stage-2-drag-drop-and-pasteboard.md)  
> 阶段 3 实施：[stage-3-native-interactions.md](./stage-3-native-interactions.md)  
> 阶段 3 手工验收：[stage-3-manual-acceptance.md](./stage-3-manual-acceptance.md)  
> 阶段 0 审查：[stage-0-review-issues.md](./stage-0-review-issues.md)<br>
> 阶段 1 审查：[stage-1-review-issues.md](./stage-1-review-issues.md)<br>
> 阶段 2 审查：[stage-2-review-issues.md](./stage-2-review-issues.md)<br>
> 阶段 3 审查：[stage-3-review-issues.md](./stage-3-review-issues.md)<br>
> 基线分支：当前工作区（原生工程位于 `macos-native/`）  
> 平台 / 范围：仅 macOS 13.0+；阶段 3 原生交互完善 **已完成**

---

## 1. 总体进度

| 阶段 | 方案内容 | 状态 | 说明 |
|---|---|---|---|
| 阶段 0 | 需求冻结与技术验证 | **已完成** | S0-01～S0-10 通过 |
| 阶段 1 | 内容架领域与窗口骨架 | **已完成** | REV-S1 已关闭 |
| 阶段 2 | 拖放与剪贴板主链路 | **已完成** | REV-S2 已关闭 |
| 阶段 3 | 原生交互完善 | **已完成** | REV-S3 已关闭；S3-01～S3-14 全部通过（自动化 + 手工验收）；退出条件已满足 |
| 阶段 4 | 发布准备 | **未开始** | 可按 [stage-4 §9](./stage-4-release-readiness.md#9-发布接入点规划阶段-3-预埋) 启动 |

**综合判断：阶段 3 已退出。产品代码、自动化回归（90/90）与 [手工验收清单](./stage-3-manual-acceptance.md) 全部通过；可进入阶段 4 发布准备。**

## 2. 已实现能力

### 阶段 0–2（基线）

- 内容架领域、生命周期、拖入/拖出、剪贴板物化、摇动唤起、保留清理等。

### 阶段 3

- 网格 / 列表、图标与缩略图、打开 / 定位 / Quick Look、右键、文本合并、Settings / About / Logs。
- **收起态重叠堆**：最多露出 3 个图标 + 数量文案；拖动整堆；双击展开。
- **本地化**：`Localizable.xcstrings`（en + zh-Hans）；设置语言覆盖立即生效；不支持系统语言回退英文。
- **无障碍**：内容架 / 列表 / 网格 / 收起堆 / 按钮 / 菜单栏 VoiceOver 标签；临时架不抢焦点。
- **深浅色**：HUD `NSVisualEffectView` 跟随系统外观。
- **阶段 4 预埋**：Sandbox / Developer ID / 公证接入点与切换顺序已写入阶段 4 文档。

## 3. 已落地的架构改动

| 模块 | 路径 | 职责 |
|---|---|---|
| 本地化 | `Resources/Localizable.xcstrings` + `Services/AppLocalization.swift` | Catalog + 运行时语言解析 / `L10n` |
| 收起堆 | `ShelfUI/CollapsedStackView.swift` | 最多 3 图标重叠堆 |
| 内容 UI | `ShelfUI/ShelfContentViewController.swift` | 收起堆 / 展开网格列表 / 本地化 / a11y |
| 设置 | `Application/SettingsWindowController.swift` | 语言切换驱动 `AppLocalization` |
| 发布规划 | `docs/macos-native/stage-4-release-readiness.md` §9 | Sandbox / 签名 / 公证接入点 |

## 4. 已知偏差 / 限制

1. **App Sandbox 仍关闭**：阶段 4 按文档启用并补 bookmark。
2. **部分系统对话框**：语言覆盖立即作用于 Drops UI；极少数系统级对话框可能需重启后完全跟随（设置页已提示）。
3. **Prototype 未编译**：仅作历史参考。

## 5. 验证与修复记录

| 类型 / 级别 | 场景或问题 | 状态 | 证据 / 修复 |
|---|---|---|---|
| 构建 / 单测 | Debug 测试 90/90 | **通过** | `xcodebuild test -scheme Drops -destination 'platform=macOS'` |
| 自动化 | en / zh-Hans 覆盖与手动切换 | **通过** | `AppLocalizationTests` |
| 自动化 | 收起堆显示 / 展开隐藏 | **通过** | `CollapsedStackViewTests` |
| 手工反馈修复 | 详情框过大；单击选中框突然变大；Space 无法 Quick Look / 误触 Finder 预览 | **已验证** | 展开尺寸随数量增长；选区轻量同步；Space 转发 + `acceptsPreviewPanelControl` + 点击时激活 Drops |
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

## 6. 未完成 / 待办

### 阶段 3

无。S3-01～S3-14 与手工复验项均已关闭。

### 阶段 4（下一阶段）

- [ ] 按 [stage-4-release-readiness.md](./stage-4-release-readiness.md) 启用 Sandbox → Developer ID → 公证。
- [ ] 发布级回归、性能与稳定性、迁移与构建收口。

## 7. 验收对照

| 验收项 | 状态 |
|---|---|
| S3-01 网格/列表与图标缩略图 | **已通过** |
| S3-02 选择一致性 | **已通过** |
| S3-03 打开 / 定位 / 失败反馈 | **已通过** |
| S3-04 混选预览 | **已通过**（自动化决策 + 手工 Space→QL） |
| S3-05 右键 / 移除安全 | **已通过** |
| S3-06 菜单文本合并 | **已通过**（自动化） |
| S3-07 拖放文本合并 | **已通过** |
| S3-08 动画与高频 | **已通过** |
| S3-09 多屏 / 缩放 / 深浅色 | **已通过** |
| S3-10 菜单栏入口 | **已通过** |
| S3-11 英/简中与回退 | **已通过** |
| S3-12 双语布局 | **已通过** |
| S3-13 安全文案 | **已通过** |
| S3-14 无障碍与焦点 | **已通过** |

## 8. 建议下一迭代顺序

1. 进入 [stage-4-release-readiness.md](./stage-4-release-readiness.md)。
2. 按 §9 启用 Sandbox → Developer ID → 公证。
3. 执行发布级回归、性能/稳定性与迁移收口。

## 9. 变更文件速查

**本轮（阶段 3 验收关闭与文档收口）**

- `docs/macos-native/development-progress.md`
- `docs/macos-native/stage-3-manual-acceptance.md`
- `docs/macos-native/stage-3-native-interactions.md`
- `docs/macos-native/stage-3-review-issues.md`
- `docs/macos-native/README.md`

**上轮（网格/列表切换动画）**

- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`
- `docs/macos-native/development-progress.md`

**更早（合并成功去掉回原位抖动）**

- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`
- `docs/macos-native/development-progress.md`

**更早（粘贴选区 / 禁用架内重排）**

- `macos-native/Drops/Domain/ShelfModels.swift`
- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`
- `macos-native/DropsTests/ShelfItemDomainTests.swift`
- `docs/Drops-PRD.md`（5.4.1 选区规则）
- `docs/macos-native/development-progress.md`
