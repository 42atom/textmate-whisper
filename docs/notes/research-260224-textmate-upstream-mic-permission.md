# TextMate 上游调研：麦克风权限声明与构建基线

## 结论先行
- 上游 `Applications/TextMate/Info.plist` 当前未包含 `NSMicrophoneUsageDescription`。
- 上游官方构建路径是 `./configure && ninja TextMate/run`。
- 你本机当前是 `Xcode 26.2 / clang 17`，未发现直接“版本过高”硬报错证据；当前实际阻塞是构建依赖缺失（`capnp`）。

## 证据
- Docs
  - `/tmp/textmate-upstream-inspect/README.md`
    - “After installing dependencies ... `./configure && ninja TextMate/run`”
    - “`ninja TextMate` # Build and sign TextMate”
- Code
  - `/tmp/textmate-upstream-inspect/Applications/TextMate/Info.plist`
    - 包含 `NSAppleEventsUsageDescription`、`NSContactsUsageDescription`，未见 `NSMicrophoneUsageDescription`。
  - `/tmp/textmate-upstream-inspect/default.rave`
    - `APP_MIN_OS` 与构建 flag 定义可见。
- Tests / Logs
  - 环境版本：
    - `xcodebuild -version` -> `Xcode 26.2 (17C52)`
    - `xcrun --sdk macosx --show-sdk-version` -> `26.2`
    - `clang --version` -> `Apple clang version 17.0.0`
  - 构建前检查：
    - `./configure` -> `*** dependency missing: ‘capnp’.`

## 受影响模块
- `Applications/TextMate/Info.plist`（权限声明）
- 构建工具链（Homebrew 依赖 + ninja 构建流程）

## 风险点
- 上游 Info.plist 结构变动会触发补丁冲突。
- 本地依赖不齐全会导致误判为“Xcode 不兼容”。

## 验证方式
- 先补齐依赖再执行构建。
- fork 产物首次录音时确认系统弹窗与 TCC 记录是否出现。
