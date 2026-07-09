# ShakePin 本地构建说明

本文档说明如何在本机编译并运行 ShakePin（macOS）。

## 环境要求

- macOS
- [Flutter](https://docs.flutter.dev/get-started/install/macos)（建议 stable）
- Xcode（含 Command Line Tools）
- CocoaPods（`pod` 可用）

当前验证过的环境示例：

```text
Flutter 3.44.x (stable)
Dart 3.12.x
Xcode 16.x
```

检查环境：

```bash
flutter doctor
flutter --version
```

## 为什么要用 `oss` flavor

本仓库有两套签名配置：

| Flavor / Configuration | Bundle ID | 签名 | 适用场景 |
|---|---|---|---|
| 默认 `Debug` / `Release` | `click.shakepin.macos` | 需要 Apple Development 证书 + Provisioning Profile | 正式开发者账号签名 |
| `oss`（`Debug-oss` / `Release-oss`） | `click.shakepin.macos.oss` | 免签名 / ad-hoc | **本地验证、开源构建（推荐）** |

如果本机没有有效的 Apple 开发者证书，直接跑：

```bash
flutter build macos --debug
```

会报类似错误：

```text
No profiles for 'click.shakepin.macos' were found
```

本地日常验证请统一使用 `--flavor oss`。

---

## 一、首次准备

在项目根目录执行：

```bash
cd /path/to/shakepin

# 拉取 Dart 依赖
flutter pub get

# 生成 OSS licenses（setup.sh 内容）
sh ./setup.sh
```

`setup.sh` 实际执行的是：

```bash
dart run flutter_oss_licenses:generate
```

---

## 二、日常开发：热重载运行

最常用，改完 Dart 代码可热重载：

```bash
sh ./ruoss.sh
```

等价于：

```bash
sh ./setup.sh
flutter run -d macos --flavor oss
```

Release 模式直接跑（无热重载，更接近正式包）：

```bash
sh ./ruross.sh
```

等价于：

```bash
sh ./setup.sh
flutter run -d macos --release --flavor oss
```

---

## 三、只编译、不自动 run（推荐验证原生改动）

改了 `macos/Runner/*.swift`（例如 `DropTarget.swift`）时，建议先 build 再手动打开 app。

### Debug 包（本次验证用的方式）

```bash
flutter build macos --debug --flavor oss
```

成功后产物：

```text
build/macos/Build/Products/Debug-oss/ShakePin.app
```

打开：

```bash
open build/macos/Build/Products/Debug-oss/ShakePin.app
```

### Release 包

```bash
# 方式 A：用仓库脚本
sh ./buildoss.sh

# 方式 B：手动
sh ./setup.sh
flutter build macos --release --flavor oss
```

成功后产物：

```text
build/macos/Build/Products/Release-oss/ShakePin.app
```

打开：

```bash
# 方式 A
sh ./openbuild.sh

# 方式 B
open build/macos/Build/Products/Release-oss/ShakePin.app
```

一键「编译 Release + 打开」：

```bash
sh ./reloss.sh
```

---

## 四、常用命令速查

| 目的 | 命令 |
|---|---|
| 开发运行（Debug + 热重载） | `sh ./ruoss.sh` |
| Release 模式运行 | `sh ./ruross.sh` |
| 只编 Debug 包 | `flutter build macos --debug --flavor oss` |
| 只编 Release 包 | `sh ./buildoss.sh` |
| 打开刚编好的 Release 包 | `sh ./openbuild.sh` |
| 编 Release 并打开 | `sh ./reloss.sh` |
| 打开 Xcode 工程 | `sh ./openmac.sh` |
| 生成 licenses | `sh ./setup.sh` |

---

## 五、验证临时文件路径改动时

改完 `macos/Runner/DropTarget.swift` 后：

```bash
flutter build macos --debug --flavor oss
open build/macos/Build/Products/Debug-oss/ShakePin.app
```

然后拖入文本 / 图片，预期临时文件类似：

```text
.../T/<UUID>/文字档.txt
.../T/<UUID>/图片.png
.../T/<UUID>/网页.html
```

而不是旧的：

```text
.../T/temp_file_<UUID>.html
```

---

## 六、常见问题

### 1. `No profiles for 'click.shakepin.macos'`

原因：没用 `oss` flavor，走了需要开发者证书的默认配置。

解决：加上 `--flavor oss`。

### 2. 改了 Swift，但 `flutter run` 看起来没生效

原生代码不会被 Dart 热重载覆盖。请：

1. 停掉当前运行中的 app
2. 重新 `flutter build macos --debug --flavor oss` 或重新 `flutter run -d macos --flavor oss`
3. 再打开新产物验证

### 3. 想用 Xcode 直接编

```bash
sh ./openmac.sh
# 或
open macos/Runner.xcworkspace
```

在 Xcode 里选择 scheme：`oss`，configuration：`Debug-oss` 或 `Release-oss`。

---

## 七、产物目录结构（摘要）

```text
build/macos/Build/Products/
├── Debug-oss/
│   └── ShakePin.app          # 本地调试验证用
└── Release-oss/
    └── ShakePin.app          # 更接近正式发布的本地包
```
