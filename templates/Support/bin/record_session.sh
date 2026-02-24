#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_common.sh"
safe_source_tm_bash_init

ACTION=""
MODE="insert"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      ACTION="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-insert}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

LOG_ROOT="${TM_WHISPER_LOG_DIR:-$HOME/.cache/textmate-whisper/logs}"
mkdir -p "$LOG_ROOT" >/dev/null 2>&1 || true
LOG_FILE="$LOG_ROOT/record_session-$(date +%Y%m%d).log"

strip_window_indicator_prefix() {
  printf '%s\n' "${1:-}" | sed -E \
    -e 's/^(🔴|⚪) REC=[^|]* \| //' \
    -e 's/^❌ ERR=[^|]* \| //' \
    -e 's/^(🟡 AI\.\.\.|🪩 AI后处理\.\.\.|⏳ Loading\.\.\.|🟡 loading\.\.\.) \| //' \
    -e 's/^\[(REC|AI\.\.\.)\] //'
}

capture_front_window_meta() {
  if ! command -v osascript >/dev/null 2>&1; then
    return 1
  fi
  /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
try
  tell application "TextMate"
    if (count of windows) is 0 then return ""
    return (id of front window as text) & tab & (name of front window as text)
  end tell
on error
  return ""
end try
APPLESCRIPT
}

capture_front_window_meta_and_mark_loading() {
  local marker="${1:-⏳ Loading... | }"

  if ! is_truthy "${TM_VOICE_SHOW_STATUS:-1}"; then
    capture_front_window_meta
    return 0
  fi
  if ! command -v osascript >/dev/null 2>&1; then
    capture_front_window_meta
    return 0
  fi

  /usr/bin/osascript - "$marker" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set marker to item 1 of argv as text
  try
    tell application "TextMate"
      if (count of windows) is 0 then return ""
      set w to front window
      set wid to id of w as text
      set rawName to name of w as text
      set name of w to marker & rawName
      return wid & tab & rawName
    end tell
  on error
    return ""
  end try
end run
APPLESCRIPT
}

set_window_name_by_id() {
  local win_id="${1:-}"
  local target_name="${2:-}"

  if [[ -z "$win_id" || -z "$target_name" ]]; then
    return 0
  fi

  if ! is_truthy "${TM_VOICE_SHOW_STATUS:-1}"; then
    return 0
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    return 0
  fi

  /usr/bin/osascript - "$win_id" "$target_name" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  try
    set targetID to item 1 of argv as integer
    set targetName to item 2 of argv as text
    tell application "TextMate"
      repeat with w in windows
        if (id of w) is targetID then
          set name of w to targetName
          exit repeat
        end if
      end repeat
    end tell
  end try
end run
APPLESCRIPT
}

set_window_indicator() {
  local marker="${1:-}"
  local win_id="${2:-}"
  local base_name="${3:-}"
  local plain_name target_name

  if [[ -z "$win_id" || -z "$base_name" ]]; then
    return 0
  fi

  plain_name="$(strip_window_indicator_prefix "$base_name")"
  if [[ -n "$marker" ]]; then
    target_name="${marker} ${plain_name}"
  else
    target_name="$plain_name"
  fi
  set_window_name_by_id "$win_id" "$target_name"
}

read_state_var() {
  local key="$1"
  local file="$2"
  awk -F'=' -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file"
}

