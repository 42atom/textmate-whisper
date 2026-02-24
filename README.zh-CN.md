# textmate-whisper

[English](README.md) | [中文](README.zh-CN.md)

基于 `mlx_whisper` 的 TextMate 本地语音输入增强，并支持可选的 OpenAI 兼容 API 后修饰。

## 目标

让 TextMate 具备“录音 -> 转写 -> 插入/替换”的高效写作能力，同时保持轻量和可控：

- 默认本地转写
- 可选云端后修饰
- 不改 TextMate 核心

## 功能

- 本地 Whisper-MLX 转写（命令：`mlx_whisper`）
- 录音状态指示（窗口标题前缀 `🔴 REC=<设备名>` / `🟡 AI...` + macOS 通知）
- 八条命令 + 快捷键
  - `Voice Dictation - Start Recording`（`Option+Command+F1`）
  - `Voice Dictation - Stop Recording + Insert`（`Shift+Option+Command+F1`）
  - `Voice Dictation - Insert`（`Option+Command+D`）
  - `Voice Dictation - Replace Selection`（`Shift+Option+Command+D`）
  - `Voice Dictation - Preview Draft`（`Control+Option+Command+D`）
  - `Voice Dictation - Insert + AI Prompt...`（`Option+Command+G`）
  - `Whisper Voice - Settings...`（菜单命令）
  - `Whisper Voice - Local Model Setup Guide`（菜单命令）
- 可选 OpenAI 兼容后修饰
- 一键安装/卸载脚本

## 依赖

- macOS
- TextMate 2
- `ffmpeg`
- `mlx_whisper`

检查命令：

```bash
command -v ffmpeg
command -v mlx_whisper
```

## 安装

```bash
cd <path-to>/textmate-whisper
./scripts/install.sh
```

然后在 TextMate 执行：

- `Bundles -> Bundle Editor -> Reload Bundles`
- 打开设置面板：
  - `Bundles -> Whisper Voice -> Whisper Voice - Settings...`
- 打开本地模型说明：
  - `Bundles -> Whisper Voice -> Whisper Voice - Local Model Setup Guide`
- 保存配置后让其生效：
  - `Bundles -> Bundle Editor -> Reload Bundles`
  - 如果仍未生效，重启 TextMate

## 卸载

```bash
cd <path-to>/textmate-whisper
./scripts/uninstall.sh
```

## 配置

使用 `~/.config/textmate-whisper/config.env`（由 `Whisper Voice - Settings...` 自动创建）。

### Whisper 与录音

```bash
TM_WHISPER_BIN=mlx_whisper
TM_FFMPEG_BIN=ffmpeg
TM_WHISPER_MODEL=mlx-community/whisper-tiny
TM_WHISPER_LANG=zh
TM_WHISPER_TASK=transcribe
TM_WHISPER_MAX_SEC=20
TM_WHISPER_INPUT_DEVICE=auto
TM_VOICE_SHOW_STATUS=1
```

建议先查看可用设备：

```bash
./scripts/list_input_devices.sh
```

`auto` 的选择优先级：

- 耳机/外接麦克风
- 内置麦克风
- iPhone 连续互通麦克风
- 其余首个可用设备（兜底）

如果要固定设备号，再设置：

```bash
TM_WHISPER_INPUT_DEVICE=:1
```

### 可选 OpenAI 兼容后修饰

```bash
TM_OAI_BASE_URL=https://api.openai.com/v1
TM_OAI_API_KEY=sk-...
TM_OAI_MODEL=gpt-4o-mini
TM_OAI_TIMEOUT_SEC=45

TM_VOICE_POST_PROMPT=Polish this transcript into concise writing.
TM_VOICE_POST_SYSTEM_PROMPT=You are a writing assistant. Improve punctuation and readability while preserving meaning. Return only the rewritten text.
```

开启后修饰需要：

```bash
TM_VOICE_POSTPROCESS=openai
```

其中 `Voice Dictation - Insert + AI Prompt...` 会自动开启并弹出指令输入框。

### 开始/结束录音流程

- 按 `Option+Command+F1` 开始录音
- 按 `Shift+Option+Command+F1` 结束录音并插入文本
- 当 `TM_VOICE_SHOW_STATUS=1` 时，录音/转写中会显示窗口标题前缀 `🔴 REC=<设备名>` / `🟡 AI...`

## 实现说明

- Bundle 安装路径：
  - `~/Library/Application Support/TextMate/Bundles/Whisper Voice.tmbundle`
- 命令统一调用入口：
  - `Support/bin/bootstrap.sh`
- 运行时共享工具库：
  - `Support/bin/_common.sh`
- OpenAI 后修饰是可选项，失败会自动回退到原始转写文本。
- PRD 文档：
  - `docs/PRD-TextMate-Whisper-Voice-Input-v1.0.md`

## 排障

- `ffmpeg not found`
  - 安装 ffmpeg 或设置 `TM_FFMPEG_BIN`
- `mlx_whisper not found`
  - 安装 whisper-mlx 或设置 `TM_WHISPER_BIN`
- 录音失败
  - 检查麦克风权限（系统设置 -> 隐私与安全性 -> 麦克风）
  - 运行 `./scripts/list_input_devices.sh` 检查可用设备与索引
  - 不需要固定索引时可用 `TM_WHISPER_INPUT_DEVICE=auto`
- 结果为空
  - 增加 `TM_WHISPER_MAX_SEC`
  - 换更大模型（如 `mlx-community/whisper-medium`）
- 需要调试日志
  - `~/.cache/textmate-whisper/logs/voice_input-YYYYMMDD.log`
  - `~/.cache/textmate-whisper/logs/record_session-YYYYMMDD.log`
  - 可选重定向：`TM_WHISPER_LOG_DIR=/your/path`

## 开发校验

```bash
./scripts/smoke.sh
```

`smoke.sh` 包含语法检查与 `voice_input.sh --dry-run` 逻辑路径校验。

## 许可证

MIT
