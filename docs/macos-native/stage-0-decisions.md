# 阶段 0 · 关键架构决策记录

> 更新日期：2026-07-14  
> 对应阶段：[需求冻结与技术验证](stage-0-requirements-and-validation.md)

## 决策表

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
| D-11 | Debug/Release | Xcode 标准 Debug / Release；Hardened Runtime 开启 | Release 用于构建验证；正式 Developer ID 公证留到阶段 5 |
| D-12 | 签名策略 | 阶段 0：Automatic + 本地开发签名；无 Team 也可 Debug 构建 | 发布签名与公证不阻塞阶段 0 退出 |
| D-13 | Sandbox | 阶段 0 原型 **关闭 App Sandbox** | 降低拖放验证噪声；阶段 5 发布前再启用并补齐书签/权限 |
| D-14 | Flutter | 原生 Target **零依赖** Flutter Engine / MethodChannel | 运行时与构建均不链接 Flutter |
| D-15 | 性能预算 | 主动创建→首帧 P95 < 300 ms；摇动/临时→可拖放 P95 < 200 ms | 结束点为 CATransaction completion 后的 firstFrameVisible / dragReady；M-06 手工报告 p95=78.7ms，通过 |

## 实现偏差（已关闭）

- D-06 / D-07 / D-08：M-01～M-05 手工通过（直角边框与按住拖出已二次修复后复验）。
- D-15：测量点对齐且 M-06 通过。
- 审查关闭记录见 [stage-0-review-issues.md](stage-0-review-issues.md)。

## 对阶段 1 的约束

- 阶段 1 沿用本表的系统版本、Bundle ID、工程布局及窗口行为契约，不再重新选型。
- 领域模型与 `ShelfWindowController` 正式实现时，可替换 Stage 0 原型类，但行为契约保持一致。
