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

## Stage 1 操作

应用启动后弹出一个持久内容架；Dock 显示 **Drops**，菜单栏有托盘图标。默认全局快捷键 **⌘⌥Space** 在鼠标附近新建持久内容架。

| 菜单项 | 用途 |
|---|---|
| New Shelf | 主动持久内容架（可激活） |
| New Transient Shelf (Demo) | 临时内容架 Demo（不抢焦点）；点 **Simulate Drop** 可晋升 |
| Create Three Shelves | 多窗口独立性 |
| Log Performance Benchmarks | 输出创建延迟样本 |
| Close All Shelves | 关闭全部内容架 |
| Quit Drops | 退出应用 |

骨架按钮：

- **Simulate Drop**：模拟接收一项内容（空→收起；临时架晋升为持久）
- **Expand / Collapse**：在收起态与展开态之间切换
- **Close**：关闭当前内容架

第 21 个内容架会被拒绝，并伴随系统提示音。

> `Drops/Prototype/` 为阶段 0 历史原型，已从编译 Target 排除。

## 测试

```bash
cd macos-native
xcodegen generate
xcodebuild test -scheme Drops -destination 'platform=macOS' -quiet
```

## 文档

- [阶段方案](../docs/macos-native/README.md)
- [阶段 1 实施说明](../docs/macos-native/stage-1-shelf-domain-and-window.md)
- [开发进度](../docs/macos-native/development-progress.md)
