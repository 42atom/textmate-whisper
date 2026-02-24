#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT_DIR/scripts/install.sh"
bash -n "$ROOT_DIR/scripts/uninstall.sh"
bash -n "$ROOT_DIR/templates/Support/bin/voice_input.sh"

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
