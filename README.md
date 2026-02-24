# textmate-whisper

[English](README.md) | [中文](README.zh-CN.md)

Local voice dictation for TextMate using `mlx_whisper`, with optional OpenAI-compatible post-editing.

## Why

TextMate is lightweight and fast, but it has no built-in speech-to-text workflow. This project adds a production-ready bundle that keeps the workflow local-first:

- Record from microphone
- Transcribe with local Whisper MLX
- Insert/replace/preview in TextMate
- Optionally run post-edit polishing through any OpenAI-compatible API

## Features

- Local transcription via `mlx_whisper` (default)
- Recording status indicator (window title prefix `🔴 REC=<device>` / `🟡 AI...` + macOS notifications)
- Eight commands with keyboard shortcuts
  - `Voice Dictation - Start Recording` (`Option+Command+F1`)
  - `Voice Dictation - Stop Recording + Insert` (`Shift+Option+Command+F1`)
  - `Voice Dictation - Insert` (`Option+Command+D`)
  - `Voice Dictation - Replace Selection` (`Shift+Option+Command+D`)
  - `Voice Dictation - Preview Draft` (`Control+Option+Command+D`)
  - `Voice Dictation - Insert + AI Prompt...` (`Option+Command+G`)
  - `Whisper Voice - Settings...` (menu command)
  - `Whisper Voice - Local Model Setup Guide` (menu command)
- Optional OpenAI-compatible post-editing pipeline
- Install/uninstall scripts
- No TextMate core modification

## Requirements

- macOS
- TextMate 2
- `ffmpeg` (record audio)
- `mlx_whisper` (transcribe audio)

Check dependencies:

```bash
command -v ffmpeg
command -v mlx_whisper
```

## Install

```bash
cd <path-to>/textmate-whisper
./scripts/install.sh
```

Then in TextMate:

- `Bundles -> Bundle Editor -> Reload Bundles`
- Open settings panel:
  - `Bundles -> Whisper Voice -> Whisper Voice - Settings...`
- Open local setup guide:
  - `Bundles -> Whisper Voice -> Whisper Voice - Local Model Setup Guide`
- Save config and make it effective:
  - `Bundles -> Bundle Editor -> Reload Bundles`
  - If still stale, restart TextMate

## Uninstall

```bash
cd <path-to>/textmate-whisper
./scripts/uninstall.sh
```

## Configuration

Use `~/.config/textmate-whisper/config.env` (created by `Whisper Voice - Settings...`).

### Whisper / Recording

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

List audio devices (recommended before setting a fixed index):

```bash
./scripts/list_input_devices.sh
```

Auto selection priority is:

- Headset / earphones
- Built-in microphone
- iPhone continuity microphone
- First available device (fallback)

Then set one explicitly if needed:

```bash
TM_WHISPER_INPUT_DEVICE=:1
```

### Optional OpenAI-Compatible Post-Edit

```bash
TM_OAI_BASE_URL=https://api.openai.com/v1
TM_OAI_API_KEY=sk-...
TM_OAI_MODEL=gpt-4o-mini
TM_OAI_TIMEOUT_SEC=45

TM_VOICE_POST_PROMPT=Polish this transcript into concise writing.
TM_VOICE_POST_SYSTEM_PROMPT=You are a writing assistant. Improve punctuation and readability while preserving meaning. Return only the rewritten text.
```

To enable post-editing for a command run, the command sets:

```bash
TM_VOICE_POSTPROCESS=openai
```

`Voice Dictation - Insert + AI Prompt...` sets this automatically and asks for an instruction.

### Start/Stop Recording Flow

- Press `Option+Command+F1` to start recording
- Press `Shift+Option+Command+F1` to stop and insert transcript
- During recording/transcribing, window title shows `🔴 REC=<device>` / `🟡 AI...` when `TM_VOICE_SHOW_STATUS=1`

## Design Notes

- The bundle is installed under user bundles:
  - `~/Library/Application Support/TextMate/Bundles/Whisper Voice.tmbundle`
- Commands call a shared bootstrap entry:
  - `Support/bin/bootstrap.sh`
- Runtime scripts share helper library:
  - `Support/bin/_common.sh`
- Post-editing is optional and fail-open (falls back to raw transcript if API fails)
- Product requirement document:
  - `docs/PRD-TextMate-Whisper-Voice-Input-v1.0.md`

## Troubleshooting

- `ffmpeg not found`
  - Install ffmpeg and/or set `TM_FFMPEG_BIN`
- `mlx_whisper not found`
  - Install whisper-mlx and/or set `TM_WHISPER_BIN`
- Recording fails
  - Check microphone permission for TextMate (System Settings -> Privacy & Security -> Microphone)
  - Run `./scripts/list_input_devices.sh` and verify `TM_WHISPER_INPUT_DEVICE`
  - Use `auto` if you do not need a fixed device index
- Empty transcript
  - Increase `TM_WHISPER_MAX_SEC`
  - Use a larger model (`mlx-community/whisper-medium`)
- Need debug logs
  - `~/.cache/textmate-whisper/logs/voice_input-YYYYMMDD.log`
  - `~/.cache/textmate-whisper/logs/record_session-YYYYMMDD.log`
  - Optional override: `TM_WHISPER_LOG_DIR=/your/path`

## Development

Run static checks:

```bash
./scripts/smoke.sh
```

`smoke.sh` includes syntax checks and `voice_input.sh --dry-run` runtime-path validation.

## License

MIT
