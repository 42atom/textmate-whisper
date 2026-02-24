#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_common.sh"
safe_source_tm_bash_init

MODE="insert"
AUDIO_FILE_INPUT=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-insert}"
      shift 2
      ;;
    --audio-file)
      AUDIO_FILE_INPUT="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

LOG_ROOT="${TM_WHISPER_LOG_DIR:-$HOME/.cache/textmate-whisper/logs}"
mkdir -p "$LOG_ROOT" >/dev/null 2>&1 || true
LOG_FILE="$LOG_ROOT/voice_input-$(date +%Y%m%d).log"
SESSION_DIR=""
STATE_ROOT="${TM_WHISPER_STATE_DIR:-$HOME/.cache/textmate-whisper}"
LOCK_DIR="${STATE_ROOT}/.voice_input.lock"
LOCK_ACQUIRED=0

trim_text_file() {
  local file="$1"
  local content
  content="$(tr -d '\r' < "$file")"
  content="${content#"${content%%[![:space:]]*}"}"
  content="${content%"${content##*[![:space:]]}"}"
  printf '%s' "$content"
}

wait_for_input_file_stable() {
  local file="$1"
  local max_tries="${2:-12}"
  local sleep_sec="${3:-0.2}"
  local prev_size="-1"
  local stable_count=0
  local current_size=0
  local i

  for ((i = 0; i < max_tries; i++)); do
    current_size="$(stat -f '%z' "$file" 2>/dev/null || echo 0)"
    if [[ "$current_size" -gt 0 && "$current_size" -eq "$prev_size" ]]; then
      stable_count=$((stable_count + 1))
      if [[ "$stable_count" -ge 3 ]]; then
        break
      fi
    else
      stable_count=0
    fi
    prev_size="$current_size"
    sleep "$sleep_sec"
  done
}

write_runtime_snapshot() {
  local out_file="$1"
  {
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "script=$0"
    echo "mode=$MODE"
    echo "audio_file_input=${AUDIO_FILE_INPUT:-<none>}"
    echo "whisper_bin=${WHISPER_BIN:-<none>}"
    echo "ffmpeg_bin=${FFMPEG_BIN:-<none>}"
    echo "whisper_model=${WHISPER_MODEL:-<none>}"
    echo "whisper_lang=${WHISPER_LANG:-<none>}"
    echo "whisper_task=${WHISPER_TASK:-<none>}"
    echo "pwd=$(pwd)"
    echo "sw_vers=$(sw_vers 2>/dev/null | tr '\n' ';')"
    echo "python3=$(python3 --version 2>&1 || true)"
    echo "env_selected_begin"
    for key in \
      PATH HOME USER SHELL TMPDIR LANG LC_ALL LC_CTYPE \
      PYTHONPATH PYTHONHOME VIRTUAL_ENV CONDA_PREFIX \
      OBJC_DISABLE_INITIALIZE_FORK_SAFETY \
      MLX_USE_GPU MLX_METAL_DEVICE_WRAPPER_TYPE \
      DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH; do
      printf '%s=%s\n' "$key" "${!key:-}"
    done
    echo "env_selected_end"
  } > "$out_file"
}

persist_debug_artifacts() {
  local reason="${1:-unknown}"
  local target_dir="$SESSION_DIR"

  [[ -n "$target_dir" ]] || return 0
  [[ -d "$target_dir" ]] || return 0

  if [[ -f "${TMP_DIR}/whisper.stderr" ]]; then
    cp -f "${TMP_DIR}/whisper.stderr" "${target_dir}/whisper.stderr" 2>/dev/null || true
  fi
  if [[ -f "${TMP_DIR}/whisper.stdout" ]]; then
    cp -f "${TMP_DIR}/whisper.stdout" "${target_dir}/whisper.stdout" 2>/dev/null || true
  fi
  if [[ -f "${TMP_DIR}/ffmpeg-remux.stderr" ]]; then
    cp -f "${TMP_DIR}/ffmpeg-remux.stderr" "${target_dir}/ffmpeg-remux.stderr" 2>/dev/null || true
  fi
  if [[ -f "${TMP_DIR}/transcript.txt" ]]; then
    cp -f "${TMP_DIR}/transcript.txt" "${target_dir}/transcript-debug.txt" 2>/dev/null || true
  fi

  write_runtime_snapshot "${target_dir}/whisper-runtime.txt"
  append_log "INFO" "debug artifacts persisted reason=${reason} dir=${target_dir}"
}

acquire_transcribe_lock() {
  local tries="${1:-40}"
  local sleep_sec="${2:-0.1}"
  local i

  mkdir -p "$STATE_ROOT" >/dev/null 2>&1 || true
  for ((i = 0; i < tries; i++)); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      LOCK_ACQUIRED=1
      printf '%s\n' "$$" > "${LOCK_DIR}/pid" 2>/dev/null || true
      return 0
    fi
    sleep "$sleep_sec"
  done
  return 1
}

release_transcribe_lock() {
  if [[ "$LOCK_ACQUIRED" == "1" ]]; then
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    LOCK_ACQUIRED=0
  fi
}

postprocess_openai() {
  local in_file="$1"
  local out_file="$2"

  local api_base="${TM_OAI_BASE_URL:-${OPENAI_BASE_URL:-https://api.openai.com/v1}}"
  local api_key="${TM_OAI_API_KEY:-${OPENAI_API_KEY:-}}"
  local model="${TM_OAI_MODEL:-${OPENAI_MODEL:-gpt-4o-mini}}"
  local timeout_sec="${TM_OAI_TIMEOUT_SEC:-45}"

  if [[ -z "$api_key" ]]; then
    cp "$in_file" "$out_file"
    return 0
  fi

  local payload_file response_file
  payload_file="${TMP_DIR}/openai-payload.json"
  response_file="${TMP_DIR}/openai-response.json"

  TM_VOICE_USER_PROMPT="${TM_VOICE_USER_PROMPT:-}"
  TM_VOICE_POST_PROMPT="${TM_VOICE_POST_PROMPT:-}"
  TM_VOICE_POST_SYSTEM_PROMPT="${TM_VOICE_POST_SYSTEM_PROMPT:-}"
  TM_OAI_MODEL="$model" \
  python3 - "$in_file" > "$payload_file" <<'PY'
import json
import os
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").strip()
model = os.getenv("TM_OAI_MODEL", "gpt-4o-mini")
system_prompt = os.getenv(
    "TM_VOICE_POST_SYSTEM_PROMPT",
    "You are a writing assistant. Improve punctuation and readability while preserving meaning. Return only the rewritten text.",
).strip()
user_prompt = os.getenv("TM_VOICE_USER_PROMPT", "").strip() or os.getenv("TM_VOICE_POST_PROMPT", "").strip()
if not user_prompt:
    user_prompt = "Polish this transcript for written prose. Keep the original meaning and language."

payload = {
    "model": model,
    "temperature": 0.2,
    "messages": [
        {"role": "system", "content": system_prompt},
        {
            "role": "user",
            "content": f"Instruction:\n{user_prompt}\n\nTranscript:\n{text}",
        },
    ],
}
print(json.dumps(payload, ensure_ascii=False))
PY

  api_base="${api_base%/}"
  if ! curl -sS --fail-with-body \
      --max-time "$timeout_sec" \
      -H "Authorization: Bearer ${api_key}" \
      -H "Content-Type: application/json" \
      -d @"$payload_file" \
      "${api_base}/chat/completions" > "$response_file"; then
    cp "$in_file" "$out_file"
    return 0
  fi

  python3 - "$response_file" > "$out_file" <<'PY'
import json
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
obj = json.loads(p.read_text(encoding="utf-8", errors="ignore"))
choices = obj.get("choices") or []
if not choices:
    raise SystemExit(1)
msg = choices[0].get("message", {})
content = msg.get("content", "")
if isinstance(content, list):
    parts = []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text":
            parts.append(item.get("text", ""))
    content = "\n".join(parts)
content = (content or "").strip()
if not content:
    raise SystemExit(1)
print(content, end="")
PY
}

load_config_env "${TM_WHISPER_CONFIG_FILE:-$HOME/.config/textmate-whisper/config.env}" \
  TM_FFMPEG_BIN \
  TM_WHISPER_BIN \
  TM_WHISPER_MODEL \
  TM_WHISPER_LANG \
  TM_WHISPER_TASK \
  TM_WHISPER_MAX_SEC \
  TM_WHISPER_INPUT_DEVICE \
  TM_WHISPER_FORCE_CPU \
  TM_WHISPER_RETRY_CPU_ON_CRASH \
  TM_WHISPER_STATE_DIR \
  TM_VOICE_POSTPROCESS \
  TM_OAI_BASE_URL \
  TM_OAI_API_KEY \
  TM_OAI_MODEL \
  TM_OAI_TIMEOUT_SEC \
  TM_VOICE_POST_PROMPT \
  TM_VOICE_POST_SYSTEM_PROMPT \
  TM_WHISPER_LOG_DIR \
  TM_VOICE_SHOW_STATUS

if [[ -n "${TM_WHISPER_LOG_DIR:-}" ]]; then
  LOG_ROOT="${TM_WHISPER_LOG_DIR}"
  mkdir -p "$LOG_ROOT" >/dev/null 2>&1 || true
  LOG_FILE="$LOG_ROOT/voice_input-$(date +%Y%m%d).log"
fi

FFMPEG_BIN_RAW="${TM_FFMPEG_BIN:-ffmpeg}"
WHISPER_BIN_RAW="${TM_WHISPER_BIN:-mlx_whisper}"
FFMPEG_BIN="$(resolve_bin "$FFMPEG_BIN_RAW" || true)"
WHISPER_BIN="$(resolve_bin "$WHISPER_BIN_RAW" || true)"
WHISPER_MODEL="${TM_WHISPER_MODEL:-mlx-community/whisper-large-v3-turbo}"
WHISPER_LANG="${TM_WHISPER_LANG:-zh}"
WHISPER_TASK="${TM_WHISPER_TASK:-transcribe}"
WHISPER_MAX_SEC="${TM_WHISPER_MAX_SEC:-20}"
WHISPER_INPUT_DEVICE="${TM_WHISPER_INPUT_DEVICE:-auto}"
WHISPER_FORCE_CPU="${TM_WHISPER_FORCE_CPU:-0}"
WHISPER_RETRY_CPU_ON_CRASH="${TM_WHISPER_RETRY_CPU_ON_CRASH:-1}"
POSTPROCESS_MODE="$(printf '%s' "${TM_VOICE_POSTPROCESS:-auto}" | tr '[:upper:]' '[:lower:]')"
TM_VOICE_SHOW_STATUS="${TM_VOICE_SHOW_STATUS:-1}"

append_log "INFO" "start mode=$MODE audio_file_input=${AUDIO_FILE_INPUT:-<none>} model=${WHISPER_MODEL} postprocess=${POSTPROCESS_MODE}"
append_log "INFO" "bin ffmpeg=${FFMPEG_BIN:-<missing>} whisper=${WHISPER_BIN:-<missing>}"

if [[ ! "$MODE" =~ ^(insert|replace|preview|auto)$ ]]; then
  show_tip_and_exit "Unsupported mode: $MODE"
fi

if ! [[ "$WHISPER_MAX_SEC" =~ ^[0-9]+$ ]] || [[ "$WHISPER_MAX_SEC" -lt 3 ]] || [[ "$WHISPER_MAX_SEC" -gt 300 ]]; then
  show_tip_and_exit "TM_WHISPER_MAX_SEC must be an integer between 3 and 300."
fi

if [[ "$MODE" == "replace" && -z "${TM_SELECTED_TEXT:-}" ]]; then
  show_tip_and_exit "Replace mode requires a non-empty selection."
fi

if [[ -z "$AUDIO_FILE_INPUT" ]] && [[ -z "$FFMPEG_BIN" ]]; then
  show_tip_and_exit "ffmpeg not found. Install it or set TM_FFMPEG_BIN (current: ${FFMPEG_BIN_RAW})."
fi

if [[ -z "$WHISPER_BIN" ]]; then
  show_tip_and_exit "mlx_whisper not found. Install it or set TM_WHISPER_BIN (current: ${WHISPER_BIN_RAW})."
fi

if [[ -z "$AUDIO_FILE_INPUT" && "$DRY_RUN" != "1" ]]; then
  requested_input_device="$WHISPER_INPUT_DEVICE"
  if ! WHISPER_INPUT_DEVICE="$(validate_and_resolve_input_device "$requested_input_device")"; then
    append_log "WARN" "invalid input device config: $requested_input_device"
    if [[ "$requested_input_device" != "auto" ]] && WHISPER_INPUT_DEVICE="$(validate_and_resolve_input_device "auto")"; then
      append_log "WARN" "fallback input device to auto from: $requested_input_device"
    else
      show_tip_and_exit "$WHISPER_INPUT_DEVICE"
    fi
  fi
fi

if [[ "$DRY_RUN" == "1" ]]; then
  append_log "INFO" "dry-run success mode=$MODE postprocess=$POSTPROCESS_MODE"
  printf 'DRY_RUN_OK mode=%s postprocess=%s\n' "$MODE" "$POSTPROCESS_MODE"
  exit 0
fi

TMP_DIR="$(mktemp -d /tmp/tm-whisper-XXXXXX)"
AUDIO_FILE="${TMP_DIR}/voice.wav"
RAW_TXT="${TMP_DIR}/raw.txt"
FINAL_TXT="${TMP_DIR}/final.txt"

cleanup() {
  release_transcribe_lock
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! acquire_transcribe_lock 40 0.1; then
  show_tip_and_exit "Another transcription is running. Try again in 2-3 seconds."
fi

if [[ -n "$AUDIO_FILE_INPUT" ]]; then
  if [[ ! -s "$AUDIO_FILE_INPUT" ]]; then
    show_tip_and_exit "Input audio file is missing or empty: $AUDIO_FILE_INPUT"
  fi
  SESSION_DIR="$(dirname "$AUDIO_FILE_INPUT")"
  wait_for_input_file_stable "$AUDIO_FILE_INPUT" 12 0.2
  # Re-mux to a stable mono 16k PCM file to avoid occasional partial WAV state right after recording stop.
  if [[ -n "${FFMPEG_BIN:-}" ]]; then
    if ! "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error \
      -i "$AUDIO_FILE_INPUT" -ac 1 -ar 16000 -c:a pcm_s16le "$AUDIO_FILE" 2>"${TMP_DIR}/ffmpeg-remux.stderr"; then
      append_log "WARN" "ffmpeg remux failed, fallback to raw copy: $(tr '\n' ' ' < "${TMP_DIR}/ffmpeg-remux.stderr" | head -c 240)"
      cp "$AUDIO_FILE_INPUT" "$AUDIO_FILE"
    fi
  else
    cp "$AUDIO_FILE_INPUT" "$AUDIO_FILE"
  fi
  append_log "INFO" "using external audio file: $AUDIO_FILE_INPUT"
else
  status_notify "Recording" "Speak now. Max ${WHISPER_MAX_SEC}s."
  if ! "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error \
      -f avfoundation -i "$WHISPER_INPUT_DEVICE" \
      -ac 1 -ar 16000 -t "$WHISPER_MAX_SEC" "$AUDIO_FILE" 2>"${TMP_DIR}/ffmpeg.stderr"; then
    if grep -qi "Permission denied\\|not authorized\\|Operation not permitted" "${TMP_DIR}/ffmpeg.stderr"; then
      show_tip_and_exit "Recording failed: microphone permission denied for TextMate."
    fi
    show_tip_and_exit "Recording failed. Check TM_WHISPER_INPUT_DEVICE (default auto) and microphone input."
  fi
  append_log "INFO" "recording finished to $AUDIO_FILE"
fi

status_notify "Transcribing" "Converting speech to text..."

run_whisper_transcribe() {
  local model="$1"
  local lang="${2:-$WHISPER_LANG}"
  local force_cpu="${3:-$WHISPER_FORCE_CPU}"
  local whisper_cmd

  whisper_cmd=(
    "$WHISPER_BIN" "$AUDIO_FILE"
    --model "$model"
    --task "$WHISPER_TASK"
    --output-dir "$TMP_DIR"
    --output-name transcript
    --output-format txt
    --verbose False
  )

  if [[ -n "$lang" && "$lang" != "auto" && "$lang" != "none" ]]; then
    whisper_cmd+=(--language "$lang")
  fi

  if is_truthy "$force_cpu"; then
    MLX_USE_GPU=0 "${whisper_cmd[@]}" >"${TMP_DIR}/whisper.stdout" 2>"${TMP_DIR}/whisper.stderr"
  else
    "${whisper_cmd[@]}" >"${TMP_DIR}/whisper.stdout" 2>"${TMP_DIR}/whisper.stderr"
  fi
}

wait_for_transcript_file() {
  local tries="${1:-5}"
  local sleep_sec="${2:-0.3}"
  local i

  for ((i = 0; i < tries; i++)); do
    if [[ -s "${TMP_DIR}/transcript.txt" ]]; then
      return 0
    fi
    sleep "$sleep_sec"
  done

  [[ -s "${TMP_DIR}/transcript.txt" ]]
}

if ! run_whisper_transcribe "$WHISPER_MODEL" "$WHISPER_LANG"; then
  if grep -qi "Traceback (most recent call last)" "${TMP_DIR}/whisper.stderr" \
    && is_truthy "$WHISPER_RETRY_CPU_ON_CRASH" \
    && ! is_truthy "$WHISPER_FORCE_CPU"; then
    append_log "WARN" "mlx traceback detected on initial run, retrying with CPU mode (MLX_USE_GPU=0)."
    rm -f "${TMP_DIR}/transcript.txt"
    if run_whisper_transcribe "$WHISPER_MODEL" "$WHISPER_LANG" "1"; then
      append_log "INFO" "cpu fallback succeeded after initial traceback."
    else
      append_log "WARN" "cpu fallback failed after initial traceback."
    fi
  fi
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]] && grep -qi "Traceback (most recent call last)" "${TMP_DIR}/whisper.stderr" \
  && is_truthy "$WHISPER_RETRY_CPU_ON_CRASH" \
  && ! is_truthy "$WHISPER_FORCE_CPU"; then
  append_log "WARN" "traceback persists with missing transcript, retrying CPU+auto language."
  rm -f "${TMP_DIR}/transcript.txt"
  run_whisper_transcribe "$WHISPER_MODEL" "auto" "1" || true
  wait_for_transcript_file 4 0.2 || true
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]] && ! grep -qi "RepositoryNotFoundError\\|Repository Not Found\\|404 Not Found" "${TMP_DIR}/whisper.stderr" "${TMP_DIR}/whisper.stdout" 2>/dev/null; then
  append_log "ERROR" "transcribe failed model=$WHISPER_MODEL stderr_file=${SESSION_DIR:-<none>}/whisper.stderr"
  if grep -qi "No module named\\|not found\\|No such file" "${TMP_DIR}/whisper.stderr"; then
    persist_debug_artifacts "transcribe-failed-dependency"
    show_tip_and_exit "Transcription failed: whisper runtime/dependency missing."
  fi
  # Keep flowing into fallback/retry branches when applicable.
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]] \
  && grep -qi "RepositoryNotFoundError\\|Repository Not Found\\|404 Not Found" "${TMP_DIR}/whisper.stderr" "${TMP_DIR}/whisper.stdout" 2>/dev/null \
  && [[ "$WHISPER_MODEL" != "mlx-community/whisper-tiny" ]]; then
  rm -f "${TMP_DIR}/transcript.txt"
  status_notify "Transcribing" "Model unavailable, fallback to whisper-tiny..."
  append_log "WARN" "model unavailable, fallback to whisper-tiny from $WHISPER_MODEL"
  if ! run_whisper_transcribe "mlx-community/whisper-tiny" "$WHISPER_LANG"; then
    persist_debug_artifacts "transcribe-failed-fallback-model"
    append_log "ERROR" "fallback transcribe failed stderr_file=${SESSION_DIR:-<none>}/whisper.stderr"
    show_tip_and_exit "Transcription failed: model unavailable and fallback failed."
  fi
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]]; then
  append_log "WARN" "transcript missing after first pass, waiting for file visibility."
  if wait_for_transcript_file 5 0.3; then
    append_log "INFO" "transcript became visible after filesystem wait."
  fi
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]]; then
  append_log "WARN" "transcript still missing after wait, retry with same language."
  rm -f "${TMP_DIR}/transcript.txt"
  if ! run_whisper_transcribe "$WHISPER_MODEL" "$WHISPER_LANG"; then
    append_log "WARN" "retry failed model=$WHISPER_MODEL stderr=$(tr '\n' ' ' < "${TMP_DIR}/whisper.stderr" | head -c 300)"
  fi
  if wait_for_transcript_file 3 0.2; then
    append_log "INFO" "transcript available after same-language retry."
  fi
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]] && [[ -n "$WHISPER_LANG" && "$WHISPER_LANG" != "auto" && "$WHISPER_LANG" != "none" ]]; then
  append_log "WARN" "transcript still missing, retry with language auto-detect from $WHISPER_LANG."
  rm -f "${TMP_DIR}/transcript.txt"
  if ! run_whisper_transcribe "$WHISPER_MODEL" "auto"; then
    append_log "WARN" "auto-language retry failed model=$WHISPER_MODEL stderr=$(tr '\n' ' ' < "${TMP_DIR}/whisper.stderr" | head -c 300)"
  fi
  if wait_for_transcript_file 3 0.2; then
    append_log "INFO" "transcript available after auto-language retry."
  fi
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]]; then
  persist_debug_artifacts "transcript-missing-final"
  append_log "WARN" "final transcript missing; stderr_file=${SESSION_DIR:-<none>}/whisper.stderr"
  if grep -qi "RepositoryNotFoundError\\|Repository Not Found\\|404 Not Found" "${TMP_DIR}/whisper.stderr" "${TMP_DIR}/whisper.stdout" 2>/dev/null; then
    show_tip_and_exit "Transcription failed: TM_WHISPER_MODEL repo not found. Try mlx-community/whisper-tiny."
  fi
  if grep -qi "Traceback (most recent call last)" "${TMP_DIR}/whisper.stderr"; then
    show_tip_and_exit "Transcription failed: mlx_whisper crashed. See whisper.stderr in session folder."
  fi
  show_tip_and_exit "No speech detected. Try speaking louder or increase TM_WHISPER_MAX_SEC."
