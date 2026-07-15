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
> 平台 / 范围：仅 macOS 13.0+；阶段 3 原生交互完善

---

## 1. 总体进度

| 阶段 | 方案内容 | 状态 | 说明 |
|---|---|---|---|
| 阶段 0 | 需求冻结与技术验证 | **已完成** | S0-01～S0-10 通过 |
| 阶段 1 | 内容架领域与窗口骨架 | **已完成** | REV-S1 已关闭 |
| 阶段 2 | 拖放与剪贴板主链路 | **已完成** | REV-S2 已关闭 |
| 阶段 3 | 原生交互完善 | **代码已实现，待手工验收** | REV-S3 已关闭；本地化/收起堆/无障碍标签/阶段 4 接入点规划已落地；详情尺寸与 Space Quick Look 交互已修；自动化 90/90 |
| 阶段 4 | 发布准备 | **未开始** | 接入点规划见 [stage-4 §9](./stage-4-release-readiness.md#9-发布接入点规划阶段-3-预埋) |

**综合判断：阶段 3 产品代码与自动化回归已就绪（90/90）。手工反馈的详情尺寸 / 选中跳变 / Space Quick Look 已在代码侧修复，待按 [手工验收清单](./stage-3-manual-acceptance.md) 复验后再申请退出阶段 3。**

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
3. **内容插入微动画 / 高频压力**：窗口尺寸动画既有；S3-08 仍依赖手工压力验收。
4. **Prototype 未编译**：仅作历史参考。
5. **空格 Quick Look**：已按 responder 链接管 `QLPreviewPanel`，并在点击/预览时 `activate` 内容架，避免 Space 落到 Finder；**仍待手工确认**切到 Finder 后再点回内容架按 Space 预览的是架内文件。

## 5. 验证与修复记录

| 类型 / 级别 | 场景或问题 | 状态 | 证据 / 修复 |
|---|---|---|---|
| 构建 / 单测 | Debug 测试 89/89 | **通过** | `xcodebuild test -scheme Drops -destination 'platform=macOS'`（2026-07-14） |
| 自动化 | en / zh-Hans 覆盖与手动切换 | **通过** | `AppLocalizationTests` |
| 自动化 | 收起堆显示 / 展开隐藏 | **通过** | `CollapsedStackViewTests` |
| 手工反馈修复 | 详情框过大；单击选中框突然变大；Space 无法 Quick Look / 误触 Finder 预览 | **代码已实现，待手工复验** | 展开尺寸随数量增长；选区轻量同步；Space 转发 + `acceptsPreviewPanelControl` + 点击时激活 Drops，避免 Finder 抢走预览 |
| 手工反馈修复 | 拖放文本合并无感知 | **代码已实现，待手工复验** | 停留/就绪用灰白与选中蓝提示 + 底部文案「正在合并文本，松手完成」+ 触感；本地化抽查通过 |
| 手工反馈修复 | 合并成功后拖影先回弹再消失；零尺寸拖影导致崩溃；就绪提示呼吸缩放 | **代码已实现，待手工复验** | 达到悬停就绪时关闭 drag-image 回位，并立即隐藏被拖源项；松手后直接 `replaceItems`，去掉参与项 0.28s 放大—回缩（那是「回原位→抖动→消失」的主因）；结果项仍轻脉冲。合并相关单测 14/14（2026-07-15）。 |
| 手工反馈修复 | 禁用架内重排后拖放合并失效 | **已修复，待手工复验** | 合并源改为拖出的 `dragOutItemIDs`，不依赖可能为空的选区；`testDragMergeUsesSourceIDsEvenWhenSelectionEmpty` 通过 |
| 手工反馈修复 | 粘贴后旧首项仍被选中；框内拖放误触发“排序” | **代码已实现，待手工复验** | `insertItems` 仅选中新插入项；拒绝同源架内 drop 避免重插入前移；领域单测通过；PRD 5.4.1 已同步 |
| 手工反馈修复 | 详情右上角网格/列表切换图标难辨认 | **代码已实现，待手工复验** | 独立 `configureModeIcon`：`square.grid.2x2` / `list.bullet` 加大至 15pt medium、深色描边；仅选中态浅灰圆角底，未选中无背景 |
| 自动化 | 合并相关聚焦单测 | **通过** | `TextMergeServiceTests` + `ShelfItemDomainTests` + `ShelfStage3InteractionTests`（15/15，2026-07-14） |
| 自动化 | 展开尺寸随数量增长并封顶 | **通过** | `testExpandedSizeGrowsWithItemCountAndCapsAtMax` |
| 自动化 | 插入后选区仅为新项 | **通过** | `testInsertedItemsBecomeSoleSelection` |
| 审查 | REV-S3-001～005 | **已关闭** | 见 stage-3-review-issues.md |
| 手工 | S3-01/03/05/07～14 | **待验证** | [stage-3-manual-acceptance.md](./stage-3-manual-acceptance.md) |

## 6. 未完成 / 待办

### P0 · 正确性或稳定性

- [x] REV-S3-001～005。
- [x] String Catalog（en + zh-Hans）+ 运行时语言覆盖。
- [x] 手工反馈：详情尺寸 / 选中框跳变 / Space Quick Look（代码已修，待手工复验）。
- [x] 手工反馈：拖放文本合并增加高亮与「正在合并文本」提示（待手工复验）。
- [x] 手工反馈：粘贴仅选中新项；禁用架内拖放重排（待手工复验）。
- [x] 手工反馈：合并成功时源项立即消失（无回原位抖动），结果项轻脉冲（待手工复验）。
- [x] 手工反馈：详情右上角网格/列表切换图标可读性（代码已修，待手工复验）。
- [ ] 按 [手工验收清单](./stage-3-manual-acceptance.md) 完成勾选并记录问题。

### P1 · 治理、性能或维护性

- [x] 收起态重叠堆视觉（最多 3 图标）。
- [x] VoiceOver / 焦点代码侧能力（标签 + 临时架不抢焦点）；**手工勾选 S3-14 仍待做**。
- [x] 多屏 / 深浅色代码侧适配 + 验收清单；**手工勾选 S3-09 仍待做**。
- [x] 规划阶段 4 的 Sandbox / Developer ID / 公证接入点。

## 7. 验收对照

| 验收项 | 状态 |
|---|---|
| S3-01 网格/列表与图标缩略图 | **代码已实现，待手工验证**（右上角切换图标已加大并区分选中底） |
| S3-02 选择一致性 | **代码已实现，待手工验证**（选区同步不再整窗 reload；粘贴/拖入仅选中新项） |
| S3-03 打开 / 定位 / 失败反馈 | **代码已实现，待手工验证** |
| S3-04 混选预览 | **已验证（自动化决策）**；Space→QL 已修（焦点转发 + 防 Finder 抢预览），**待手工** |
| S3-05 右键 / 移除安全 | **代码已实现，待手工验证** |
| S3-06 菜单文本合并 | **已验证（自动化）** |
| S3-07 拖放文本合并 | **代码已实现，待手工验证**（高亮/文案提示 + 就绪即藏源项 + 松手直接合并，无回原位抖动） |
| S3-08 动画与高频 | **待手工验证**（含展开尺寸随数量变化；合并成功缩放） |
| S3-09 多屏 / 缩放 / 深浅色 | **代码已实现，待手工验证**（清单已备） |
| S3-10 菜单栏入口 | **代码已实现，待手工验证** |
| S3-11 英/简中与回退 | **代码已实现，待手工验证**（有自动化抽查） |
| S3-12 双语布局 | **待手工验证** |
| S3-13 安全文案 | **代码已实现，待产品抽查** |
| S3-14 无障碍与焦点 | **代码已实现，待手工验证**（清单已备） |

## 8. 建议下一迭代顺序

1. 手工复验：合并成功源项立即消失（无回原位抖动）、粘贴仅选中新项、架内拖放不再重排、合并反馈色（灰/蓝）、详情尺寸 / Space Quick Look。
2. 按 [stage-3-manual-acceptance.md](./stage-3-manual-acceptance.md) 完成其余勾选并回填。
3. 进入 [stage-4-release-readiness.md](./stage-4-release-readiness.md)，按 §9 启用 Sandbox → Developer ID → 公证。

## 9. 变更文件速查

**本轮（合并成功去掉回原位抖动）**

- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`（就绪即隐藏源项；松手直接 `replaceItems`；移除参与项脉冲）
- `docs/macos-native/development-progress.md`

**上轮（合并成功动画 / 取消拖影回弹）**

- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`（抑制拖影回弹且不再设置非法零尺寸 frame；参与项/结果缩放脉冲；菜单合并结果脉冲）
- `docs/macos-native/development-progress.md`

**更早（粘贴选区 / 禁用架内重排）**

- `macos-native/Drops/Domain/ShelfModels.swift`（`insertItems` 仅选中新项）
- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`（拒绝同源架内 drop）
- `macos-native/DropsTests/ShelfItemDomainTests.swift`
- `docs/Drops-PRD.md`（5.4.1 选区规则）
- `docs/macos-native/development-progress.md`

**更早（拖放合并反馈 / 灰蓝配色）**

- `macos-native/Drops/ShelfUI/ShelfContentViewController.swift`
- `macos-native/Drops/Services/AppLocalization.swift` / `Resources/Localizable.xcstrings`
- `macos-native/DropsTests/AppLocalizationTests.swift`
