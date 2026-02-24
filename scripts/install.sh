#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TM_USER_BUNDLES="$HOME/Library/Application Support/TextMate/Bundles"
BUNDLE_NAME="Whisper Voice.tmbundle"
TARGET_BUNDLE="$TM_USER_BUNDLES/$BUNDLE_NAME"

TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$TM_USER_BUNDLES"

if [[ -d "$TARGET_BUNDLE" ]]; then
  BACKUP_DIR="${TARGET_BUNDLE}.bak-${TS}"
  mv "$TARGET_BUNDLE" "$BACKUP_DIR"
  echo "[INFO] Backed up existing bundle: $BACKUP_DIR"
fi

mkdir -p "$TARGET_BUNDLE/Commands"
mkdir -p "$TARGET_BUNDLE/Support/bin"

install -m 644 "$ROOT_DIR/templates/info.plist" "$TARGET_BUNDLE/info.plist"
for f in "$ROOT_DIR"/templates/Commands/*.tmCommand; do
  install -m 644 "$f" "$TARGET_BUNDLE/Commands/$(basename "$f")"
done
install -m 755 "$ROOT_DIR/templates/Support/bin/voice_input.sh" "$TARGET_BUNDLE/Support/bin/voice_input.sh"

plutil -lint "$TARGET_BUNDLE/info.plist" >/dev/null
for f in "$TARGET_BUNDLE"/Commands/*.tmCommand; do
  plutil -lint "$f" >/dev/null
done

bash -n "$TARGET_BUNDLE/Support/bin/voice_input.sh"

cat <<MSG
[OK] Installed TextMate bundle: $TARGET_BUNDLE
[OK] Commands:
  - Voice Dictation - Insert                  (Option+Command+D)
  - Voice Dictation - Replace Selection       (Shift+Option+Command+D)
  - Voice Dictation - Preview Draft           (Control+Option+Command+D)
  - Voice Dictation - Insert + AI Prompt...   (Option+Command+G)

[Next] Reload bundles in TextMate:
  Bundles -> Bundle Editor -> Reload Bundles

[Optional] Add to ~/.tm_properties:
  TM_WHISPER_BIN = mlx_whisper
  TM_WHISPER_MODEL = mlx-community/whisper-small
  TM_WHISPER_LANG = zh
  TM_WHISPER_MAX_SEC = 20
  TM_WHISPER_INPUT_DEVICE = :0

[Optional OpenAI-compatible post-edit]
  TM_OAI_BASE_URL = https://api.openai.com/v1
  TM_OAI_API_KEY = <your_key>
  TM_OAI_MODEL = gpt-4o-mini
MSG
