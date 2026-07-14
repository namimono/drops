# 阶段 2 · 代码审查问题清单

> 审查日期：2026-07-14<br>
> 修复更新日期：2026-07-14<br>
> 审查范围：`macos-native/Drops/Domain/`、`Application/`、`ShelfUI/`、`Input/`、`Services/`、`DropsTests/` 及阶段 2 验收文档<br>
> 对应实施：[stage-2-drag-drop-and-pasteboard.md](./stage-2-drag-drop-and-pasteboard.md)<br>
> 当前结论：**REV-S2-001～009 已关闭；自动化 69/69；手工 S2-01 / S2-05 / S2-06 / S2-13 通过。阶段 2 退出条件已满足。**

## 1. 审查证据

| 检查项 | 结果 | 说明 |
|---|---|---|
| 原生单元测试 | **通过（69/69）** | 修复后 `xcodebuild test -project Drops.xcodeproj -scheme Drops -destination 'platform=macOS' ...` |
| Release 构建 | **待复跑** | 审查当时通过；修复后以 Debug 单测为准，建议退出前再跑 Release / Analyze |
| Xcode 静态分析 | **待复跑** | 同上 |
| Diff 健康检查 | **有既存格式问题** | `git diff --check` 报告阶段文档中的行尾空白；与本次功能缺陷无直接关系 |
| 手工验收 | **通过** | S2-01 / S2-05 / S2-06 / S2-13 人工验收通过（2026-07-14） |

## 2. 问题摘要

| 编号 | 级别 | 问题 | 影响验收 | 状态 |
|---|---|---|---|---|
| REV-S2-001 | P0 | 受管临时文件拖入另一内容架后丢失受管身份 | S2-05、S2-10、S2-13 | **已修复** |
| REV-S2-002 | P1 | 应用退出时未释放窗口引用，重启后旧 ShelfID 永久阻止清理 | S2-10、S2-11、S2-13 | **已修复** |
| REV-S2-003 | P1 | 混合 file URL + 图片数据时优先物化图片 | S2-01、S2-12 | **已修复** |
| REV-S2-004 | P1 | UI 刷新重置 Shift 选择锚点 | S2-04 | **已修复** |
| REV-S2-005 | P1 | “立即清理”缺少二次确认 | S2-11、PRD 7.4 | **已修复** |
| REV-S2-006 | P1 | 保留天数无用户入口与非法输入提示 | S2-08、S2-09 | **已修复** |
| REV-S2-007 | P1 | 多项物化中途失败无回滚 | S2-13 | **已修复** |
| REV-S2-008 | P2 | RTF 被 plain text 优先级降级 | S2-03 | **已修复** |
| REV-S2-009 | P2 | Application Support 失败时退回系统临时目录且 `try!` | S2-12、稳定性 | **已修复** |

## 3. 详细问题与修复

### REV-S2-001 · 跨内容架拖入丢失受管身份（P0）— 已修复

拖出写入私有 pasteboard 类型 `click.shakepin.macos.managed-temporary-file-id`；接收时优先恢复记录 ID，或按受管根路径反查记录，并在 `acceptContent` 成功后 `addReference`。回归：`testCrossShelfManagedDragAddsReferenceAndProtectsCleanup`。

### REV-S2-002 · 重启后残留引用永久阻止清理（P1）— 已修复

`applicationWillTerminate` → `prepareForTermination` 关闭全部内容架并清空引用；`ManagedTemporaryFileStore` 加载 metadata 时清除全部 `activeShelfReferences`（内容架不跨进程恢复）。回归：`testStaleReferencesClearedOnStoreReloadAllowCleanup`。

### REV-S2-003 · 混合 pasteboard 类型错误优先物化图片（P1）— 已修复

`PasteboardMaterializer` 将 file URL（含受管恢复）置于 TIFF/PNG 之前。回归：`testFileURLWinsOverImagePreviewOnSameItem`。

### REV-S2-004 · Shift 区间选择锚点在刷新后漂移（P1）— 已修复

`apply(shelf:)` 仅在锚点已不在 items 中时回退；连续 Shift 锚点保持稳定。回归：`testSelectionAnchorSurvivesApplyRefresh`。

### REV-S2-005 · 手动清理缺少二次确认（P1）— 已修复

菜单清理先走确认框，取消不改动文件；结果/错误经可注入提示路径展示。回归：`testManualCleanupConfirmationGate`。

### REV-S2-006 · 保留天数不可由用户配置（P1）— 已修复

菜单栏增加 **Retention Days…**；非法输入提示并保留旧值。回归：`testRetentionPromptRejectsIllegalInputWithFeedbackPath` + 既有 Settings 边界测试。

### REV-S2-007 · 多项物化失败没有事务回滚（P1）— 已修复

物化阶段创建文件但不登记 shelf 引用；批次失败或 `acceptContent` 失败时 `discardCreatedFiles`；元数据持久化失败也会回滚已写文件。回归：`testMaterializeFailureRollsBackPartialCreations`。

### REV-S2-008 · RTF 被 plain text 优先级降级（P2）— 已修复

显式 RTF/RTFD 优先于 AppKit 合成的 plain text；浏览器 HTML+string 仍优先 plain text。回归：`testPrefersRTFOverSynthesizedPlainTextAndMaterializesPDF`。

### REV-S2-009 · 受管目录失败时退回临时目录且可能崩溃（P2）— 已修复

Application Support 初始化失败时禁用受管物化（`isTemporaryStoreUnavailable`），不再回退系统临时目录，也不再 `try!`。

## 4. 修复优先级与回归建议

1. ~~先修复 REV-S2-001…~~ **已完成**
2. ~~修复 REV-S2-002、REV-S2-007…~~ **已完成**
3. ~~修复 REV-S2-003、REV-S2-004…~~ **已完成**
4. ~~补齐 REV-S2-005、REV-S2-006…~~ **已完成**
5. ~~REV-S2-008 / 009…~~ **已完成**
6. ~~手工 S2-01 / S2-05 / S2-06 / S2-13…~~ **已完成**（2026-07-14）

## 5. 阶段退出意见

代码审查项 REV-S2-001～009 已关闭；自动化 69/69；手工 S2-01 / S2-05 / S2-06 / S2-13 通过。阶段 2 退出条件已满足，可进入阶段 3。
