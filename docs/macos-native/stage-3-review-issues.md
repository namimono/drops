# 阶段 3 · 代码审查问题清单

> 审查日期：2026-07-14<br>
> 修复日期：2026-07-14<br>
> 审查范围：`macos-native/Drops/Domain/`、`Application/`、`ShelfUI/`、`Services/`、`DropsTests/` 及阶段 3 验收文档<br>
> 对应实施：[stage-3-native-interactions.md](./stage-3-native-interactions.md)<br>
> 当前结论：**REV-S3-001～005 已关闭。自动化通过；手工验收 S3-01～S3-14 已全部通过（2026-07-15）。阶段 3 退出条件已满足。**

## 1. 审查证据

| 检查项 | 结果 | 说明 |
|---|---|---|
| 原生单元测试 | **通过（83/83）** | `xcodebuild test -project Drops.xcodeproj -scheme Drops -destination 'platform=macOS'`（2026-07-14 修复后） |
| 窗口布局 | **已修复** | `scrollView.translatesAutoresizingMaskIntoConstraints = false` 提前到入树前；全量测试日志无 `Unable to simultaneously satisfy constraints`；`testTransientPanelKeepsNonactivatingMask` 单独复跑通过 |
| S3-04 混选预览决策 | **通过** | `ShelfPreviewDecisionTests` |
| S3-06 文本合并 | **通过** | `TextMergeServiceTests` |
| 选区 / 右键 / 打开失败回归 | **通过** | `ShelfStage3InteractionTests`（6 例） |
| 手工验收 | **已通过** | S3-01～S3-14 全部通过；见 [stage-3-manual-acceptance.md](./stage-3-manual-acceptance.md)（2026-07-15） |

## 2. 问题摘要

| 编号 | 级别 | 问题 | 影响验收 | 状态 |
|---|---|---|---|---|
| REV-S3-001 | P1 | `NSScrollView` 关闭 autoresizing mask 的时机过晚，产生必现布局冲突 | S3-01、S3-08、S3-09 | **已关闭** |
| REV-S3-002 | P1 | 网格 Command 取消选择未同步领域状态，Shift 多选目标不确定 | S3-02、S3-05 | **已关闭** |
| REV-S3-003 | P1 | 右键菜单未采用右键命中项，操作可能作用于旧选区 | S3-03、S3-05、S3-06 | **已关闭** |
| REV-S3-004 | P2 | 异步缩略图未校验复用单元格身份，可能显示其他项目的缩略图 | S3-01 | **已关闭** |
| REV-S3-005 | P2 | 打开失败仅写日志并蜂鸣，没有明确、可恢复的用户反馈 | S3-03 | **已关闭** |

## 3. 详细问题与修复

### REV-S3-001 · ScrollView 必现 Auto Layout 冲突（P1）— 已关闭

**修复**

- 在 `loadView()` 中、`scrollView` 入树与约束激活之前设置 `translatesAutoresizingMaskIntoConstraints = false`，并完成滚动区基础配置。
- 回归：`testScrollViewDisablesAutoresizingMaskBeforeLayout`；全量测试日志无约束冲突。

### REV-S3-002 · 网格取消选择与区间选择不同步（P1）— 已关闭

**修复**

- 实现 `collectionView(_:didDeselectItemsAt:)`，仅在 Command（toggle）时同步领域取消选择。
- 选择目标优先使用鼠标命中 index，经 `ShelfCollectionClickTarget` 解析；禁止从无序多元素 `Set` 取 `first`。
- 回归：`testCommandToggleDeselectUpdatesDomainSelection`、`testCollectionClickTargetPrefersConcreteIndexOverUnorderedSet`。

### REV-S3-003 · 右键菜单可能操作旧选区（P1）— 已关闭

**修复**

- 菜单构建前执行 Finder 规则：命中既有多选区则保留；否则将命中项设为唯一选中。
- 列表（`clickedRow`）与网格（事件坐标命中）共用 `ShelfContextMenuSelection`。
- 回归：`testContextMenuKeepsMultiSelectWhenHittingInsideSelection`、`testRightClickUnselectedItemUpdatesLocalSelectionBeforeMenuActions`。

### REV-S3-004 · 异步缩略图污染复用单元格（P2）— 已关闭

**修复**

- `ShelfListCellView` / `ShelfGridItemView` 配置时记录 `representedItemID`；缩略图回调仅在 ID 仍一致时赋图。

### REV-S3-005 · 打开失败缺少明确反馈（P2）— 已关闭

**修复**

- `ItemActionService` 增加缺失文件检测与恢复建议文案。
- `ShelfManager` 通过 `onUserFacingError` 上报标题 + 可恢复说明；`ApplicationController` 接到 `presentUserMessage`。
- 回归：`testOpenMissingFileReportsRecoverableUserFacingError`。

## 4. 修复优先级与回归建议（完成情况）

1. [x] 修复 REV-S3-001，消除窗口测试中的必现布局冲突。
2. [x] 修复 REV-S3-002、REV-S3-003，并补齐网格选区与右键数据安全回归。
3. [x] 修复 REV-S3-004、REV-S3-005，覆盖快速滚动复用和打开失败反馈。
4. [x] 重新运行自动化（83/83），测试日志不再出现 Auto Layout 冲突。
5. [x] 执行 S3-01、S3-03、S3-05、S3-07～S3-14 手工验收；完成 String Catalog 与双语验证（2026-07-15）。

## 5. 阶段退出意见

审查缺陷 REV-S3-001～005 已关闭；自动化与手工验收均已通过。阶段 3 退出条件已满足，可进入阶段 4 发布准备。
