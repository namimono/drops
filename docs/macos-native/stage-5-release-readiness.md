# 阶段 5：发布准备

> 状态：待实施（前置：[阶段 4 产品打磨](stage-4-product-polish.md) 封版后方可启动）  
> 上级文档：[macOS 原生方案](README.md)  
> 前置阶段：[阶段 4：产品打磨](stage-4-product-polish.md)

## 1. 阶段定位

本阶段不扩展产品功能，而是验证原生版本在真实环境中的稳定性、性能、升级安全和发布完整性，并完成从 Flutter/Windows 构建体系到单一 macOS 原生产品的收口。

## 2. 实现目标

- 对全部在范围内的核心场景进行发布级回归。
- 验证性能、资源占用、长时间运行和复杂系统环境下的稳定性。
- 完成签名、公证、权限、更新和安装升级链路。
- 安全迁移设置和旧临时内容，保证任何情况下不误删用户原始文件。
- 使仓库的正式构建和发布流程只产出 macOS 原生应用。

## 3. 范围

### 3.1 本阶段包含

- 全量功能、交互、多语言和数据安全回归（不含已移出范围的媒体压缩）。
- 性能、压力、内存、睡眠唤醒、多屏和无障碍验证。
- Bundle ID、签名、Entitlements、公证和 Sparkle 更新配置。
- 干净安装、覆盖升级、设置迁移和旧临时文件迁移。
- Flutter 与 Windows 构建、打包和发布入口清理。
- 发布清单、已知问题和回滚方案评审。

### 3.2 本阶段不包含

- 新增产品能力或扩大产品范围。
- 图片/视频压缩或任何媒体处理入口。
- Windows 兼容、构建或发布。
- 未经阶段回退重新验收的重大架构调整。

## 4. 阶段交付物

- 全量回归、性能、压力、内存和环境兼容性报告。
- 可签名、公证、安装和更新的原生 macOS 发布包。
- 设置与旧临时文件迁移报告及回滚方案。
- 单一原生工程的构建与发布流水线。
- 经评审签署的发布清单和已知问题清单。

## 5. 验收标准

| 编号 | 验收标准 | 验收证据 |
|---|---|---|
| S5-01 | 阶段 0–4 的全部退出条件及 PRD 9.1、9.2、9.4、9.5 核心场景完成发布候选版本回归；产品中不存在图片/视频压缩入口。 | 全量回归报告 |
| S5-02 | 主动创建内容架到首帧可见 P95 小于 300 ms；摇动触发到窗口可接收拖放 P95 小于 200 ms。 | 统一环境下的性能报告 |
| S5-03 | 20 个空内容架同时存在时无持续高 CPU 占用，空内容架不会启动无关重任务。 | CPU 与任务采样报告 |
| S5-04 | 快速重复创建/关闭、展开/收起、拖入/拖出、取消和清理操作时，无崩溃、死锁或不可恢复状态。 | 压力测试报告 |
| S5-05 | 长时间运行、睡眠唤醒、显示器插拔、切换缩放比例、浅色/深色切换和应用重新激活后功能正常。 | 稳定性与环境测试记录 |
| S5-06 | 内存和资源检查不存在会随重复操作持续增长的严重泄漏，窗口关闭后关联资源能够释放。 | Instruments 或等效检查报告 |
| S5-07 | 英文、简体中文和不支持语言环境下的全部核心页面、菜单、错误和确认文案通过最终验收。 | 本地化验收报告 |
| S5-08 | 键盘操作、焦点和 VoiceOver 基础检查通过，不存在阻断核心流程的无障碍问题。 | 无障碍验收记录 |
| S5-09 | Release 应用使用正式 Bundle ID，可完成签名和公证；Entitlements 与实际能力一致，不申请无关权限。 | 签名、公证和权限检查结果 |
| S5-10 | 干净安装、从支持的旧版本升级和 Sparkle 更新链路均成功，应用身份、用户设置和快捷键迁移符合预期。 | 安装与升级矩阵报告 |
| S5-11 | 旧临时文件迁移仅处理已确认的受管内容；迁移、清理或回滚均不会删除用户原始文件，失败时可安全恢复。 | 迁移与故障注入测试 |
| S5-12 | 正式构建、打包和发布流程仅产出 macOS 原生应用，不依赖 Flutter 或 Windows 工具链。 | CI/发布流水线记录 |
| S5-13 | 发布候选版本连续日常试用期间不存在阻断性的窗口、拖放或数据安全问题。 | 试用记录与缺陷清单 |
| S5-14 | 所有 P0/P1 缺陷已关闭；其余已知问题有明确影响、规避方案和后续计划，并经发布评审接受。 | 缺陷报告与发布评审结论 |

