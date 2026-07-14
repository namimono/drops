# Drops macOS Native

原生 Swift / AppKit 工程，是 Drops 后续唯一开发和发布入口。现有 Flutter 工程仅作行为与算法参考。

## 要求

- macOS 13.0+
- Xcode 16+
- 不依赖 Flutter

## 生成 / 打开工程

```bash
cd macos-native
xcodegen generate
open Drops.xcodeproj
```

若 `project.yml` 或源文件结构变更，重新执行 `xcodegen generate`。

## Stage 0 原型操作

> 当前状态（2026-07-14）：存在 [REV-S0-001](../docs/macos-native/stage-0-review-issues.md) 启动阻断缺陷。进程可以启动，但 `AppDelegate` 未被安装，状态栏与内容架浮窗不会创建。以下内容是修复后的预期操作方式，不是当前已验证结果。

修复启动入口后，应用应立刻弹出一个内容架浮窗；Dock 显示 **Drops**（Stage 0 为方便验证临时显示 Dock），菜单栏另有托盘图标可点开操作菜单。

| 菜单项 | 用途 |
|---|---|
| New Persistent Shelf | 主动内容架：预期可激活；当前另有 REV-S0-002 窗口类型问题待修复 |
| New Transient Shelf (No Activate) | 临时内容架：不抢源应用焦点 |
| Create Three Independent Shelves | 多窗口独立性 |
| Log Performance Benchmarks | 输出创建延迟样本与预算对照 |
| Close All Shelves | 关闭全部原型窗口 |
| Quit Drops | 退出应用 |

拖放验证：

1. 从 Finder 拖文件到内容架，确认接收日志 `[Stage0][DragIn]`。
2. 在内容架列表中选中项并双击开始拖出，放到 Finder / 其他应用。
3. 根据控制台 `[Stage0][DragOut] operation=` 识别 copy / move / cancel。

## 测试

```bash
cd macos-native
xcodegen generate
xcodebuild test -scheme Drops -destination 'platform=macOS' -quiet
```

## 文档

- [阶段方案](../docs/macos-native/README.md)
- [阶段 0 实施说明](../docs/macos-native/stage-0-requirements-and-validation.md)
- [开发进度](../docs/macos-native/development-progress.md)
- [阶段 0 审查问题清单](../docs/macos-native/stage-0-review-issues.md)
