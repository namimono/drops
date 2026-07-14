# 阶段 0 · 技术风险与结论

> 更新日期：2026-07-14  
> 对应阶段：[需求冻结与技术验证](stage-0-requirements-and-validation.md)

| 编号 | 风险 | 验证方式 | 结论 | 处理 |
|---|---|---|---|---|
| R-01 | 无边框浮窗出现灰色直角/系统背景泄漏 | `NSPanel` + VisualEffect + layer cornerRadius | **通过（手工）** | 二次修复后 M-01 通过 |
| R-02 | 临时窗抢走拖拽源焦点导致拖放中断 | `.nonactivatingPanel` + 不调用 `activate` | **通过（手工）** | M-02 通过 |
| R-03 | Finder / 第三方应用拖入拖出不可靠 | file URL destination + dragging session source | **通过（手工）** | M-03 / M-04 通过（按住拖出） |
| R-04 | 多窗口关闭互相影响或进程异常 | 多 `ShelfPanelController` 独立持有 | **通过（手工+单测）** | M-05 通过 |
| R-05 | 清理误删用户原始文件或符号链接逃逸 | 单元测试覆盖外部路径与 symlink | **通过** | `validateManagedURL` 拒绝逃逸；测试见 `ManagedTemporaryFileStoreTests` |
| R-06 | 使用系统临时目录导致提前丢失 | 决策写入 Application Support | **通过（方案）** | 见决策 D-09 |
| R-07 | 最低系统版本过高/过低 | 工程 `MACOSX_DEPLOYMENT_TARGET=13.0` | **接受限制** | 仅支持 macOS 13+；不维护更旧版本 |
| R-08 | 签名/公证阻塞阶段 0 | Debug/Release 本地构建 | **接受限制** | 发布签名留阶段 5；不构成架构阻断 |
| R-09 | App Sandbox 与拖放书签复杂度 | 阶段 0 关闭 Sandbox | **接受限制** | 发布前再启用；不改变领域与窗口方案 |
| R-10 | 性能不达标 | Stage0 指标采样器 | **通过（手工）** | M-06 报告 p95=78.7ms，低于预算 |
| R-11 | 重写范围过大 | 分阶段交付 | **通过（流程）** | 阶段 0 只做骨架与验证，不交付日用版本 |
| R-12 | Flutter 残留依赖 | Target 源码与链接检查 | **通过** | `macos-native` 无 Flutter import / Pod |
| R-13 | AppDelegate 未安装导致应用无窗口 | 实际启动 + 宿主单测 | **已修复并通过** | `main.swift` 强持有；手工窗口可见 |
| R-14 | 启动和窗口回归缺少自动化保护 | 原生测试范围核对 | **已补测试** | `Stage0LaunchAndWindowTests` 6 例 |

## 阶段评审结论

- S0-01～S0-10 均已满足；R-01～R-14 均有「通过 / 接受限制 / 已修复」结论，无未处理架构阻断项。
- 接受限制项（R-07～R-09）不阻塞阶段 1：系统版本、发布签名与 Sandbox 已明确留给后续阶段。
- **阶段 0 可退出；允许进入阶段 1。**
