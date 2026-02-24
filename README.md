# textmate-whisper

[English](README.md) | [中文](README.zh-CN.md)

Local voice dictation for TextMate using `mlx_whisper`, with optional OpenAI-compatible post-editing.

## Why

TextMate is lightweight and fast, but it has no built-in speech-to-text workflow. This project adds a production-ready bundle that keeps the workflow local-first:

- Record from microphone
- Transcribe with local Whisper MLX
- Insert/replace in TextMate
- Optionally run post-edit polishing through any OpenAI-compatible API

## Features

- Local transcription via `mlx_whisper` (default)
- Recording status indicator (window title prefix `🔴 REC=<device> ⌥+⌘+F1 to stop` / `🪩 AI后处理...` + macOS notifications)
- Five commands with keyboard shortcuts
  - `Voice Dictation - Toggle Recording` (`Option+Command+F1`, primary)
  - `Voice Dictation - Stop Recording` (`Option+Command+F2`, optional fallback)
  - `Whisper Voice - Enable/Disable AI Post-Edit` (`Control+Option+Command+D`, dynamic label by current state)
  - `Whisper Voice - AI Output Language: <Auto|English|Chinese|Japanese|Korean>` (menu command, only effective when AI Post-Edit is enabled)
  - `Whisper Voice - Settings...` (menu command)
  - `Whisper Voice - Local Model Setup Guide` (menu command)
- Optional OpenAI-compatible post-editing pipeline
- Install/uninstall scripts
- No TextMate core modification

## Requirements

- macOS (Apple Silicon, M1 or later)
- TextMate 2
- Python 3.9+
- `ffmpeg` (record audio)
- `mlx_whisper` (transcribe audio, provided by `mlx-whisper`)

Install dependencies:

```bash
brew install ffmpeg
python3 -m pip install -U mlx-whisper
```

Check dependencies:

```bash
python3 --version
command -v ffmpeg
command -v mlx_whisper
```

## Install

```bash
git clone https://github.com/42atom/textmate-whisper.git
cd textmate-whisper
./scripts/install.sh
```

Then in TextMate:

- `Bundles -> Bundle Editor -> Reload Bundles`
- First-time setup (required once):
  - `Bundles -> Whisper Voice -> Request Microphone Permission`
  - Keep TextMate frontmost, trigger recording once, and click `Allow` in macOS prompt
- Open settings panel:
  - `Bundles -> Whisper Voice -> Whisper Voice - Settings...`
- Open local setup guide:
  - `Bundles -> Whisper Voice -> Whisper Voice - Local Model Setup Guide`
- Save config and make it effective:
  - `Bundles -> Bundle Editor -> Reload Bundles`
  - If still stale, restart TextMate

## Uninstall

```bash
cd textmate-whisper
./scripts/uninstall.sh
```

## Configuration

Use `~/.config/textmate-whisper/config.env` (created by `Whisper Voice - Settings...`).

### Whisper / Recording

```bash
TM_WHISPER_BIN=mlx_whisper
TM_FFMPEG_BIN=ffmpeg
TM_WHISPER_MODEL=mlx-community/whisper-large-v3-turbo
# Optional local model path example:
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

TM_VOICE_POSTPROCESS=auto
TM_VOICE_POST_OUTPUT_LANG=auto
# off|none: disable post-edit
# auto: enable only when API key is set
# openai: force post-edit path (falls back to raw text if API fails)
# post-edit output language: auto|en|zh|ja|ko
# post-edit context window: before 200 chars + after 200 chars (enabled by default)

TM_VOICE_POST_PROMPT=Punctuation-only pass: add/fix punctuation and spacing. Do not change words or meaning.
TM_VOICE_POST_SYSTEM_PROMPT=You are a strict transcript punctuation corrector. Only correct punctuation and spacing. Keep words, characters, order, and meaning unchanged. Do not paraphrase, summarize, rewrite, translate, or expand. Return only the corrected text.
```

`TM_VOICE_POSTPROCESS=off` can force-disable post-edit even when key is configured.
You can quickly toggle it via menu command: `Whisper Voice - Enable/Disable AI Post-Edit`.
You can select post-edit output language via: `Whisper Voice - AI Output Language: ...` (effective only when post-edit is enabled).
When post-edit is enabled, it also sends a context window around caret (200 chars before + 200 chars after) to improve continuity.

### Start/Stop Recording Flow

- Press `Option+Command+F1` to toggle recording (start/stop)
- Optional fallback: `Option+Command+F2` to force stop and write transcript
- If selection exists, output replaces selection; otherwise it inserts at caret
- During recording/transcribing, window title shows `🔴 REC=<device> ⌥+⌘+F1 to stop` / `🪩 AI后处理...` when `TM_VOICE_SHOW_STATUS=1`
- Recording title blink interval can be tuned via `TM_WHISPER_REC_BLINK_SEC` (seconds, default `0.45`)

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
  - Prefer `mlx-community/whisper-large-v3-turbo` (or a local turbo model path)
- `mlx_whisper` traceback / random crash in TextMate chain
  - Set `TM_WHISPER_RETRY_CPU_ON_CRASH=1` (enabled by default)
  - If still unstable, set `TM_WHISPER_FORCE_CPU=1` to bypass Metal path
  - Check per-session artifacts: `~/.cache/textmate-whisper/session-*/whisper.stderr`, `whisper.stdout`, `whisper-runtime.txt`
- Need debug logs
  - `~/.cache/textmate-whisper/logs/voice_input-YYYYMMDD.log`
  - `~/.cache/textmate-whisper/logs/record_session-YYYYMMDD.log`
  - Optional override: `TM_WHISPER_LOG_DIR=/your/path`

### Window Title Error Codes (`❌ ERR=...`)

When recording/transcription fails, window title shows a short error code for quick triage.

| Code | Meaning | First Check |
| --- | --- | --- |
| `device-config` | Invalid or unsupported `TM_WHISPER_INPUT_DEVICE` value | Run `./scripts/list_input_devices.sh`, then set a valid `:N` or `auto` |
| `start-failed` | `ffmpeg` recording process failed to start | Check mic permission and `TM_FFMPEG_BIN` |
| `state-broken` | Active session state file is invalid/incomplete | Start a new recording session |
| `audio-missing` | Recorded file is missing at stop time | Retry recording and inspect session folder |
| `too-short` | Audio size/duration below minimum threshold | Hold recording longer and speak continuously |
| `audio-empty` | Output audio file exists but is empty | Verify selected input device and microphone signal |
| `silent` | Audio captured but peak volume is effectively silent | Confirm correct input device and system input level |
| `transcribe` | `voice_input.sh` transcription stage failed | Check `whisper.stderr` under `~/.cache/textmate-whisper/session-*` |

## Development

Run static checks:

```bash
./scripts/smoke.sh
```

`smoke.sh` includes syntax checks and `voice_input.sh --dry-run` runtime-path validation.

## Release (Compiled App)

To publish a downloadable compiled `TextMate-Whisper.app` to GitHub Release:

```bash
chmod +x ./scripts/release.sh
TAG=v0.2.1 ./scripts/release.sh
```

Defaults:
- App input path (auto-detected):
  - `~/Desktop/textmate-whisper-build/TextMate-Whisper.app` (preferred)
  - fallback: `~/Desktop/textmate-whisper-build/TextMate.app`
- Artifact output: `dist/TextMate-whisper-macos-universal-<tag>.zip`
- Also uploads SHA256 checksum file.

Override repo / app path if needed:

```bash
REPO=owner/repo APP_PATH=/path/to/TextMate-Whisper.app TAG=v0.2.1 ./scripts/release.sh
```

## License

MIT
