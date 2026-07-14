# 阶段 0：需求冻结与技术验证

> 状态：已完成（S0-01～S0-10 通过；可进入阶段 1）<br>
> 更新日期：2026-07-14<br>
> 上级文档：[macOS 原生方案](README.md)<br>
> 产品依据：[Drops PRD](../Drops-PRD.md)<br>
> 审查问题：[stage-0-review-issues.md](stage-0-review-issues.md)<br>
> 开发进度：[development-progress.md](development-progress.md)

## 1. 阶段定位

本阶段用于冻结首版原生产品的范围，并验证决定架构成败的 macOS 系统能力。阶段结束时，团队应能确定现有方案可以支撑后续开发，且关键交互不存在尚未验证的技术阻断。

本阶段不交付可日常使用的产品版本。

## 2. 实现目标

- 将 PRD 中已确认的产品边界转化为可执行、可验收的工程约束。
- 确认最低支持 macOS 版本、应用标识、签名与发布前提。
- 建立不依赖 Flutter 的原生 macOS 工程和测试入口。
- 验证无边框浮窗、多窗口、拖入、拖出、不抢焦点和受管临时文件等关键能力。
- 提前发现可能改变窗口、拖放或数据安全方案的系统限制。

## 3. 范围概要

### 3.1 本阶段包含

- PRD 范围评审和核心场景验收步骤整理。
- 原生 Xcode 工程、Debug/Release 配置和测试 Target。
- 内容架窗口和拖放主链路的最小技术原型。
- 受管临时目录、删除边界和符号链接逃逸防护验证。
- 关键架构决策及风险记录。

### 3.2 本阶段不包含

- 完整内容架界面和正式视觉效果。
- 完整剪贴板类型处理或文本合并。
- 正式数据迁移、安装包和发布流程。
- 归档、裁剪、音频提取、ICO 转换、媒体下载及 Windows 支持。

## 4. 范围冻结清单

产品依据：[Drops PRD](../Drops-PRD.md) 第 8 章。本清单状态：**已冻结**（2026-07-14）。

### 4.1 首版正式范围（必须实现）

- 仅 macOS；Swift / AppKit 原生实现，不依赖 Flutter。
- 内容架：快捷键 / 菜单栏 / 摇动创建；主动与临时生命周期；最多 20 个。
- 内容：文件、文件夹、链接、剪贴板非文件内容物化；同路径去重并前移。
- 交互：收起堆叠、展开网格/列表、选择、拖入拖出、Quick Look、合并文本。
- 临时文件：默认保留 30 天，可配置且 ≤ 120 天；清理不得删除用户原始文件。
- 本地化：英文 + 简体中文；不支持系统语言回退英文。

### 4.2 明确非目标（首版不实现、不验收）

| 边界 | 说明 |
|---|---|
| 图片/视频压缩 | 不设计、不开发、不验收压缩、格式转换、缩放、GIF、能力准备与任务调度 |
| 文件归档 | 不设计、不开发、不验收归档及密码/输出目录等衍生能力 |
| 辅助工具 | 不提供音频提取、ICO 转换、视频下载、媒体下载；无“其他工具”入口 |
| 独立转换入口 | 不提供辅助工具式单项或批量转换入口 |
| 媒体裁剪 | 不进入产品范围 |
| Windows | 不构建、不对齐、不承诺兼容 |
| 长期网盘/同步 | 不做分类、标签、搜索、版本管理 |
| 许可证激活草稿页 | PRD 不定义为已发布功能 |

### 4.3 核心验收场景索引（来自 PRD 第 9 章）

后续阶段按此清单验收；阶段 0 只建立验证基础，不要求产品级通过。PRD 9.3 已移出范围。

1. **9.1 内容架主链路**：摇动创建、去重前移、整堆拖出 copy/move、展开选择与预览。
2. **9.2 粘贴与文本合并**：纯文本/截图/链接物化；菜单合并与拖拽合并。
3. **9.4 临时文件、语言与安全文案**：保留期、引用保护、清理边界、双语与安全术语。
4. **9.5 多内容架与系统入口**：独立窗口、临时自动关闭、20 上限、菜单栏入口。

