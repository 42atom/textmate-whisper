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
- Four commands with keyboard shortcuts
  - `Voice Dictation - Insert` (`Option+Command+D`)
  - `Voice Dictation - Replace Selection` (`Shift+Option+Command+D`)
  - `Voice Dictation - Preview Draft` (`Control+Option+Command+D`)
  - `Voice Dictation - Insert + AI Prompt...` (`Option+Command+G`)
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
cd /Users/admin/GitProjects/textmate-whisper
./scripts/install.sh
```

Then in TextMate:

- `Bundles -> Bundle Editor -> Reload Bundles`

## Uninstall

```bash
cd /Users/admin/GitProjects/textmate-whisper
./scripts/uninstall.sh
```

## Configuration

Use `~/.tm_properties` (or project `.tm_properties`).

### Whisper / Recording

```properties
TM_WHISPER_BIN = mlx_whisper
TM_FFMPEG_BIN = ffmpeg
TM_WHISPER_MODEL = mlx-community/whisper-small
TM_WHISPER_LANG = zh
TM_WHISPER_TASK = transcribe
TM_WHISPER_MAX_SEC = 20
TM_WHISPER_INPUT_DEVICE = :0
```

### Optional OpenAI-Compatible Post-Edit

```properties
TM_OAI_BASE_URL = https://api.openai.com/v1
TM_OAI_API_KEY = sk-...
TM_OAI_MODEL = gpt-4o-mini
TM_OAI_TIMEOUT_SEC = 45

TM_VOICE_POST_PROMPT = Polish this transcript into concise writing.
TM_VOICE_POST_SYSTEM_PROMPT = You are a writing assistant. Improve punctuation and readability while preserving meaning. Return only the rewritten text.
```

To enable post-editing for a command run, the command sets:

```properties
TM_VOICE_POSTPROCESS = openai
```

`Voice Dictation - Insert + AI Prompt...` sets this automatically and asks for an instruction.

## Design Notes

- The bundle is installed under user bundles:
  - `~/Library/Application Support/TextMate/Bundles/Whisper Voice.tmbundle`
- Commands call a single shared runtime script:
  - `Support/bin/voice_input.sh`
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
  - Check input device index (`TM_WHISPER_INPUT_DEVICE`, default `:0`)
- Empty transcript
  - Increase `TM_WHISPER_MAX_SEC`
  - Use a larger model (`mlx-community/whisper-medium`)

## Development

Run static checks:

```bash
./scripts/smoke.sh
```

## License

MIT
