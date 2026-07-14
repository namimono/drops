# 阶段 0 · 验证记录

> 更新日期：2026-07-14  
> 验收标准见：[stage-0-requirements-and-validation.md](stage-0-requirements-and-validation.md)

## 1. 自动化验证

| 命令 | 结果 | 说明 |
|---|---|---|
| `cd macos-native && xcodegen generate` | **通过** | 生成 `Drops.xcodeproj` |
| `xcodebuild -scheme Drops -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build` | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| `xcodebuild -scheme Drops -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build` | **通过** | `BUILD SUCCEEDED`（2026-07-14） |
| `xcodebuild test -scheme Drops -destination 'platform=macOS' -derivedDataPath build/DerivedData` | **通过** | `ManagedTemporaryFileStoreTests` 8/8，`TEST SUCCEEDED` |
| `otool -L …/Drops.app/Contents/MacOS/Drops` | **通过** | 无 Flutter 动态库链接 |

自动化结果的覆盖范围有限：现有 8 个原生测试只验证受管临时文件，不验证 AppDelegate、窗口显示、焦点或拖放。

## 2. 2026-07-14 运行审查

| 检查项 | 结果 | 证据 |
|---|---|---|
| 当前源码 Debug 构建 | **通过** | `BUILD SUCCEEDED` |
| 当前源码单测 | **通过** | `ManagedTemporaryFileStoreTests` 8/8 |
| Xcode 静态分析 | **通过** | `xcodebuild analyze` 成功 |
| 启动后窗口 | **失败 / P0** | Drops 进程存活，但 WindowServer 中没有 Drops 窗口 |
| AppKit 运行时状态 | **失败 / P0** | `NSApplication.shared.delegate == nil`；`NSApp.windows.count == 0` |

根因与修复条件见 [stage-0-review-issues.md](stage-0-review-issues.md) REV-S0-001。

## 3. 手工验证清单

| 编号 | 场景 | 步骤 | 期望 | 结果 |
|---|---|---|---|---|
| M-01 | 无边框浮窗 | 菜单 → New Persistent Shelf；切换浅色/深色 | 圆角浮层，无灰色直角底层 | **被 REV-S0-001 阻断** |
| M-02 | 临时窗不抢焦点 | 在其他应用开始拖拽后开 Transient Shelf | 源应用保持前台；可拖入 | **被 REV-S0-001 阻断；REV-S0-002 待修复** |
| M-03 | Finder 拖入 | 从 Finder 拖文件到架内 | 列表出现文件名；日志 DragIn | **被 REV-S0-001 阻断** |
| M-04 | 拖出 copy/move/cancel | 双击架内项拖到 Finder / 其他 App | 日志识别 operation | **被 REV-S0-001 阻断** |
| M-05 | 多窗口独立 | Create Three Independent Shelves，关闭其中一个 | 其余窗口仍在且内容保留 | **被 REV-S0-001 阻断** |
| M-06 | 性能样本 | 多次创建后 Log Performance Benchmarks | 输出 avg/p95 与预算对照 | **被 REV-S0-001 阻断；当前测量点无效** |

## 4. 性能预算与测量状态

| 指标 | 预算 | 当前状态 |
|---|---|---|
| 主动创建 → 首帧可见 | P95 < 300 ms | `show()` 前后只能测同步调用耗时；需改为真实首帧事件点 |
| 临时创建 → 可接收拖放 | P95 < 200 ms | `show()` 前后不能证明 drag-ready；需改为完成拖放准备的事件点 |

性能预算保留，`Stage0PerformanceMetrics` 的结束标记待 REV-S0-003 修复。修复前不得生成 PASS/OVER 验收结论。

## 5. S0 验收对照

| 编号 | 状态 | 证据 |
|---|---|---|
| S0-01 | **已实现** | [stage-0-scope.md](stage-0-scope.md) |
| S0-02 | **已实现** | [stage-0-decisions.md](stage-0-decisions.md) + `project.yml` |
| S0-03 | **已验证** | 本节第 1 节构建 / 测试 / otool |
| S0-04 | **被 P0 阻断** | REV-S0-001；当前无窗口 |
| S0-05 | **被 P0 阻断且存在实现偏差** | REV-S0-001 / REV-S0-002 |
| S0-06 | **代码存在，验证被阻断** | REV-S0-001；待 M-03 / M-04 |
| S0-07 | **代码存在，验证被阻断** | REV-S0-001；待 M-05 |
| S0-08 | **已验证** | 单测覆盖外部路径与 symlink 逃逸 |
| S0-09 | **预算已确认，测量实现无效** | REV-S0-003；修复后重做 M-06 |
| S0-10 | **未通过** | [stage-0-risks.md](stage-0-risks.md) 存在 P0/P1 未解决项 |