## 6. 准入条件

- 阶段 4 需求池已收敛，产品确认封版。
- 产品功能范围冻结，发布阶段不再加入新需求（缺陷修复除外）。
- 正式签名、公证、更新服务和目标系统测试环境可用。
- 已明确需要支持的旧版本及迁移来源。

## 7. 退出条件

- S5-01 至 S5-14 全部通过。
- 发布清单、回归报告、迁移方案和回滚方案均完成评审。
- 原生版本满足签名、公证、更新和分发要求。
- 仓库正式流程只产出 macOS 原生应用，版本可以发布。

## 8. PRD 映射与后续依赖

本阶段覆盖 PRD 第 9 章中仍在产品范围内的核心验收场景（9.1、9.2、9.4、9.5），并落实原生方案的性能、测试和发布条件。PRD 9.3（图片/视频处理）已移出范围，不纳入发布验收。通过本阶段即代表首个 macOS 原生版本达到发布标准；未通过的条目必须回退到对应阶段修复并重新回归。

## 9. 发布接入点规划（阶段 3 预埋）

以下接入点在阶段 3 已明确位置与切换顺序，阶段 5 只改配置与流水线，不重做产品功能。

### 9.1 App Sandbox

| 项 | 现状 | 阶段 5 动作 |
|---|---|---|
| Entitlements 文件 | `macos-native/Drops/Support/Drops.entitlements` | 将 `com.apple.security.app-sandbox` 改为 `true` |
| XcodeGen 镜像 | `project.yml` → `targets.Drops.entitlements.properties` | 与 entitlements 文件同步为 sandbox 开启 |
| 临时文件根 | Application Support / `TemporaryContent` | Sandbox 下自然落入容器；验证清理与跨架引用仍成立 |
| 拖放 / 书签 | 阶段 0–4 关闭 Sandbox 以降低噪声 | 开启后补齐 security-scoped bookmark：外部文件拖入、Reveal、跨重启引用（若需要持久访问） |
| 验证 | — | 拖入 Finder 文件、拖出到 Finder/第三方、粘贴物化、手动清理安全边界全量回归 |

### 9.2 Developer ID 签名

| 项 | 现状 | 阶段 5 动作 |
|---|---|---|
| Bundle ID | `click.shakepin.macos`（`project.yml` / Info.plist） | 确认与 Apple Developer 登记一致，作为发布唯一身份 |
| Team / 签名样式 | `DEVELOPMENT_TEAM=""`，`CODE_SIGN_STYLE=Automatic` | CI/本机注入正式 Team ID；Release 使用 Developer ID Application 证书 |
| Hardened Runtime | `ENABLE_HARDENED_RUNTIME=YES`（已开） | 保持开启；按需核对 entitlements 与实际能力一致 |
| 构建入口 | `macos-native/Drops.xcodeproj` + scheme `Drops` | Archive → Developer ID 签名的 `.app`；禁止再走 Flutter Runner |

### 9.3 公证（Notarization）

| 项 | 现状 | 阶段 5 动作 |
|---|---|---|
| 打包形态 | 本地 Debug/Release 即可运行 | 导出 Developer ID 签名 app → `ditto` zip 或产品 pkg/dmg |
| 公证命令 | 未接入 | `xcrun notarytool submit … --wait`，成功后 `xcrun stapler staple` |
| 凭据 | — | App Store Connect API Key 或钥匙串 App 专用密码；仅存 CI secrets |
| 验收 | — | 干净 Mac 下载后 Gatekeeper 直接打开；对应 S5-09 |

### 9.4 建议实施顺序

1. 冻结 Bundle ID 与版本号规则（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）。
2. 在独立分支启用 Sandbox，修 bookmark / 拖放权限问题，再合入发布候选。
3. 配置 Developer ID + Hardened Runtime 的 Archive 流水线。
4. 接入 notarytool + stapler，将产物挂到现有分发/Sparkle 更新通道（S5-10）。
5. 用发布候选包跑 S5-01～S5-14，再清理 Flutter/Windows 发布入口（S5-12）。
