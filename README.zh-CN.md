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
- 四条命令 + 快捷键
  - `Voice Dictation - Insert`（`Option+Command+D`）
  - `Voice Dictation - Replace Selection`（`Shift+Option+Command+D`）
  - `Voice Dictation - Preview Draft`（`Control+Option+Command+D`）
  - `Voice Dictation - Insert + AI Prompt...`（`Option+Command+G`）
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
cd /Users/admin/GitProjects/textmate-whisper
./scripts/install.sh
```

然后在 TextMate 执行：

- `Bundles -> Bundle Editor -> Reload Bundles`

## 卸载

```bash
cd /Users/admin/GitProjects/textmate-whisper
./scripts/uninstall.sh
```

## 配置

在 `~/.tm_properties`（或项目 `.tm_properties`）中设置。

### Whisper 与录音

```properties
TM_WHISPER_BIN = mlx_whisper
TM_FFMPEG_BIN = ffmpeg
TM_WHISPER_MODEL = mlx-community/whisper-small
TM_WHISPER_LANG = zh
TM_WHISPER_TASK = transcribe
TM_WHISPER_MAX_SEC = 20
TM_WHISPER_INPUT_DEVICE = :0
```

### 可选 OpenAI 兼容后修饰

```properties
TM_OAI_BASE_URL = https://api.openai.com/v1
TM_OAI_API_KEY = sk-...
TM_OAI_MODEL = gpt-4o-mini
TM_OAI_TIMEOUT_SEC = 45

TM_VOICE_POST_PROMPT = Polish this transcript into concise writing.
TM_VOICE_POST_SYSTEM_PROMPT = You are a writing assistant. Improve punctuation and readability while preserving meaning. Return only the rewritten text.
```

开启后修饰需要：

```properties
TM_VOICE_POSTPROCESS = openai
```

其中 `Voice Dictation - Insert + AI Prompt...` 会自动开启并弹出指令输入框。

## 实现说明

- Bundle 安装路径：
  - `~/Library/Application Support/TextMate/Bundles/Whisper Voice.tmbundle`
- 四条命令统一调用：
  - `Support/bin/voice_input.sh`
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
  - 检查 `TM_WHISPER_INPUT_DEVICE`（默认 `:0`）
- 结果为空
  - 增加 `TM_WHISPER_MAX_SEC`
  - 换更大模型（如 `mlx-community/whisper-medium`）

## 开发校验

```bash
./scripts/smoke.sh
```

## 许可证

MIT
