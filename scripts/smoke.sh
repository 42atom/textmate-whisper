#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT_DIR/scripts/install.sh"
bash -n "$ROOT_DIR/scripts/uninstall.sh"
bash -n "$ROOT_DIR/scripts/list_input_devices.sh"
for f in "$ROOT_DIR"/templates/Support/bin/*.sh; do
  bash -n "$f"
done

plutil -lint "$ROOT_DIR/templates/info.plist" >/dev/null
for f in "$ROOT_DIR"/templates/Commands/*.tmCommand; do
  plutil -lint "$f" >/dev/null
done

echo "[OK] Static checks passed."
if ! command -v mlx_whisper >/dev/null 2>&1; then
  echo "[WARN] mlx_whisper not found in PATH"
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[WARN] ffmpeg not found in PATH"
fi

if command -v mlx_whisper >/dev/null 2>&1 && command -v ffmpeg >/dev/null 2>&1; then
  dry_out="$("$ROOT_DIR/templates/Support/bin/voice_input.sh" --mode insert --dry-run)"
  if [[ "$dry_out" != DRY_RUN_OK* ]]; then
    echo "[ERROR] dry-run check failed: $dry_out" >&2
    exit 1
  fi
  echo "[OK] Runtime dry-run passed."
else
  echo "[WARN] Runtime dry-run skipped (ffmpeg/mlx_whisper missing)."
fi
