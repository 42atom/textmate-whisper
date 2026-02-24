#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_SH="$ROOT_DIR/templates/Support/bin/_common.sh"

if [[ ! -f "$COMMON_SH" ]]; then
  echo "[ERROR] common helper not found: $COMMON_SH" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$COMMON_SH"

FFMPEG_BIN_RAW="${TM_FFMPEG_BIN:-ffmpeg}"
FFMPEG_BIN="$(resolve_bin "$FFMPEG_BIN_RAW" || true)"
if [[ -z "$FFMPEG_BIN" ]]; then
  echo "[ERROR] ffmpeg not found. Set TM_FFMPEG_BIN or install ffmpeg." >&2
  exit 1
fi

echo "[INFO] Available avfoundation audio input devices"
devices="$(list_audio_devices)"

printf '%s\n' "$devices" | awk -F'|' '{ print "  - " $1 ": " $2 }'

auto_idx="$(auto_pick_audio_device_index "$devices")"

echo
echo "[INFO] Recommended setting in ~/.tm_properties:"
echo "  TM_WHISPER_INPUT_DEVICE = :<audio_index>"
echo "[INFO] Or keep auto-detect:"
echo "  TM_WHISPER_INPUT_DEVICE = auto"
if [[ -n "$auto_idx" ]]; then
  auto_name="$(printf '%s\n' "$devices" | awk -F'|' -v idx="$auto_idx" '$1 == idx { print $2; exit }')"
  echo "[INFO] Current auto pick:"
  echo "  :$auto_idx ($auto_name)"
fi