### 4.4 范围评审结论

- PRD 第 8 章决策已作为工程正式约束写入本清单。
- 2026-07-14 追加决策：图片/视频压缩不进入原生首版；若 `Drops-PRD.md` 仍描述该能力，以本冻结清单为准并后续同步 PRD。
- 阶段 0 及以后不得以“迁移兼容”“技术预留”名义重新引入非目标能力。

## 5. 阶段交付物

- 可独立编译和运行的原生 macOS 工程骨架。
- 可重复执行的关键能力验证 Demo 或测试入口。
- 已确认的范围清单、核心验收场景和非目标清单。
- 最低支持系统、窗口方案、拖放方案和临时文件边界的决策记录。
- 技术风险清单及每项风险的处理结论。

## 6. 验收标准

| 编号 | 验收标准 | 验收证据 |
|---|---|---|
| S0-01 | 已确认决策已成为正式范围约束，明确首版不实现图片/视频压缩、归档、裁剪、辅助工具、独立转换入口和 Windows 支持。 | 第 4 节范围冻结清单 |
| S0-02 | 最低支持 macOS 版本、产品 Bundle ID、Debug/Release 配置和签名策略已有明确结论。 | 第 9 节决策记录 + `project.yml` |
| S0-03 | 原生工程可在干净环境完成 Debug 和 Release 构建，测试 Target 可运行，产品运行时不依赖 Flutter。 | 第 11 节构建日志与测试结果 |
| S0-04 | 可在鼠标附近展示无边框内容架原型，窗口无灰色直角底层、异常边框或系统默认背景泄漏。 | 浅色/深色模式演示或截图（M-01） |
| S0-05 | 主动创建的窗口可正常交互；外部拖拽期间出现的窗口能够接收内容且不抢走源应用焦点。 | 跨应用手工演示记录（M-02） |
| S0-06 | Finder 文件可拖入原型，原型中的文件可拖到 Finder 或其他应用，复制、移动和取消结果可识别。 | Finder 与至少一个第三方应用演示（M-03/M-04） |
| S0-07 | 可同时创建多个相互独立的窗口，关闭其中一个不会导致其他窗口状态丢失或进程异常。 | 多窗口演示与异常日志检查（M-05） |
| S0-08 | 受管临时文件只能在指定目录内被清理，外部文件和通过符号链接逃逸到目录外的目标不会被删除。 | 自动化测试或验证报告 |
| S0-09 | 主动创建到首帧可见、摇动触发到可接收拖放的性能基准已确认，后续阶段有统一测量口径。 | 性能基准记录（M-06 / D-15） |
| S0-10 | 阶段 0 退出评审时，所有关键技术风险均须有“通过、接受限制或调整方案”的明确结论，且不得存在未处理的架构阻断项。 | 第 10 节风险清单与阶段评审结论 |

## 7. 准入条件

- [Drops PRD](../Drops-PRD.md) 已作为产品范围基线。
- 已确认产品只面向 macOS，并采用 Swift 原生实现。
- 可获得目标最低系统版本的测试环境。

## 8. 退出条件

- S0-01 至 S0-10 全部通过。
- 关键能力验证结果已进入决策记录，不依赖口头结论。
- 尚未解决的问题均不影响阶段 1 的窗口与领域骨架建设。
- 阶段评审确认可以进入阶段 1。

## 9. 关键架构决策记录

