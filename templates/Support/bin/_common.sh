#!/usr/bin/env bash

# Shared helpers for Whisper Voice scripts.

safe_source_tm_bash_init() {
  if [[ -n "${TM_SUPPORT_PATH:-}" && -f "${TM_SUPPORT_PATH}/lib/bash_init.sh" ]]; then
    # bash_init.sh may contain commands incompatible with set -e.
    set +e
    # shellcheck source=/dev/null
    . "${TM_SUPPORT_PATH}/lib/bash_init.sh"
    set -euo pipefail
  fi
}

append_log() {
  local level="$1"
  shift || true
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

is_textmate_context() {
  if [[ -n "${TM_BUNDLE_SUPPORT:-}" || -n "${TM_SCOPE:-}" || -n "${TM_SELECTED_TEXT+x}" ]]; then
    return 0
  fi
  return 1
}

show_tip_and_exit() {
  local msg="$1"
  local non_tm_exit_code="${2:-1}"
  local in_tm_context=0

  append_log "TIP" "$msg"
  if is_textmate_context; then
    in_tm_context=1
  fi

  if declare -F exit_show_tool_tip >/dev/null 2>&1; then
    exit_show_tool_tip "$msg"
    exit 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'display notification "'"${msg//\"/\\\"}"'" with title "Whisper Voice"' >/dev/null 2>&1 || true
  fi

  # In TextMate command context, avoid writing tip text to stderr/stdout,
  # otherwise it may be inserted into editor content (replaceInput mode).
  if [[ "$in_tm_context" == "1" ]]; then
    exit 0
  fi

  echo "$msg" >&2
  exit "$non_tm_exit_code"
}

resolve_bin() {
  local raw="${1:-}"
  local candidate

  if [[ -z "$raw" ]]; then
    return 1
  fi

  if [[ "$raw" == */* ]]; then
    [[ -x "$raw" ]] && printf '%s\n' "$raw" && return 0
    return 1
  fi

  if candidate="$(command -v "$raw" 2>/dev/null)"; then
    [[ -n "$candidate" ]] && printf '%s\n' "$candidate" && return 0
  fi

  for candidate in "/opt/homebrew/bin/$raw" "/usr/local/bin/$raw" "/usr/bin/$raw"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

trim_inline_space() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  printf '%s' "$value"
}

strip_wrapping_quotes() {
  local value="$1"
  if [[ "$value" =~ ^\"(.*)\"$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$value" =~ ^\'(.*)\'$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s' "$value"
}

load_config_env() {
  local cfg_file="$1"
  shift || true
  local -a allowed_keys=()
  if [[ $# -gt 0 ]]; then
    allowed_keys=("$@")
  fi
  local line key value

  [[ -f "$cfg_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$(trim_inline_space "$line")" ]] && continue

    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="$(trim_inline_space "${BASH_REMATCH[2]}")"
      value="$(strip_wrapping_quotes "$value")"

      if [[ "${#allowed_keys[@]}" -gt 0 ]]; then
        local matched=0
        local allowed
        for allowed in "${allowed_keys[@]}"; do
          if [[ "$key" == "$allowed" ]]; then
            matched=1
            break
          fi
        done
        (( matched == 1 )) || continue
      fi

      export "$key=$value"
    fi
  done < "$cfg_file"
}

is_truthy() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

status_notify() {
  local phase="${1:-Status}"
  local message="${2:-}"

  if ! is_truthy "${TM_VOICE_SHOW_STATUS:-1}"; then
    return 0
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    return 0
  fi

  /usr/bin/osascript - "$phase" "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  try
    set phaseName to item 1 of argv
    set bodyText to item 2 of argv
    display notification bodyText with title "Whisper Voice" subtitle phaseName
  end try
end run
APPLESCRIPT
}

list_audio_devices_raw() {
  if [[ -z "${FFMPEG_BIN:-}" ]]; then
    return 0
  fi
  "$FFMPEG_BIN" -f avfoundation -list_devices true -i "" 2>&1 || true
}

list_audio_devices() {
  list_audio_devices_raw \
    | awk '
      /AVFoundation audio devices/ { in_audio=1; next }
      /AVFoundation video devices/ { if(in_audio) in_audio=0 }
      in_audio && match($0, /\[[0-9]+\]/) {
        idx = substr($0, RSTART + 1, RLENGTH - 2)
        name = $0
        sub(/.*\[[0-9]+\][[:space:]]*/, "", name)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        if (name != "") print idx "|" name
      }
    '
}

pick_audio_device_index() {
  local devices="$1"
  local regex="$2"
  printf '%s\n' "$devices" | awk -F'|' -v pat="$regex" 'tolower($2) ~ pat { print $1; exit }'
}

auto_pick_audio_device_index() {
  local devices="$1"
  local first_idx=""

  first_idx="$(pick_audio_device_index "$devices" '(airpods|headset|headphone|earbud|earphone|pods|usb[[:space:]]+audio|usb[[:space:]]+headset|bluetooth)')"
  if [[ -z "$first_idx" ]]; then
    first_idx="$(pick_audio_device_index "$devices" '(macbook|built-?in|internal)')"
  fi
  if [[ -z "$first_idx" ]]; then
    first_idx="$(pick_audio_device_index "$devices" 'iphone')"
  fi
  if [[ -z "$first_idx" ]]; then
    first_idx="$(printf '%s\n' "$devices" | head -n 1 | cut -d'|' -f1)"
  fi

  printf '%s\n' "$first_idx"
}

validate_and_resolve_input_device() {
  local configured="$1"
  local devices device_count first_idx audio_idx
  devices="$(list_audio_devices)"
  device_count="$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$device_count" == "0" ]]; then
    echo "No audio input device found by ffmpeg avfoundation."
    return 1
  fi

  if [[ "$configured" == "auto" || -z "$configured" ]]; then
    first_idx="$(auto_pick_audio_device_index "$devices")"
    printf ':%s\n' "$first_idx"
    return 0
  fi

  if [[ "$configured" =~ ^:([0-9]+)$ ]]; then
    audio_idx="${BASH_REMATCH[1]}"
    if printf '%s\n' "$devices" | cut -d'|' -f1 | grep -qx "$audio_idx"; then
      printf ':%s\n' "$audio_idx"
      return 0
    fi
    echo "Invalid TM_WHISPER_INPUT_DEVICE=${configured}. Run scripts/list_input_devices.sh and pick a valid audio index."
    return 1
  fi

  if [[ "$configured" =~ ^[0-9]+:[0-9]+$ ]]; then
    audio_idx="${configured##*:}"
    if printf '%s\n' "$devices" | cut -d'|' -f1 | grep -qx "$audio_idx"; then
      printf '%s\n' "$configured"
      return 0
    fi
    echo "Invalid audio index in TM_WHISPER_INPUT_DEVICE=${configured}. Run scripts/list_input_devices.sh."
    return 1
  fi

  echo "Unsupported TM_WHISPER_INPUT_DEVICE=${configured}. Use :N / V:N / auto."
  return 1
}