fi

trim_text_file "${TMP_DIR}/transcript.txt" > "$RAW_TXT"
if [[ ! -s "$RAW_TXT" ]]; then
  show_tip_and_exit "Transcript is empty. Try longer recording (TM_WHISPER_MAX_SEC=30)."
fi

POSTPROCESS_ENABLED=0
case "$POSTPROCESS_MODE" in
  off|none|0|false|no)
    POSTPROCESS_ENABLED=0
    ;;
  openai|openai-compatible|1|true|yes)
    POSTPROCESS_ENABLED=1
    ;;
  auto|"")
    if [[ -n "${TM_OAI_API_KEY:-${OPENAI_API_KEY:-}}" ]]; then
      POSTPROCESS_ENABLED=1
    fi
    ;;
  *)
    if [[ -n "${TM_OAI_API_KEY:-${OPENAI_API_KEY:-}}" ]]; then
      POSTPROCESS_ENABLED=1
    fi
    ;;
esac

if [[ "$POSTPROCESS_ENABLED" == "1" ]]; then
  status_notify "Polishing" "Applying OpenAI-compatible post-edit..."
  if ! postprocess_openai "$RAW_TXT" "$FINAL_TXT"; then
    cp "$RAW_TXT" "$FINAL_TXT"
  fi
else
  cp "$RAW_TXT" "$FINAL_TXT"
fi

EFFECTIVE_MODE="$MODE"
if [[ "$MODE" == "auto" ]]; then
  if [[ -n "${TM_SELECTED_TEXT:-}" ]]; then
    EFFECTIVE_MODE="replace"
  else
    EFFECTIVE_MODE="insert"
  fi
fi

case "$EFFECTIVE_MODE" in
  insert)
    status_notify "Done" "Transcript inserted at caret."
    ;;
  replace)
    status_notify "Done" "Selection replaced with transcript."
    ;;
  preview)
    status_notify "Done" "Draft opened in preview window."
    ;;
  *)
    status_notify "Done" "Transcript is ready."
    ;;
esac

result_text="$(trim_text_file "$FINAL_TXT")"
append_log "INFO" "success mode=$MODE effective_mode=$EFFECTIVE_MODE postprocess=$POSTPROCESS_MODE enabled=$POSTPROCESS_ENABLED output_chars=$(printf '%s' "$result_text" | wc -m | tr -d ' ')"
printf '%s' "$result_text"
