#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_common.sh"
safe_source_tm_bash_init

BUNDLE_ID="com.macromates.TextMate"

/usr/bin/tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1 || true
/usr/bin/killall tccd >/dev/null 2>&1 || true
/usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" >/dev/null 2>&1 || true

show_tip_and_exit "Microphone permission reset for TextMate. Keep TextMate frontmost, run Voice Dictation - Toggle Recording, then click Allow in the macOS prompt." 0