| 编号 | 决策项 | 结论 | 理由 |
|---|---|---|---|
| D-01 | 工程位置 | `macos-native/Drops.xcodeproj`，由 `project.yml` + XcodeGen 生成 | 与 Flutter Runner 隔离；文件增删可重复生成 |
| D-02 | Bundle ID | `click.shakepin.macos` | 与现网 Sparkle / 用户数据路径连续，后续迁移验证同一标识 |
| D-03 | 产品名 | `Drops`（显示名与 Target 名） | 对齐 PRD；旧 Flutter Target 曾用 ShakePin，原生版统一为 Drops |
| D-04 | 最低系统 | **macOS 13.0** | 满足现代 AppKit / 安全 API；低于 13 不作为支持目标 |
| D-05 | UI 技术 | 内容架与拖放用 AppKit；设置等表单后续用 SwiftUI | 浮窗、焦点、系统拖放用 AppKit 更可预测 |
| D-06 | 内容架窗口 | `NSPanel` + `.borderless` + `NSVisualEffectView` 圆角 | 验证无灰色直角底层；临时窗使用 `.nonactivatingPanel` |
| D-07 | 临时窗焦点 | 临时内容架 `orderFrontRegardless` 且不 `activate` | 外部拖拽期间不抢源应用焦点 |
| D-08 | 拖放 | `NSDraggingDestination` / `NSDraggingSource` + file URL pasteboard | 阶段 0 足够验证 Finder 与跨应用 copy/move/cancel |
| D-09 | 临时文件根目录 | `~/Library/Application Support/<bundle-id>/TemporaryContent/` | 不用 `NSTemporaryDirectory`，避免系统提前清理 |
| D-10 | 删除安全 | 标准化路径 + `resolvingSymlinksInPath`，拒绝根外与符号链接逃逸 | 满足 S0-08；清理与手动清理共用入口 |
| D-11 | Debug/Release | Xcode 标准 Debug / Release；Hardened Runtime 开启 | Release 用于构建验证；正式 Developer ID 公证留到阶段 4 |
| D-12 | 签名策略 | 阶段 0：Automatic + 本地开发签名；无 Team 也可 Debug 构建；正式发布用 Developer ID | 发布签名与公证不阻塞阶段 0 退出 |
| D-13 | Sandbox | 阶段 0 原型 **关闭 App Sandbox** | 降低拖放验证噪声；阶段 4 发布前再启用并补齐书签/权限 |
| D-14 | Flutter | 原生 Target **零依赖** Flutter Engine / MethodChannel | 运行时与构建均不链接 Flutter |
| D-15 | 性能预算 | 主动创建→首帧 P95 < 300 ms；摇动/临时→可拖放 P95 < 200 ms | 结束点为 CATransaction completion 后的 firstFrameVisible / dragReady；M-06 手工报告 p95=78.7ms，通过 |

### 9.1 实现偏差（已关闭）

- D-06 / D-07 / D-08：M-01～M-05 手工通过（直角边框与按住拖出已二次修复后复验）。
- D-15：测量点对齐且 M-06 通过。
- 审查关闭记录见 [stage-0-review-issues.md](stage-0-review-issues.md)。

### 9.2 对阶段 1 的约束

- 阶段 1 沿用本表的系统版本、Bundle ID、工程布局及窗口行为契约，不再重新选型。
- 领域模型与 `ShelfWindowController` 正式实现时，可替换 Stage 0 原型类，但行为契约保持一致。

## 10. 技术风险与结论

