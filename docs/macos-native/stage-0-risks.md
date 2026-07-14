# 阶段 0 · 技术风险与结论

> 更新日期：2026-07-14  
> 对应阶段：[需求冻结与技术验证](stage-0-requirements-and-validation.md)

| 编号 | 风险 | 验证方式 | 结论 | 处理 |
|---|---|---|---|---|
| R-01 | 无边框浮窗出现灰色直角/系统背景泄漏 | `NSPanel` + VisualEffect + layer cornerRadius | **被 P0 阻断** | 当前无窗口，浅色/深色尚未验证；待 REV-S0-001 修复后执行 M-01 |
| R-02 | 临时窗抢走拖拽源焦点导致拖放中断 | `.nonactivatingPanel` + 不调用 `activate` | **实现偏差，待修复** | persistent/transient 当前都带 `.nonactivatingPanel`；见 REV-S0-002 |
| R-03 | Finder / 第三方应用拖入拖出不可靠 | file URL destination + dragging session source | **代码已实现，验证被阻断** | 待 REV-S0-001 修复后执行 M-03/M-04，不再视为原型通过 |
| R-04 | 多窗口关闭互相影响或进程异常 | 多 `ShelfPanelController` 独立持有 | **代码已实现，验证被阻断** | 待 REV-S0-001 修复后执行 M-05，不再视为原型通过 |
| R-05 | 清理误删用户原始文件或符号链接逃逸 | 单元测试覆盖外部路径与 symlink | **通过** | `validateManagedURL` 拒绝逃逸；测试见 `ManagedTemporaryFileStoreTests` |
| R-06 | 使用系统临时目录导致提前丢失 | 决策写入 Application Support | **通过（方案）** | 见决策 D-09 |
| R-07 | 最低系统版本过高/过低 | 工程 `MACOSX_DEPLOYMENT_TARGET=13.0` | **接受限制** | 仅支持 macOS 13+；不维护更旧版本 |
| R-08 | 签名/公证阻塞阶段 0 | Debug/Release 本地构建 | **接受限制** | 发布签名留阶段 5；不构成架构阻断 |
| R-09 | App Sandbox 与拖放书签复杂度 | 阶段 0 关闭 Sandbox | **接受限制** | 发布前再启用；不改变领域与窗口方案 |
| R-10 | 性能不达标 | Stage0 指标采样器 | **测量实现无效** | 当前只统计 `show()` 同步耗时；待 REV-S0-003 修复后再采集 M-06 |
| R-11 | 重写范围过大 | 分阶段交付 | **通过（流程）** | 阶段 0 只做骨架与验证，不交付日用版本 |
| R-12 | Flutter 残留依赖 | Target 源码与链接检查 | **通过** | `macos-native` 无 Flutter import / Pod |
| R-13 | AppDelegate 未安装导致应用无窗口 | 实际启动 + LLDB / WindowServer 检查 | **P0，待修复** | `NSApp.delegate == nil`、`NSApp.windows.count == 0`；见 REV-S0-001 |
| R-14 | 启动和窗口回归缺少自动化保护 | 原生测试范围核对 | **P1，待补测试** | 现有 8 个测试仅覆盖 `ManagedTemporaryFileStore`；见 REV-S0-004 |

## 阶段评审结论

- **存在未处理的 P0 启动阻断项 R-13。**
- R-01～R-04 的窗口与拖放结论尚未通过运行验证；R-02 另有已确认的实现偏差。
- R-10 必须先修正测量事件点，当前样本不能用于验收。
- 阶段 0 暂不满足退出条件；修复 [问题清单](stage-0-review-issues.md) 并完成 M-01～M-06 后重新评审，评审通过前不进入阶段 1。
