#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_common.sh"
safe_source_tm_bash_init

CONFIG_FILE="${TM_WHISPER_CONFIG_FILE:-$HOME/.config/textmate-whisper/config.env}"
LANG_COMMAND_PLIST_REL="Commands/Whisper Voice - Set AI Output Language.tmCommand"

ensure_config_file() {
  local cfg="$1"
  local cfg_dir
  cfg_dir="$(dirname "$cfg")"
  mkdir -p "$cfg_dir"
  if [[ ! -f "$cfg" ]]; then
    cat > "$cfg" <<'EOF'
TM_VOICE_POST_OUTPUT_LANG=auto
EOF
  fi
}

update_config_key() {
  local cfg="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp /tmp/tm-whisper-lang-XXXXXX)"

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

normalize_lang() {
  local raw="${1:-auto}"
  local value
  value="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | tr -d '[:space:]')"
  case "$value" in
    ""|auto|same|follow|input|source|original)
      printf 'auto\n'
      ;;
    en|eng|english)
      printf 'en\n'
      ;;
    zh|zhcn|zh_cn|zh-cn|cn|chinese|simplifiedchinese|simplified)
      printf 'zh\n'
      ;;
    ja|jp|jpn|japanese)
      printf 'ja\n'
      ;;
    ko|kr|kor|korean)
      printf 'ko\n'
      ;;
    *)
      printf 'auto\n'
      ;;
  esac
}

lang_label() {
  local code="$1"
  case "$code" in
    en)
      printf 'English\n'
      ;;
    zh)
      printf 'Chinese\n'
      ;;
    ja)
      printf 'Japanese\n'
      ;;
    ko)
      printf 'Korean\n'
      ;;
    *)
      printf 'Auto\n'
      ;;
  esac
}

resolve_bundle_root() {
  (cd "$SCRIPT_DIR/../.." && pwd)
}

sync_lang_menu_name() {
  local lang_code="$1"
  local bundle_root command_plist target_name label

  bundle_root="$(resolve_bundle_root)"
  command_plist="${bundle_root}/${LANG_COMMAND_PLIST_REL}"
  [[ -f "$command_plist" ]] || return 0

  label="$(lang_label "$lang_code")"
  target_name="Whisper Voice - AI Output Language: ${label}"
  if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :name ${target_name}" "$command_plist" >/dev/null 2>&1 || true
  fi
}

pick_lang_from_menu() {
  local default_label="${1:-Auto}"
  local choice

  if ! command -v osascript >/dev/null 2>&1; then
    printf '\n'
    return 0
  fi

  choice="$(/usr/bin/osascript - "$default_label" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set defaultItem to item 1 of argv as text
  set options to {"Auto (Follow Transcript)", "English", "Chinese", "Japanese", "Korean"}
  try
    set picked to choose from list options with title "Whisper Voice" with prompt "Choose AI post-edit output language:" default items {defaultItem} OK button name "Apply" cancel button name "Cancel"
    if picked is false then return ""
    return item 1 of picked
  on error
    return ""
  end try
end run
APPLESCRIPT
)"
  printf '%s\n' "$choice"
}

choice_to_lang_code() {
  local choice="$1"
  case "$choice" in
    "English")
      printf 'en\n'
      ;;
    "Chinese")
      printf 'zh\n'
      ;;
    "Japanese")
      printf 'ja\n'
      ;;
    "Korean")
      printf 'ko\n'
      ;;
    "Auto (Follow Transcript)"|"Auto")
      printf 'auto\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

ensure_config_file "$CONFIG_FILE"
load_config_env "$CONFIG_FILE" TM_VOICE_POST_OUTPUT_LANG

current_lang="$(normalize_lang "${TM_VOICE_POST_OUTPUT_LANG:-auto}")"
current_label="$(lang_label "$current_lang")"
choice="$(pick_lang_from_menu "$current_label")"

if [[ -z "$choice" ]]; then
  sync_lang_menu_name "$current_lang"
  exit 0
fi

target_lang="$(choice_to_lang_code "$choice")"
if [[ -z "$target_lang" ]]; then
  show_tip_and_exit "Unsupported language option: ${choice}" 1
fi

update_config_key "$CONFIG_FILE" "TM_VOICE_POST_OUTPUT_LANG" "$target_lang"
sync_lang_menu_name "$target_lang"

show_tip_and_exit "AI post-edit output language: $(lang_label "$target_lang") (TM_VOICE_POST_OUTPUT_LANG=${target_lang})." 0
