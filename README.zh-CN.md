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
- 录音状态指示（窗口标题前缀 `🔴 REC=<设备名> ⌥+⌘+F1 to stop` / `🪩 AI后处理...` + macOS 通知）
- 五条命令 + 快捷键
  - `Voice Dictation - Toggle Recording`（`Option+Command+F1`，主快捷键）
  - `Voice Dictation - Stop Recording`（`Option+Command+F2`，可选兜底）
  - `Whisper Voice - Enable/Disable AI Post-Edit`（`Control+Option+Command+D`，菜单会随状态切换）
  - `Whisper Voice - AI Output Language: <Auto|English|Chinese|Japanese|Korean>`（菜单命令，仅在启用 AI Post-Edit 时生效）
  - `Whisper Voice - Settings...`（菜单命令）
  - `Whisper Voice - Local Model Setup Guide`（菜单命令）
- 可选 OpenAI 兼容后修饰
- 一键安装/卸载脚本

## 依赖

- macOS（Apple Silicon，M1 及以上）
- TextMate 2
- Python 3.9+
- `ffmpeg`
- `mlx_whisper`（由 `mlx-whisper` 提供）

安装依赖：

```bash
brew install ffmpeg
python3 -m pip install -U mlx-whisper
```

检查命令：

```bash
python3 --version
command -v ffmpeg
command -v mlx_whisper
```

## 安装

```bash
git clone https://github.com/42atom/textmate-whisper.git
cd textmate-whisper
./scripts/install.sh
```

然后在 TextMate 执行：

- `Bundles -> Bundle Editor -> Reload Bundles`
- 首次使用（必做一次）：
  - `Bundles -> Whisper Voice -> Request Microphone Permission`
  - 保持 TextMate 在前台，触发一次录音，并在 macOS 弹窗中点 `Allow`
- 打开设置面板：
  - `Bundles -> Whisper Voice -> Whisper Voice - Settings...`
- 打开本地模型说明：
  - `Bundles -> Whisper Voice -> Whisper Voice - Local Model Setup Guide`
- 保存配置后让其生效：
  - `Bundles -> Bundle Editor -> Reload Bundles`
  - 如果仍未生效，重启 TextMate

## 卸载

```bash
cd textmate-whisper
./scripts/uninstall.sh
```

## 配置

使用 `~/.config/textmate-whisper/config.env`（由 `Whisper Voice - Settings...` 自动创建）。

### Whisper 与录音

```bash
TM_WHISPER_BIN=mlx_whisper
TM_FFMPEG_BIN=ffmpeg
TM_WHISPER_MODEL=mlx-community/whisper-large-v3-turbo
# 可选：本地模型路径示例
# TM_WHISPER_MODEL=/Users/<you>/Models/whisper-large-v3-turbo-mlx
TM_WHISPER_LANG=zh
TM_WHISPER_TASK=transcribe
TM_WHISPER_MAX_SEC=20
TM_WHISPER_FORCE_CPU=0
TM_WHISPER_RETRY_CPU_ON_CRASH=1
TM_WHISPER_INPUT_DEVICE=auto
TM_VOICE_SHOW_STATUS=1
TM_WHISPER_REC_BLINK_SEC=0.45
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

TM_VOICE_POSTPROCESS=auto
TM_VOICE_POST_OUTPUT_LANG=auto
# off|none: 关闭后处理
# auto: 仅当配置了 API key 时启用
# openai: 强制走后处理（API 失败会回退原始转写）
# 后处理输出语言：auto|en|zh|ja|ko
# 后处理上下文窗口：默认启用，光标前 200 字 + 后 200 字

TM_VOICE_POST_PROMPT=Punctuation-only pass: add/fix punctuation and spacing. Do not change words or meaning.
TM_VOICE_POST_SYSTEM_PROMPT=You are a strict transcript punctuation corrector. Only correct punctuation and spacing. Keep words, characters, order, and meaning unchanged. Do not paraphrase, summarize, rewrite, translate, or expand. Return only the corrected text.
```

