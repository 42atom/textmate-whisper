#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_common.sh"
safe_source_tm_bash_init

CONFIG_FILE="${TM_WHISPER_CONFIG_FILE:-$HOME/.config/textmate-whisper/config.env}"
TOGGLE_COMMAND_PLIST_REL="Commands/Whisper Voice - Toggle AI Postprocess.tmCommand"

ensure_config_file() {
  local cfg="$1"
  local cfg_dir
  cfg_dir="$(dirname "$cfg")"
  mkdir -p "$cfg_dir"
  if [[ ! -f "$cfg" ]]; then
    cat > "$cfg" <<'EOF'
TM_VOICE_POSTPROCESS=auto
EOF
  fi
}

update_config_key() {
  local cfg="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp /tmp/tm-whisper-toggle-XXXXXX)"

  awk -v key="$key" -v value="$value" '
    BEGIN { updated = 0 }
    {
      if ($0 ~ ("^[[:space:]]*" key "[[:space:]]*=")) {
        if (!updated) {
          print key "=" value
          updated = 1
        }
        next
      }
      print
    }
    END {
      if (!updated) {
        print key "=" value
      }
    }
  ' "$cfg" > "$tmp"

  mv "$tmp" "$cfg"
}

ensure_config_file "$CONFIG_FILE"
load_config_env "$CONFIG_FILE" TM_VOICE_POSTPROCESS

mode_is_enabled() {
  local mode="$1"
  case "$mode" in
    openai|openai-compatible|1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_bundle_root() {
  # .../Whisper Voice.tmbundle/Support/bin -> .../Whisper Voice.tmbundle
  (cd "$SCRIPT_DIR/../.." && pwd)
}

sync_toggle_menu_name() {
  local mode="$1"
  local bundle_root command_plist target_name

  bundle_root="$(resolve_bundle_root)"
  command_plist="${bundle_root}/${TOGGLE_COMMAND_PLIST_REL}"
  [[ -f "$command_plist" ]] || return 0

  if mode_is_enabled "$mode"; then
    target_name="Whisper Voice - Disable AI Post-Edit"
  else
    target_name="Whisper Voice - Enable AI Post-Edit"
  fi

  if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :name ${target_name}" "$command_plist" >/dev/null 2>&1 || true
  fi
}

current_mode="$(printf '%s' "${TM_VOICE_POSTPROCESS:-auto}" | tr '[:upper:]' '[:lower:]')"
target_mode="openai"
status_label="ON"

case "$current_mode" in
  openai|openai-compatible|1|true|yes|on)
    target_mode="off"
    status_label="OFF"
    ;;
  *)
    target_mode="openai"
    status_label="ON"
    ;;
esac

update_config_key "$CONFIG_FILE" "TM_VOICE_POSTPROCESS" "$target_mode"
sync_toggle_menu_name "$target_mode"

if mode_is_enabled "$target_mode"; then
  next_action="Disable AI Post-Edit"
else
  next_action="Enable AI Post-Edit"
fi

show_tip_and_exit "AI Post-Edit: ${status_label} (TM_VOICE_POSTPROCESS=${target_mode}). Next menu action: ${next_action}." 0
