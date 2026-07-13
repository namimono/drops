# 多收集框故障排查

## 架构速览

- **AppHost**（隐藏 `MainFlutterWindow`）：菜单栏、快捷键、设置、自动更新
- **ShelfManager**：收集框生命周期唯一权威
- **ShelfWindow + WindowRuntime**：每窗独立 Flutter Engine（入口 `shelfMain`）
- **GlobalInputCoordinator**：拖放周期与晃动检测

## 常见问题

### 创建收集框：`Could not resolve main entrypoint function`
- 原因：macOS `FlutterEngine.run(withEntrypoint:)` **只能**解析与 `main()` 同一 Dart 库中的入口
- `shelfMain` 必须定义在 `lib/main.dart`（不要放在 `lib/shelf/shelf_main.dart`）
- 失败时还会出现 `Could not create root isolate` / `Communicating on a dead channel`

### Shelf：`MissingPluginException` on `click.shakepin.macos/settings`
- 每个 Shelf Engine 的 `WindowRuntime` 必须注册 settings channel（读写走 `SettingsBridge` / UserDefaults）
- 宿主不再跑 CLI 探测；CLI 自动发现与可用性检查只在 shelf bootstrap 执行

### 快捷键无反应
1. 检查辅助功能权限（全局鼠标/快捷键）
2. 查看日志 `[HOTKEY]` / `[SHELF] created`
3. 是否已达 20 窗上限（会 beep）

### 晃动框立刻消失
1. 确认是否真正落入窗口（`performDragOperation` → `[SHELF] dropAccepted`）
2. mouseUp 与 drop 时序：Manager 在 50ms 后结束 drag session
3. 拖到其他已有窗不会持久化晃动框

### 关闭后崩溃 / 迟到回调
- 关闭走 `closeSelf` → `ShelfManager.closeShelf` → runtime dispose → engine shutdown
- Channel handler 在 dispose 时解绑；`shouldIgnore` 过滤 closing/closed

### 设置变更无效
- Settings 只绑宿主 Engine；`SettingsBridge` → `AppHostController.handleSettingChange`
