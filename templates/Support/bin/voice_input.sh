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

trim_text_file() {
  local file="$1"
  local content
  content="$(tr -d '\r' < "$file")"
  content="${content#"${content%%[![:space:]]*}"}"
  content="${content%"${content##*[![:space:]]}"}"
  printf '%s' "$content"
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
WHISPER_MODEL="${TM_WHISPER_MODEL:-mlx-community/whisper-tiny}"
WHISPER_LANG="${TM_WHISPER_LANG:-zh}"
WHISPER_TASK="${TM_WHISPER_TASK:-transcribe}"
WHISPER_MAX_SEC="${TM_WHISPER_MAX_SEC:-20}"
WHISPER_INPUT_DEVICE="${TM_WHISPER_INPUT_DEVICE:-auto}"
POSTPROCESS_MODE="${TM_VOICE_POSTPROCESS:-none}"
TM_VOICE_SHOW_STATUS="${TM_VOICE_SHOW_STATUS:-1}"

append_log "INFO" "start mode=$MODE audio_file_input=${AUDIO_FILE_INPUT:-<none>} model=${WHISPER_MODEL} postprocess=${POSTPROCESS_MODE}"
append_log "INFO" "bin ffmpeg=${FFMPEG_BIN:-<missing>} whisper=${WHISPER_BIN:-<missing>}"

if [[ ! "$MODE" =~ ^(insert|replace|preview)$ ]]; then
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
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ -n "$AUDIO_FILE_INPUT" ]]; then
  if [[ ! -s "$AUDIO_FILE_INPUT" ]]; then
    show_tip_and_exit "Input audio file is missing or empty: $AUDIO_FILE_INPUT"
  fi
  cp "$AUDIO_FILE_INPUT" "$AUDIO_FILE"
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

  if [[ -n "$WHISPER_LANG" && "$WHISPER_LANG" != "auto" && "$WHISPER_LANG" != "none" ]]; then
    whisper_cmd+=(--language "$WHISPER_LANG")
  fi

  "${whisper_cmd[@]}" >"${TMP_DIR}/whisper.stdout" 2>"${TMP_DIR}/whisper.stderr"
}

if ! run_whisper_transcribe "$WHISPER_MODEL"; then
  append_log "ERROR" "transcribe failed model=$WHISPER_MODEL stderr=$(tr '\n' ' ' < "${TMP_DIR}/whisper.stderr" | head -c 300)"
  if grep -qi "No module named\\|not found\\|No such file" "${TMP_DIR}/whisper.stderr"; then
    show_tip_and_exit "Transcription failed: whisper runtime/dependency missing."
  fi
  show_tip_and_exit "Transcription failed. Check TM_WHISPER_MODEL and mlx_whisper runtime."
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]] \
  && grep -qi "RepositoryNotFoundError\\|Repository Not Found\\|404 Not Found" "${TMP_DIR}/whisper.stderr" "${TMP_DIR}/whisper.stdout" 2>/dev/null \
  && [[ "$WHISPER_MODEL" != "mlx-community/whisper-tiny" ]]; then
  rm -f "${TMP_DIR}/transcript.txt"
  status_notify "Transcribing" "Model unavailable, fallback to whisper-tiny..."
  append_log "WARN" "model unavailable, fallback to whisper-tiny from $WHISPER_MODEL"
  if ! run_whisper_transcribe "mlx-community/whisper-tiny"; then
    append_log "ERROR" "fallback transcribe failed stderr=$(tr '\n' ' ' < "${TMP_DIR}/whisper.stderr" | head -c 300)"
    show_tip_and_exit "Transcription failed: model unavailable and fallback failed."
  fi
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]]; then
  if grep -qi "RepositoryNotFoundError\\|Repository Not Found\\|404 Not Found" "${TMP_DIR}/whisper.stderr" "${TMP_DIR}/whisper.stdout" 2>/dev/null; then
    show_tip_and_exit "Transcription failed: TM_WHISPER_MODEL repo not found. Try mlx-community/whisper-tiny."
  fi
  show_tip_and_exit "No speech detected. Try speaking louder or increase TM_WHISPER_MAX_SEC."
fi

trim_text_file "${TMP_DIR}/transcript.txt" > "$RAW_TXT"
if [[ ! -s "$RAW_TXT" ]]; then
  show_tip_and_exit "Transcript is empty. Try longer recording (TM_WHISPER_MAX_SEC=30)."
fi

case "$POSTPROCESS_MODE" in
  openai|openai-compatible|1|true|yes)
    status_notify "Polishing" "Applying OpenAI-compatible post-edit..."
    if ! postprocess_openai "$RAW_TXT" "$FINAL_TXT"; then
      cp "$RAW_TXT" "$FINAL_TXT"
    fi
    ;;
  *)
    cp "$RAW_TXT" "$FINAL_TXT"
    ;;
esac

case "$MODE" in
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
append_log "INFO" "success mode=$MODE output_chars=$(printf '%s' "$result_text" | wc -m | tr -d ' ')"
printf '%s' "$result_text"
