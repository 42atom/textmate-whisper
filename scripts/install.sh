#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TM_USER_BUNDLES="$HOME/Library/Application Support/TextMate/Bundles"
BUNDLE_NAME="Whisper Voice.tmbundle"
TARGET_BUNDLE="$TM_USER_BUNDLES/$BUNDLE_NAME"
BACKUP_ROOT="$HOME/Library/Application Support/TextMate/Bundles.backups/Whisper Voice"

TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$TM_USER_BUNDLES"
mkdir -p "$BACKUP_ROOT"

if [[ -d "$TARGET_BUNDLE" ]]; then
  BACKUP_DIR="${BACKUP_ROOT}/${BUNDLE_NAME}.bak-${TS}"
  mv "$TARGET_BUNDLE" "$BACKUP_DIR"
  echo "[INFO] Backed up existing bundle: $BACKUP_DIR"
fi

mkdir -p "$TARGET_BUNDLE/Commands"
mkdir -p "$TARGET_BUNDLE/Support/bin"

install -m 644 "$ROOT_DIR/templates/info.plist" "$TARGET_BUNDLE/info.plist"
for f in "$ROOT_DIR"/templates/Commands/*.tmCommand; do
  install -m 644 "$f" "$TARGET_BUNDLE/Commands/$(basename "$f")"
done
for f in "$ROOT_DIR"/templates/Support/bin/*.sh; do
  install -m 755 "$f" "$TARGET_BUNDLE/Support/bin/$(basename "$f")"
done

plutil -lint "$TARGET_BUNDLE/info.plist" >/dev/null
for f in "$TARGET_BUNDLE"/Commands/*.tmCommand; do
  plutil -lint "$f" >/dev/null
done

for f in "$TARGET_BUNDLE"/Support/bin/*.sh; do
  bash -n "$f"
done

cat <<MSG
[OK] Installed TextMate bundle: $TARGET_BUNDLE
[OK] Commands:
  - Voice Dictation - Start Recording         (Option+Command+F1)
  - Voice Dictation - Stop Recording + Insert (Shift+Option+Command+F1)
  - Voice Dictation - Insert                  (Option+Command+D)
  - Voice Dictation - Replace Selection       (Shift+Option+Command+D)
  - Voice Dictation - Preview Draft           (Control+Option+Command+D)
  - Voice Dictation - Insert + AI Prompt...   (Option+Command+G)
  - Whisper Voice - Settings...               (menu command)
  - Whisper Voice - Local Model Setup Guide   (menu command)

[Next] Reload bundles in TextMate:
  Bundles -> Bundle Editor -> Reload Bundles
  If settings are still stale, restart TextMate.

[Config]
  Use menu: Bundles -> Whisper Voice -> Whisper Voice - Settings...
  It opens (or creates):
  ~/.config/textmate-whisper/config.env

[Device check]
  ./scripts/list_input_devices.sh

[Optional OpenAI-compatible post-edit]
  TM_OAI_BASE_URL=https://api.openai.com/v1
  TM_OAI_API_KEY=<your_key>
  TM_OAI_MODEL=gpt-4o-mini
MSG
