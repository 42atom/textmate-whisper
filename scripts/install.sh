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

CONFIG_FILE="${TM_WHISPER_CONFIG_FILE:-$HOME/.config/textmate-whisper/config.env}"
TOGGLE_COMMAND_PLIST="$TARGET_BUNDLE/Commands/Whisper Voice - Toggle AI Postprocess.tmCommand"
LANG_COMMAND_PLIST="$TARGET_BUNDLE/Commands/Whisper Voice - Set AI Output Language.tmCommand"
if [[ -f "$TOGGLE_COMMAND_PLIST" ]]; then
  mode="off"
  if [[ -f "$CONFIG_FILE" ]]; then
    mode="$(awk -F= '
      /^[[:space:]]*TM_VOICE_POSTPROCESS[[:space:]]*=/ {
        v=$2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^"|"$/, "", v)
        gsub(/^'\''|'\''$/, "", v)
        mode=tolower(v)
      }
      END { print mode }
    ' "$CONFIG_FILE")"
  fi

  if [[ "$mode" =~ ^(openai|openai-compatible|1|true|yes|on)$ ]]; then
    /usr/libexec/PlistBuddy -c "Set :name Whisper Voice - Disable AI Post-Edit" "$TOGGLE_COMMAND_PLIST" >/dev/null 2>&1 || true
  else
    /usr/libexec/PlistBuddy -c "Set :name Whisper Voice - Enable AI Post-Edit" "$TOGGLE_COMMAND_PLIST" >/dev/null 2>&1 || true
  fi
fi

if [[ -f "$LANG_COMMAND_PLIST" ]]; then
  post_lang="auto"
  if [[ -f "$CONFIG_FILE" ]]; then
    post_lang="$(awk -F= '
      /^[[:space:]]*TM_VOICE_POST_OUTPUT_LANG[[:space:]]*=/ {
        v=$2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^"|"$/, "", v)
        gsub(/^'\''|'\''$/, "", v)
        lang=tolower(v)
      }
      END { print lang }
    ' "$CONFIG_FILE")"
  fi

  case "$post_lang" in
    en|eng|english)
      lang_label="English"
      ;;
    zh|zhcn|zh_cn|zh-cn|cn|chinese|simplifiedchinese|simplified)
      lang_label="Chinese"
      ;;
    ja|jp|jpn|japanese)
      lang_label="Japanese"
      ;;
    ko|kr|kor|korean)
      lang_label="Korean"
      ;;
    *)
      lang_label="Auto"
      ;;
  esac
  /usr/libexec/PlistBuddy -c "Set :name Whisper Voice - AI Output Language: ${lang_label}" "$LANG_COMMAND_PLIST" >/dev/null 2>&1 || true
fi

cat <<MSG
[OK] Installed TextMate bundle: $TARGET_BUNDLE
[OK] Commands:
  - Voice Dictation - Toggle Recording        (Option+Command+F1)
  - Voice Dictation - Stop Recording          (Option+Command+F2, optional fallback)
  - Whisper Voice - Enable/Disable AI Post-Edit (Control+Option+Command+D)
  - Whisper Voice - AI Output Language: <Auto|English|Chinese|Japanese|Korean>
  - Whisper Voice - Request Microphone Permission
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