extract_audio_index_from_spec() {
  local spec="$1"
  if [[ "$spec" =~ ^:([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$spec" =~ ^[0-9]+:([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

resolve_audio_device_name() {
  local spec="$1"
  local devices idx name

  idx="$(extract_audio_index_from_spec "$spec" || true)"
  if [[ -z "$idx" ]]; then
    printf '%s\n' "$spec"
    return 0
  fi

  devices="$(list_audio_devices)"
  name="$(printf '%s\n' "$devices" | awk -F'|' -v i="$idx" '$1 == i { print $2; exit }')"
  if [[ -z "$name" ]]; then
    printf '%s\n' "$spec"
    return 0
  fi
  printf '%s\n' "$name"
}

build_recording_marker() {
  local spec="$1"
  local dev_name shown_name

  dev_name="$(resolve_audio_device_name "$spec")"
  dev_name="$(printf '%s' "$dev_name" | tr -d '\r\n')"
  shown_name="$dev_name"
  if [[ "${#shown_name}" -gt 24 ]]; then
    shown_name="${shown_name:0:24}..."
  fi

  printf '🔴 REC=%s |' "$shown_name"
}

build_error_marker() {
  local code="${1:-unknown}"
  code="$(printf '%s' "$code" | tr -cd 'A-Za-z0-9._:-')"
  if [[ -z "$code" ]]; then
    code="unknown"
  fi
  if [[ "${#code}" -gt 22 ]]; then
    code="${code:0:22}"
  fi
  printf '❌ ERR=%s |' "$code"
}

show_window_error_and_tip() {
  local code="$1"
  local msg="$2"
  local win_id="${3:-}"
  local base_name="${4:-}"
  local marker

  marker="$(build_error_marker "$code")"
  set_window_indicator "$marker" "$win_id" "$base_name"
  show_tip_and_exit "$msg"
}

start_recording_blink_loop() {
  local rec_pid="$1"
  local marker_on="$2"
  local win_id="$3"
  local base_name="$4"
  local marker_off current_pid blink_sec

  marker_off="${marker_on/🔴/⚪}"
  blink_sec="${TM_WHISPER_REC_BLINK_SEC:-0.45}"
  if ! awk -v x="$blink_sec" 'BEGIN { exit !(x > 0.1 && x <= 3.0) }'; then
    blink_sec="0.45"
  fi

  (
    local on=1
    while kill -0 "$rec_pid" >/dev/null 2>&1; do
      if [[ ! -f "$STATE_FILE" ]]; then
        break
      fi
      current_pid="$(read_state_var "PID" "$STATE_FILE" 2>/dev/null || true)"
      if [[ "$current_pid" != "$rec_pid" ]]; then
        break
      fi

      if [[ "$on" == "1" ]]; then
        set_window_indicator "$marker_off" "$win_id" "$base_name"
        on=0
      else
        set_window_indicator "$marker_on" "$win_id" "$base_name"
        on=1
      fi
      sleep "$blink_sec"
    done
  ) >/dev/null 2>&1 &

  printf '%s\n' "$!"
}

stop_recording_blink_loop() {
  local blink_pid="${1:-}"
  if [[ -z "$blink_pid" ]]; then
    return 0
  fi
  if kill -0 "$blink_pid" >/dev/null 2>&1; then
    kill "$blink_pid" >/dev/null 2>&1 || true
  fi
}

audio_duration_seconds() {
  local file="$1"
  local d ffprobe_bin size bytes est

  ffprobe_bin="$(resolve_bin "${TM_FFPROBE_BIN:-ffprobe}" || true)"
  if [[ -n "$ffprobe_bin" ]]; then
    d="$("$ffprobe_bin" -v error -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "$file" 2>/dev/null | tr -d '\r' | head -n 1)"
    if [[ -n "$d" ]] && awk -v x="$d" 'BEGIN { exit !(x > 0) }'; then
      printf '%s\n' "$d"
      return 0
    fi
  fi

  # Fallback for partially finalized WAV metadata:
  # ffmpeg records mono 16kHz s16le PCM -> about 32000 bytes/second (+44-byte header).
  size="$(stat -f '%z' "$file" 2>/dev/null || echo 0)"
  if [[ "$size" -gt 44 ]]; then
    bytes=$((size - 44))
    est="$(awk -v b="$bytes" 'BEGIN { printf "%.6f", b / 32000.0 }')"
    append_log "WARN" "ffprobe duration unavailable, fallback duration=${est}s size=${size}"
    printf '%s\n' "$est"
    return 0
  fi

  printf '0\n'
}

audio_max_volume_db() {
  local file="$1"
  local max_db

  if [[ -z "${FFMPEG_BIN:-}" ]]; then
    printf '\n'
    return 0
  fi

  max_db="$("$FFMPEG_BIN" -nostdin -hide_banner -i "$file" -af volumedetect -f null - 2>&1 \
    | awk -F': ' '/max_volume/ { gsub(/ dB/, "", $2); print $2; exit }')"
  printf '%s\n' "$max_db"
}

load_config_env "${TM_WHISPER_CONFIG_FILE:-$HOME/.config/textmate-whisper/config.env}" \
  TM_FFMPEG_BIN \
  TM_FFPROBE_BIN \
  TM_WHISPER_INPUT_DEVICE \
  TM_WHISPER_REC_BLINK_SEC \
  TM_VOICE_SHOW_STATUS \
  TM_WHISPER_SILENCE_DB \
  TM_WHISPER_STATE_DIR \
  TM_WHISPER_LOG_DIR

if [[ -n "${TM_WHISPER_LOG_DIR:-}" ]]; then
  LOG_ROOT="${TM_WHISPER_LOG_DIR}"
  mkdir -p "$LOG_ROOT" >/dev/null 2>&1 || true
  LOG_FILE="$LOG_ROOT/record_session-$(date +%Y%m%d).log"
fi

FFMPEG_BIN_RAW="${TM_FFMPEG_BIN:-ffmpeg}"
FFMPEG_BIN="$(resolve_bin "$FFMPEG_BIN_RAW" || true)"
WHISPER_INPUT_DEVICE="${TM_WHISPER_INPUT_DEVICE:-auto}"
TM_VOICE_SHOW_STATUS="${TM_VOICE_SHOW_STATUS:-1}"
TM_WHISPER_SILENCE_DB="${TM_WHISPER_SILENCE_DB:--80}"
STATE_ROOT="${TM_WHISPER_STATE_DIR:-$HOME/.cache/textmate-whisper}"
STATE_FILE="${STATE_ROOT}/active_session.env"
VOICE_INPUT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/voice_input.sh"

mkdir -p "$STATE_ROOT"

append_log "INFO" "start action=${ACTION:-<none>} mode=${MODE:-<none>} ffmpeg=${FFMPEG_BIN:-<missing>} state_root=$STATE_ROOT"

if [[ ! -x "$VOICE_INPUT_SCRIPT" ]]; then
  show_tip_and_exit "voice_input.sh not found or not executable."
fi

if [[ ! "$MODE" =~ ^(insert|replace|preview|auto)$ ]]; then
  show_tip_and_exit "Unsupported mode: $MODE"
fi

if [[ "$ACTION" != "start" && "$ACTION" != "stop" && "$ACTION" != "toggle" && "$ACTION" != "status" ]]; then
  show_tip_and_exit "Usage: record_session.sh --action start|stop|toggle|status [--mode insert|replace|preview|auto]"
fi

state_file_is_active() {
  local state_pid stale_win_id stale_win_title stale_blink_pid

  if [[ ! -f "$STATE_FILE" ]]; then
    return 1
  fi

  state_pid="$(read_state_var "PID" "$STATE_FILE")"
  if [[ -z "${state_pid:-}" ]]; then
    rm -f "$STATE_FILE"
    return 1
  fi

  if kill -0 "$state_pid" >/dev/null 2>&1; then
    return 0
  fi

  stale_win_id="$(read_state_var "WINDOW_ID" "$STATE_FILE")"
  stale_win_title="$(read_state_var "WINDOW_TITLE_BASE" "$STATE_FILE")"
  stale_blink_pid="$(read_state_var "BLINK_PID" "$STATE_FILE")"
  stop_recording_blink_loop "$stale_blink_pid"
  set_window_indicator "" "$stale_win_id" "$stale_win_title"
  append_log "WARN" "stale session removed: pid=$state_pid"
  rm -f "$STATE_FILE"
  return 1
}

build_status_message() {
  local pid audio_file saved_mode start_epoch_saved elapsed_now audio_size

  if ! state_file_is_active; then
    printf 'Recording: OFF | Toggle: Option+Command+F1 | Force stop: Option+Command+F2\n'
    return 0
  fi

  pid="$(read_state_var "PID" "$STATE_FILE")"
  audio_file="$(read_state_var "AUDIO_FILE" "$STATE_FILE")"
  saved_mode="$(read_state_var "MODE" "$STATE_FILE")"
  start_epoch_saved="$(read_state_var "START_EPOCH" "$STATE_FILE")"
  elapsed_now="unknown"
  if [[ -n "${start_epoch_saved:-}" && "$start_epoch_saved" =~ ^[0-9]+$ ]]; then
    elapsed_now="$(( $(date +%s) - start_epoch_saved ))s"
  fi
  audio_size=0
  if [[ -n "${audio_file:-}" && -f "$audio_file" ]]; then
    audio_size="$(stat -f '%z' "$audio_file" 2>/dev/null || echo 0)"
  fi

  printf 'Recording: ON | pid=%s | mode=%s | elapsed=%s | bytes=%s | Stop: Option+Command+F1 (or Option+Command+F2)\n' \
    "${pid:-unknown}" "${saved_mode:-auto}" "$elapsed_now" "$audio_size"
}

start_recording() {
  local window_meta window_id window_title_base requested_input_device recording_marker blink_pid

  if [[ -z "$FFMPEG_BIN" ]]; then
    show_tip_and_exit "ffmpeg not found. Install it or set TM_FFMPEG_BIN (current: ${FFMPEG_BIN_RAW})."
  fi

  if state_file_is_active; then
    show_tip_and_exit "Recording already running. Press Option+Command+F1 to stop (or Option+Command+F2)."
  fi

  if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
  fi

  window_id=""
  window_title_base=""
  window_meta="$(capture_front_window_meta_and_mark_loading "⏳ Loading... | ")"
  if [[ "$window_meta" == *$'\t'* ]]; then
    window_id="${window_meta%%$'\t'*}"
    window_title_base="${window_meta#*$'\t'}"
    window_title_base="$(strip_window_indicator_prefix "$window_title_base")"
  fi

  # Show a quick loading marker while resolving device and spawning ffmpeg.
  if [[ -n "$window_id" && -n "$window_title_base" ]]; then
    :
  else
    set_window_indicator "⏳ Loading... |" "$window_id" "$window_title_base"
  fi
  status_notify "Recording" "Preparing microphone..."

  requested_input_device="$WHISPER_INPUT_DEVICE"
  if ! WHISPER_INPUT_DEVICE="$(validate_and_resolve_input_device "$requested_input_device")"; then
    append_log "WARN" "invalid input device config: $requested_input_device"
    if [[ "$requested_input_device" != "auto" ]] && WHISPER_INPUT_DEVICE="$(validate_and_resolve_input_device "auto")"; then
      append_log "WARN" "fallback input device to auto from: $requested_input_device"
    else
      show_window_error_and_tip "device-config" "$WHISPER_INPUT_DEVICE" "$window_id" "$window_title_base"
    fi
  fi

  session_id="$(date +%s)-$$"
  session_dir="${STATE_ROOT}/session-${session_id}"
  audio_file="${session_dir}/recording.wav"
  log_file="${session_dir}/ffmpeg.log"
  start_epoch="$(date +%s)"
  mkdir -p "$session_dir"

  nohup "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error \
    -f avfoundation -i "$WHISPER_INPUT_DEVICE" \
    -ac 1 -ar 16000 "$audio_file" < /dev/null >"$log_file" 2>&1 &
  ffmpeg_pid=$!

  sleep 0.4
  if ! kill -0 "$ffmpeg_pid" >/dev/null 2>&1; then
    err_msg="Recording failed to start."
    if [[ -s "$log_file" ]]; then
      err_msg="$(tail -n 1 "$log_file")"
    fi
    rm -rf "$session_dir"
    show_window_error_and_tip "start-failed" "$err_msg" "$window_id" "$window_title_base"
  fi

  cat > "$STATE_FILE" <<EOF
PID=$ffmpeg_pid
AUDIO_FILE=$audio_file
SESSION_DIR=$session_dir
MODE=$MODE
START_EPOCH=$start_epoch
INPUT_DEVICE=$WHISPER_INPUT_DEVICE
WINDOW_ID=$window_id
WINDOW_TITLE_BASE=$window_title_base
EOF

  append_log "INFO" "recording started pid=$ffmpeg_pid device=$WHISPER_INPUT_DEVICE audio_file=$audio_file ffmpeg_log=$log_file"
  recording_marker="$(build_recording_marker "$WHISPER_INPUT_DEVICE")"
  set_window_indicator "$recording_marker" "$window_id" "$window_title_base"
  blink_pid="$(start_recording_blink_loop "$ffmpeg_pid" "$recording_marker" "$window_id" "$window_title_base")"
  printf 'BLINK_PID=%s\n' "$blink_pid" >> "$STATE_FILE"
  status_notify "Recording" "Started. Press Option+Command+F1 to stop."
  # Toggle command uses replaceInput output; emit selected text back so start action does not alter selection content.
  if [[ -n "${TM_SELECTED_TEXT:-}" ]]; then
    printf '%s' "$TM_SELECTED_TEXT"
  fi
  show_tip_and_exit "Recording started. Press Option+Command+F1 to stop." 0
}

stop_recording() {
  local window_id window_title_base blink_pid

  if ! state_file_is_active; then
    show_tip_and_exit "No active recording session. Press Option+Command+F1 to start."
  fi

  pid="$(read_state_var "PID" "$STATE_FILE")"
  audio_file="$(read_state_var "AUDIO_FILE" "$STATE_FILE")"
  session_dir="$(read_state_var "SESSION_DIR" "$STATE_FILE")"
  saved_mode="$(read_state_var "MODE" "$STATE_FILE")"
  start_epoch_saved="$(read_state_var "START_EPOCH" "$STATE_FILE")"
  window_id="$(read_state_var "WINDOW_ID" "$STATE_FILE")"
  window_title_base="$(read_state_var "WINDOW_TITLE_BASE" "$STATE_FILE")"
  blink_pid="$(read_state_var "BLINK_PID" "$STATE_FILE")"

  if [[ -z "${pid:-}" || -z "${audio_file:-}" ]]; then
    stop_recording_blink_loop "$blink_pid"
    rm -f "$STATE_FILE"
    show_window_error_and_tip "state-broken" "Recording state is broken. Please start recording again." "$window_id" "$window_title_base"
  fi

  if [[ "$saved_mode" =~ ^(insert|replace|preview|auto)$ ]]; then
    MODE="$saved_mode"
  fi

  pid_was_alive=0
  if kill -0 "$pid" >/dev/null 2>&1; then
    pid_was_alive=1
    kill -INT "$pid" >/dev/null 2>&1 || true
    for _ in {1..50}; do
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      for _ in {1..30}; do
        if ! kill -0 "$pid" >/dev/null 2>&1; then
          break
        fi
        sleep 0.1
      done
    fi
    if kill -0 "$pid" >/dev/null 2>&1; then
      append_log "WARN" "recording pid still alive after TERM, force KILL: pid=$pid"
      kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
  else
    append_log "WARN" "recording pid was not alive at stop: pid=$pid"
  fi

  stop_recording_blink_loop "$blink_pid"
  rm -f "$STATE_FILE"
  set_window_indicator "" "$window_id" "$window_title_base"

  if [[ ! -f "$audio_file" ]]; then
    append_log "ERROR" "audio file missing at stop: $audio_file"
    rm -rf "$session_dir"
    show_window_error_and_tip "audio-missing" "Recording file is missing. Please start recording again." "$window_id" "$window_title_base"
  fi

  wait_for_file_stable "$audio_file" 30 0.10
  audio_size="$(stat -f '%z' "$audio_file" 2>/dev/null || echo 0)"
  audio_dur="$(audio_duration_seconds "$audio_file")"
  audio_max_db="$(audio_max_volume_db "$audio_file")"
  stop_epoch="$(date +%s)"
  elapsed="unknown"
  if [[ -n "${start_epoch_saved:-}" && "$start_epoch_saved" =~ ^[0-9]+$ ]]; then
    elapsed="$((stop_epoch - start_epoch_saved))s"
  fi
  append_log "INFO" "stop metrics pid_alive=${pid_was_alive} size=${audio_size} duration=${audio_dur}s max_db=${audio_max_db:-unknown} elapsed=${elapsed} file=$audio_file"

  if [[ "$audio_size" -lt 2048 ]]; then
    rm -rf "$session_dir"
    show_window_error_and_tip "too-short" "Recording is too short or empty. Please hold recording longer and speak clearly." "$window_id" "$window_title_base"
  fi

  if awk -v d="$audio_dur" 'BEGIN { exit !(d < 0.40) }'; then
    rm -rf "$session_dir"
    show_window_error_and_tip "too-short" "Recording duration is too short (${audio_dur}s). Try holding recording for at least 1 second." "$window_id" "$window_title_base"
  fi

  if [[ ! -s "$audio_file" ]]; then
    show_window_error_and_tip "audio-empty" "Recording file is empty. Please try again." "$window_id" "$window_title_base"
  fi

  if [[ -n "${audio_max_db:-}" ]] && awk -v v="$audio_max_db" -v t="$TM_WHISPER_SILENCE_DB" 'BEGIN { exit !(v <= t) }'; then
    show_window_error_and_tip "silent" "Recorded audio is silent (max ${audio_max_db} dB). Run 'Whisper Voice - Request Microphone Permission', then verify TM_WHISPER_INPUT_DEVICE (e.g. AirPods :1). Debug audio kept at: $audio_file" "$window_id" "$window_title_base"
  fi

  set_window_indicator "🪩 AI后处理... |" "$window_id" "$window_title_base"
  status_notify "Transcribing" "Recording stopped. Converting speech to text..."

  if ! "$VOICE_INPUT_SCRIPT" --mode "$MODE" --audio-file "$audio_file"; then
    append_log "ERROR" "transcription after stop failed mode=$MODE audio_file=$audio_file size=$audio_size duration=${audio_dur}s"
    show_window_error_and_tip "transcribe" "Transcription failed. Debug audio kept at: $audio_file" "$window_id" "$window_title_base"
  fi

  set_window_indicator "" "$window_id" "$window_title_base"
  append_log "INFO" "recording stopped and transcribed mode=$MODE audio_file=$audio_file"
  rm -rf "$session_dir"
}

if [[ "$ACTION" == "toggle" ]]; then
  if state_file_is_active; then
    ACTION="stop"
  else
    ACTION="start"
  fi
  append_log "INFO" "toggle resolved action=$ACTION"
fi

if [[ "$ACTION" == "status" ]]; then
  show_tip_and_exit "$(build_status_message)" 0
fi

if [[ "$ACTION" == "start" ]]; then
  start_recording
fi

stop_recording