| 编号 | 风险 | 验证方式 | 结论 | 处理 |
|---|---|---|---|---|
| R-01 | 无边框浮窗出现灰色直角/系统背景泄漏 | `NSPanel` + VisualEffect + layer cornerRadius | **通过（手工）** | 二次修复后 M-01 通过 |
| R-02 | 临时窗抢走拖拽源焦点导致拖放中断 | `.nonactivatingPanel` + 不调用 `activate` | **通过（手工）** | M-02 通过 |
| R-03 | Finder / 第三方应用拖入拖出不可靠 | file URL destination + dragging session source | **通过（手工）** | M-03 / M-04 通过（按住拖出） |
| R-04 | 多窗口关闭互相影响或进程异常 | 多 `ShelfPanelController` 独立持有 | **通过（手工+单测）** | M-05 通过 |
| R-05 | 清理误删用户原始文件或符号链接逃逸 | 单元测试覆盖外部路径与 symlink | **通过** | `validateManagedURL` 拒绝逃逸；测试见 `ManagedTemporaryFileStoreTests` |
| R-06 | 使用系统临时目录导致提前丢失 | 决策写入 Application Support | **通过（方案）** | 见决策 D-09 |
| R-07 | 最低系统版本过高/过低 | 工程 `MACOSX_DEPLOYMENT_TARGET=13.0` | **接受限制** | 仅支持 macOS 13+；不维护更旧版本 |
| R-08 | 签名/公证阻塞阶段 0 | Debug/Release 本地构建 | **接受限制** | 发布签名留阶段 4；不构成架构阻断 |
| R-09 | App Sandbox 与拖放书签复杂度 | 阶段 0 关闭 Sandbox | **接受限制** | 发布前再启用；不改变领域与窗口方案 |
| R-10 | 性能不达标 | Stage0 指标采样器 | **通过（手工）** | M-06 报告 p95=78.7ms，低于预算 |
| R-11 | 重写范围过大 | 分阶段交付 | **通过（流程）** | 阶段 0 只做骨架与验证，不交付日用版本 |
| R-12 | Flutter 残留依赖 | Target 源码与链接检查 | **通过** | `macos-native` 无 Flutter import / Pod |
| R-13 | AppDelegate 未安装导致应用无窗口 | 实际启动 + 宿主单测 | **已修复并通过** | `main.swift` 强持有；手工窗口可见 |
| R-14 | 启动和窗口回归缺少自动化保护 | 原生测试范围核对 | **已补测试** | `Stage0LaunchAndWindowTests` 6 例 |

### 10.1 阶段评审结论

- S0-01～S0-10 均已满足；R-01～R-14 均有「通过 / 接受限制 / 已修复」结论，无未处理架构阻断项。
- 接受限制项（R-07～R-09）不阻塞阶段 1：系统版本、发布签名与 Sandbox 已明确留给后续阶段。
- **阶段 0 可退出；允许进入阶段 1。**

## 11. 验证记录

### 11.1 自动化验证

| 命令 | 结果 | 说明 |
|---|---|---|
| `cd macos-native && xcodegen generate` | **通过** | 生成 `Drops.xcodeproj` |
| `xcodebuild -scheme Drops -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build` | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| `xcodebuild -scheme Drops -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build` | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| `xcodebuild test -scheme Drops -destination 'platform=macOS' -derivedDataPath build/DerivedData` | **通过** | 14/14：`ManagedTemporaryFileStoreTests` 8 + `Stage0LaunchAndWindowTests` 6 |
| `otool -L …/Drops.app/Contents/MacOS/Drops` | **通过** | 无 Flutter 动态库链接 |

### 11.2 2026-07-14 运行审查与修复

| 检查项 | 结果 | 证据 |
|---|---|---|
| 启动后 AppDelegate | **已修复并验证** | `main.swift` 强持有；`testHostAppInstallsDelegate`；手工可见窗口 |
| 直角边框 / 灰底泄漏 | **已修复并复验通过** | 去掉 `.resizable`；透明 root + 圆角 VisualEffect + `invalidateShadow`；M-01 通过 |
| 拖出手势 | **已修复并复验通过** | `pasteboardWriterForRow` 按住拖出；M-04 通过 |

### 11.3 手工验证清单

| 编号 | 场景 | 步骤 | 期望 | 结果 |
|---|---|---|---|---|
| M-01 | 无边框浮窗 | 菜单 → New Persistent Shelf；切换浅色/深色 | 圆角浮层，无灰色直角底层或外圈直角描边 | **通过**（二次修复后复验） |
| M-02 | 临时窗不抢焦点 | 在其他应用开始拖拽后开 Transient Shelf | 源应用保持前台；可拖入 | **通过** |
| M-03 | Finder 拖入 | 从 Finder 拖文件到架内 | 列表出现文件名；日志 DragIn | **通过** |
| M-04 | 拖出 copy/move/cancel | 选中后按住拖到 Finder / 其他 App | 日志识别 operation；不依赖双击 | **通过**（按住拖出复验） |
| M-05 | 多窗口独立 | Create Three Independent Shelves，关闭其中一个 | 其余窗口仍在且内容保留 | **通过** |
| M-06 | 性能样本 | 见下方步骤 | 输出 avg/p95 与预算对照 | **通过**；手工报告 **p95=78.7ms**（低于 300ms / 200ms 预算） |

