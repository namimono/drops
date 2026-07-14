# 阶段 0 · 验证记录

> 更新日期：2026-07-14  
> 验收标准见：[stage-0-requirements-and-validation.md](stage-0-requirements-and-validation.md)

## 1. 自动化验证

| 命令 | 结果 | 说明 |
|---|---|---|
| `cd macos-native && xcodegen generate` | **通过** | 生成 `Drops.xcodeproj` |
| `xcodebuild -scheme Drops -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build` | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| `xcodebuild -scheme Drops -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build` | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| `xcodebuild test -scheme Drops -destination 'platform=macOS' -derivedDataPath build/DerivedData` | **通过** | 14/14：`ManagedTemporaryFileStoreTests` 8 + `Stage0LaunchAndWindowTests` 6 |
| `otool -L …/Drops.app/Contents/MacOS/Drops` | **通过** | 无 Flutter 动态库链接 |

## 2. 2026-07-14 运行审查与修复

| 检查项 | 结果 | 证据 |
|---|---|---|
| 启动后 AppDelegate | **已修复并验证** | `main.swift` 强持有；`testHostAppInstallsDelegate`；手工可见窗口 |
| 直角边框 / 灰底泄漏 | **已修复并复验通过** | 去掉 `.resizable`；透明 root + 圆角 VisualEffect + `invalidateShadow`；M-01 通过 |
| 拖出手势 | **已修复并复验通过** | `pasteboardWriterForRow` 按住拖出；M-04 通过 |

## 3. 手工验证清单

| 编号 | 场景 | 步骤 | 期望 | 结果 |
|---|---|---|---|---|
| M-01 | 无边框浮窗 | 菜单 → New Persistent Shelf；切换浅色/深色 | 圆角浮层，无灰色直角底层或外圈直角描边 | **通过**（二次修复后复验） |
| M-02 | 临时窗不抢焦点 | 在其他应用开始拖拽后开 Transient Shelf | 源应用保持前台；可拖入 | **通过** |
| M-03 | Finder 拖入 | 从 Finder 拖文件到架内 | 列表出现文件名；日志 DragIn | **通过** |
| M-04 | 拖出 copy/move/cancel | 选中后按住拖到 Finder / 其他 App | 日志识别 operation；不依赖双击 | **通过**（按住拖出复验） |
| M-05 | 多窗口独立 | Create Three Independent Shelves，关闭其中一个 | 其余窗口仍在且内容保留 | **通过** |
| M-06 | 性能样本 | 见下方步骤 | 输出 avg/p95 与预算对照 | **通过**；手工报告 **p95=78.7ms**（低于 300ms / 200ms 预算） |

### M-06 怎么测（建议步骤）

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

### M-06 采样结果（2026-07-14）

| 指标 | 预算 | 结果 |
|---|---|---|
| 创建路径 P95（手工报告） | < 300 ms / < 200 ms | **p95=78.7ms → PASS** |

测量口径见 D-15：结束点为 firstFrameVisible / dragReady。

## 4. 性能预算与测量状态

| 指标 | 预算 | 当前状态 |
|---|---|---|
| 主动创建 → 首帧可见 | P95 < 300 ms | **通过**（手工 p95=78.7ms） |
| 临时创建 → 可接收拖放 | P95 < 200 ms | **通过**（同上报告，低于预算） |

## 5. S0 验收对照

| 编号 | 状态 | 证据 |
|---|---|---|
| S0-01 | **已实现** | [stage-0-scope.md](stage-0-scope.md) |
| S0-02 | **已实现** | [stage-0-decisions.md](stage-0-decisions.md) + `project.yml` |
| S0-03 | **已验证** | 本节第 1 节构建 / 测试 / otool |
| S0-04 | **已验证（手工）** | M-01 通过 |
| S0-05 | **已验证（手工）** | M-02 通过 |
| S0-06 | **已验证（手工）** | M-03 / M-04 通过 |
| S0-07 | **已验证（手工+单测）** | M-05 通过 |
| S0-08 | **已验证** | 单测覆盖外部路径与 symlink 逃逸 |
| S0-09 | **已验证** | M-06 p95=78.7ms；测量口径见 D-15 |
| S0-10 | **已通过** | [stage-0-risks.md](stage-0-risks.md) 无未处理架构阻断项 |

## 6. 本轮问题结论（对照后续阶段文档）

| 现象 | 文档依据 | 归类 | 处理 |
|---|---|---|---|
| 直角外框 + 内嵌圆角 | S0-04、S1-07 | **实现 bug** | 已修；M-01 复验通过 |
| 双击才拖出 | S2-04 手势约定补全 | **原型实现偏差** | 已改按住拖出；M-04 复验通过 |
| M-06 不知如何测 | S0-09 / D-15 | **文档缺口** | 已补步骤；采样通过 |
