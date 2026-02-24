#!/usr/bin/env bash
set -euo pipefail

cat <<'GUIDE'
# Whisper Voice - Local Model Setup Guide

## 1) Install dependencies (macOS)

```bash
brew install ffmpeg
python3 -m pip install -U mlx-whisper
```

## 2) Verify runtime

```bash
command -v ffmpeg
command -v mlx_whisper
mlx_whisper --help
```

## 3) Check microphone input devices

```bash
cd <path-to>/textmate-whisper
./scripts/list_input_devices.sh
```

Use one of these in `~/.config/textmate-whisper/config.env`:

```bash
TM_WHISPER_INPUT_DEVICE=auto
# or fixed:
# TM_WHISPER_INPUT_DEVICE=:1
```

## 4) Recommended TextMate settings

```bash
TM_WHISPER_BIN=mlx_whisper
TM_FFMPEG_BIN=ffmpeg
TM_WHISPER_MODEL=mlx-community/whisper-tiny
TM_WHISPER_LANG=zh
TM_WHISPER_TASK=transcribe
TM_WHISPER_MAX_SEC=20
TM_WHISPER_INPUT_DEVICE=auto
TM_VOICE_SHOW_STATUS=1
# TM_WHISPER_LOG_DIR=$HOME/.cache/textmate-whisper/logs
```

## 5) Optional OpenAI-compatible post-edit

```bash
TM_OAI_BASE_URL=https://api.openai.com/v1
TM_OAI_API_KEY=sk-...
TM_OAI_MODEL=gpt-4o-mini
TM_OAI_TIMEOUT_SEC=45
TM_VOICE_POSTPROCESS=auto
```

Notes:
- `TM_VOICE_POSTPROCESS=auto`: only enable post-edit when API key is configured.
- `TM_VOICE_POSTPROCESS=off`: disable post-edit.
- If API is unavailable, pipeline falls back to raw whisper transcript.

## 6) Reload TextMate bundles

`Bundles -> Bundle Editor -> Reload Bundles`

If changes still do not take effect, restart TextMate.

## 7) Recording hotkeys

- Toggle start/stop: `Option+Command+F1` (primary)
- Force stop and insert: `Option+Command+F2` (fallback)
- When enabled (`TM_VOICE_SHOW_STATUS=1`), window title shows `🔴 REC=<device>` while recording.

## 8) Debug logs

Default log path:

`~/.cache/textmate-whisper/logs`

Current files:

- `voice_input-YYYYMMDD.log`
- `record_session-YYYYMMDD.log`
GUIDE
