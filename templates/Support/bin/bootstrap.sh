#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_common.sh"

safe_source_tm_bash_init

resolve_support_dir() {
  if [[ -n "${TM_BUNDLE_SUPPORT:-}" ]]; then
    printf '%s\n' "$TM_BUNDLE_SUPPORT"
    return 0
  fi
  if [[ -n "${TM_BUNDLE_PATH:-}" ]]; then
    printf '%s\n' "$TM_BUNDLE_PATH/Support"
    return 0
  fi
  printf '%s\n' "$HOME/Library/Application Support/TextMate/Bundles/Whisper Voice.tmbundle/Support"
}

if [[ $# -lt 1 ]]; then
  show_tip_and_exit "Whisper Voice bootstrap usage: bootstrap.sh <script> [args...]" 2
fi

script_name="$1"
shift || true

support_dir="$(resolve_support_dir)"
export TM_BUNDLE_SUPPORT="$support_dir"
script_path="$support_dir/bin/$script_name"

if [[ ! -x "$script_path" ]]; then
  show_tip_and_exit "Whisper Voice script not found: $script_path" 1
fi

set +e
"$script_path" "$@"
status=$?
set -e

case "$status" in
  0|200|201|202|203|204|205|206|207|208)
    exit 0
    ;;
  *)
    show_tip_and_exit "Whisper Voice command failed: $script_name (exit $status)" "$status"
    ;;
esac