可通过 `TM_VOICE_POSTPROCESS=off` 强制关闭后处理。
也可通过菜单命令 `Whisper Voice - Enable/Disable AI Post-Edit` 快速切换。
后处理输出语言也可通过菜单命令 `Whisper Voice - AI Output Language: ...` 直接选择（仅在启用后处理时生效）。
启用后处理时，会额外传递光标邻域上下文（前 200 字 + 后 200 字）以提升续写连贯性。

### 开始/结束录音流程

- 按 `Option+Command+F1` 开关录音（开始/结束）
- 可选兜底：按 `Option+Command+F2` 强制结束并写入文本
- 有选区时会替换选区，无选区时会在光标处插入
- 当 `TM_VOICE_SHOW_STATUS=1` 时，录音/转写中会显示窗口标题前缀 `🔴 REC=<设备名> ⌥+⌘+F1 to stop` / `🪩 AI后处理...`
- 可通过 `TM_WHISPER_REC_BLINK_SEC`（秒，默认 `0.45`）调整录音标题闪烁速度

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
  - 优先使用 `mlx-community/whisper-large-v3-turbo`（或本地 turbo 模型路径）
- TextMate 链路里出现 `mlx_whisper` traceback / 随机崩溃
  - 确认 `TM_WHISPER_RETRY_CPU_ON_CRASH=1`（默认开启）
  - 若仍不稳，设置 `TM_WHISPER_FORCE_CPU=1`，绕过 Metal 路径
  - 查看会话级诊断文件：`~/.cache/textmate-whisper/session-*/whisper.stderr`、`whisper.stdout`、`whisper-runtime.txt`
- 需要调试日志
  - `~/.cache/textmate-whisper/logs/voice_input-YYYYMMDD.log`
  - `~/.cache/textmate-whisper/logs/record_session-YYYYMMDD.log`
  - 可选重定向：`TM_WHISPER_LOG_DIR=/your/path`

### 标题栏错误码（`❌ ERR=...`）

当录音或转写失败时，窗口标题会显示简短错误码，方便快速定位问题。

| 错误码 | 含义 | 首要检查项 |
| --- | --- | --- |
| `device-config` | `TM_WHISPER_INPUT_DEVICE` 配置值非法或不受支持 | 运行 `./scripts/list_input_devices.sh`，改为有效 `:N` 或 `auto` |
| `start-failed` | `ffmpeg` 录音进程启动失败 | 检查麦克风权限与 `TM_FFMPEG_BIN` |
| `state-broken` | 当前会话状态文件损坏或字段不完整 | 重新开始一轮录音 |
| `audio-missing` | 停止时找不到录音文件 | 重试录音并检查会话目录 |
| `too-short` | 录音时长/体积低于阈值 | 延长按住录音时间并连续说话 |
| `audio-empty` | 音频文件存在但内容为空 | 检查输入设备是否正确、有无麦克风信号 |
| `silent` | 音频有数据但峰值接近静音 | 确认输入设备、系统输入音量与权限 |
| `transcribe` | `voice_input.sh` 转写阶段失败 | 查看 `~/.cache/textmate-whisper/session-*` 下的 `whisper.stderr` |

## 开发校验

```bash
./scripts/smoke.sh
```

`smoke.sh` 包含语法检查与 `voice_input.sh --dry-run` 逻辑路径校验。

## 发布（已编译 App）

将可下载的 `TextMate-Whisper.app` 推送到 GitHub Release：

```bash
chmod +x ./scripts/release.sh
TAG=v0.2.1 ./scripts/release.sh
```

默认行为：
- 自动读取 App 路径（优先顺序）：
  - `~/Desktop/textmate-whisper-build/TextMate-Whisper.app`（优先）
  - 回退：`~/Desktop/textmate-whisper-build/TextMate.app`
- 生成压缩包：`dist/TextMate-whisper-macos-universal-<tag>.zip`
- 同时上传 `SHA256` 校验文件。

如需覆盖仓库或 App 路径：

```bash
REPO=owner/repo APP_PATH=/path/to/TextMate-Whisper.app TAG=v0.2.1 ./scripts/release.sh
```

## 许可证

MIT