#### M-06 怎么测（建议步骤）

预算：主动创建→首帧 P95 < 300 ms；临时创建→可拖放 P95 < 200 ms。

1. 用 Xcode 或 `open …/Drops.app` 启动 Debug 版 Drops。
2. 打开 **Console.app**（控制台），在搜索框过滤 `Stage0` 或 `Perf`，便于看采样日志。
3. **主动窗样本（建议 ≥ 20 次）**  
   - 菜单栏托盘 → **New Persistent Shelf**（或快捷键 `N`）  
   - 每点一次应打一条：`[Stage0][Perf] persistent first-frame=…ms`  
   - 可穿插关闭窗口，再继续创建；不要只测冷启动一次。
4. **临时窗样本（建议 ≥ 20 次）**  
   - 托盘 → **New Transient Shelf (No Activate)**（或 `T`）  
   - 应出现：`[Stage0][Perf] transient drag-ready=…ms`
5. 采完后托盘 → **Log Performance Benchmarks**。  
   控制台会打印汇总，例如：
   ```
   [Stage0][Perf] Baseline summary
   - Persistent create→first-frame: n=20 avg=…ms p95=…ms budget=300ms [PASS|OVER]
   - Transient create→drag-ready: n=20 avg=…ms p95=…ms budget=200ms [PASS|OVER]
   ```
6. 把该汇总原样记入本节或 `development-progress.md`。
7. 若机器刚开机或 Xcode 刚 attach，先丢弃前 2～3 次样本再正式计数（避免冷缓存扭曲 P95）。

#### M-06 采样结果（2026-07-14）

| 指标 | 预算 | 结果 |
|---|---|---|
| 创建路径 P95（手工报告） | < 300 ms / < 200 ms | **p95=78.7ms → PASS** |

测量口径见 D-15：结束点为 firstFrameVisible / dragReady。

### 11.4 性能预算与测量状态

| 指标 | 预算 | 当前状态 |
|---|---|---|
| 主动创建 → 首帧可见 | P95 < 300 ms | **通过**（手工 p95=78.7ms） |
| 临时创建 → 可接收拖放 | P95 < 200 ms | **通过**（同上报告，低于预算） |

### 11.5 S0 验收对照

| 编号 | 状态 | 证据 |
|---|---|---|
| S0-01 | **已实现** | 第 4 节范围冻结清单 |
| S0-02 | **已实现** | 第 9 节决策记录 + `project.yml` |
| S0-03 | **已验证** | 第 11.1 节构建 / 测试 / otool |
| S0-04 | **已验证（手工）** | M-01 通过 |
| S0-05 | **已验证（手工）** | M-02 通过 |
| S0-06 | **已验证（手工）** | M-03 / M-04 通过 |
| S0-07 | **已验证（手工+单测）** | M-05 通过 |
| S0-08 | **已验证** | 单测覆盖外部路径与 symlink 逃逸 |
| S0-09 | **已验证** | M-06 p95=78.7ms；测量口径见 D-15 |
| S0-10 | **已通过** | 第 10 节风险清单无未处理架构阻断项 |

### 11.6 本轮问题结论

| 现象 | 文档依据 | 归类 | 处理 |
|---|---|---|---|
| 直角外框 + 内嵌圆角 | S0-04、S1-07 | **实现 bug** | 已修；M-01 复验通过 |
| 双击才拖出 | S2-04 手势约定补全 | **原型实现偏差** | 已改按住拖出；M-04 复验通过 |
| M-06 不知如何测 | S0-09 / D-15 | **文档缺口** | 已补步骤；采样通过 |

## 12. PRD 映射与后续依赖

本阶段覆盖 PRD 第 2 章平台范围、第 8 章产品边界，并为第 9 章全部核心验收场景建立验证基础。阶段 1 使用本阶段确认的窗口方案、系统版本和工程配置，不再重复进行架构选型。
