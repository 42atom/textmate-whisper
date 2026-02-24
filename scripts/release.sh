#!/usr/bin/env bash
set -euo pipefail

# Build artifact release helper.
# Usage:
#   TAG=v0.2.0 ./scripts/release.sh
#
# Required:
#   - gh CLI logged in (`gh auth status`)
#   - git remote origin configured
#
# Optional env:
#   APP_PATH            Path to built TextMate.app
#   REPO                GitHub repo owner/name
#   TAG                 Release tag (default: date-based)
#   TITLE               Release title
#   NOTES_FILE          Release notes markdown file
#   PRERELEASE          true/false

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="${APP_PATH:-$HOME/Desktop/textmate-whisper-build/TextMate.app}"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
TAG="${TAG:-v0.2.0}"
TITLE="${TITLE:-$TAG}"
NOTES_FILE="${NOTES_FILE:-}"
PRERELEASE="${PRERELEASE:-false}"

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

command -v gh >/dev/null 2>&1 || die "gh not found."
command -v zip >/dev/null 2>&1 || die "zip not found."
command -v shasum >/dev/null 2>&1 || die "shasum not found."

[[ -d "$APP_PATH" ]] || die "App not found: $APP_PATH"
gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated."
[[ -n "$REPO" ]] || die "Cannot resolve repo. Set REPO=owner/name."

ARTIFACT_DIR="$ROOT_DIR/dist"
mkdir -p "$ARTIFACT_DIR"

ZIP_BASENAME="TextMate-whisper-macos-universal-${TAG}.zip"
ZIP_PATH="$ARTIFACT_DIR/$ZIP_BASENAME"
SHA_PATH="$ZIP_PATH.sha256"

info "Packaging app -> $ZIP_PATH"
(
  cd "$(dirname "$APP_PATH")"
  ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP_PATH")" "$ZIP_PATH"
)

info "Generating checksum -> $SHA_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  info "Release $TAG exists, uploading assets..."
  gh release upload "$TAG" "$ZIP_PATH" "$SHA_PATH" --repo "$REPO" --clobber
else
  info "Creating release $TAG on $REPO"
  create_args=(gh release create "$TAG" "$ZIP_PATH" "$SHA_PATH" --repo "$REPO" --title "$TITLE")
  if [[ "$PRERELEASE" == "true" ]]; then
    create_args+=(--prerelease)
  fi
  if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || die "NOTES_FILE not found: $NOTES_FILE"
    create_args+=(--notes-file "$NOTES_FILE")
  else
    create_args+=(--generate-notes)
  fi
  "${create_args[@]}"
fi

info "Done. Release URL:"
gh release view "$TAG" --repo "$REPO" --json url -q .url
