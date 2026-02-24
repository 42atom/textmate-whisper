#!/usr/bin/env bash
set -euo pipefail

TM_USER_BUNDLES="$HOME/Library/Application Support/TextMate/Bundles"
BUNDLE_NAME="Whisper Voice.tmbundle"
TARGET_BUNDLE="$TM_USER_BUNDLES/$BUNDLE_NAME"
TS="$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$TARGET_BUNDLE" ]]; then
  echo "[INFO] Bundle not installed: $TARGET_BUNDLE"
  exit 0
fi

TRASH_DIR="$HOME/.Trash/textmate-whisper-uninstall-$TS"
mkdir -p "$TRASH_DIR"
mv "$TARGET_BUNDLE" "$TRASH_DIR/"

echo "[OK] Uninstalled bundle to Trash: $TRASH_DIR/$BUNDLE_NAME"
echo "[Next] Reload bundles or restart TextMate"
