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
POST_CONTEXT_BEFORE=""
POST_CONTEXT_AFTER=""

trim_text_file() {
  local file="$1"
  local content
  content="$(tr -d '\r' < "$file")"
  content="${content#"${content%%[![:space:]]*}"}"
  content="${content%"${content##*[![:space:]]}"}"
  printf '%s' "$content"
}

capture_context_window_from_file() {
  local before_chars="$1"
  local after_chars="$2"
  local out_before="$3"
  local out_after="$4"

  [[ -n "${TM_FILEPATH:-}" ]] || return 1
  [[ -r "${TM_FILEPATH:-}" ]] || return 1
  [[ "${TM_LINE_NUMBER:-}" =~ ^[0-9]+$ ]] || return 1
  [[ "${TM_COLUMN_NUMBER:-}" =~ ^[0-9]+$ ]] || return 1

  TM_VOICE_CONTEXT_FILE="$TM_FILEPATH" \
  TM_VOICE_CONTEXT_LINE="$TM_LINE_NUMBER" \
  TM_VOICE_CONTEXT_COL="$TM_COLUMN_NUMBER" \
  TM_VOICE_CONTEXT_BEFORE_N="$before_chars" \
  TM_VOICE_CONTEXT_AFTER_N="$after_chars" \
  python3 - "$out_before" "$out_after" <<'PY'
import os
from pathlib import Path
import sys

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
file_path = Path(os.environ["TM_VOICE_CONTEXT_FILE"])
line_num = int(os.environ["TM_VOICE_CONTEXT_LINE"])
col_num = int(os.environ["TM_VOICE_CONTEXT_COL"])
before_n = max(0, int(os.environ["TM_VOICE_CONTEXT_BEFORE_N"]))
after_n = max(0, int(os.environ["TM_VOICE_CONTEXT_AFTER_N"]))

text = file_path.read_text(encoding="utf-8", errors="ignore")
if not text:
    before_path.write_text("", encoding="utf-8")
    after_path.write_text("", encoding="utf-8")
    raise SystemExit(0)

lines = text.splitlines(keepends=True)
if not lines:
    offset = 0
else:
    line_num = max(1, min(line_num, len(lines)))
    prefix = sum(len(lines[i]) for i in range(line_num - 1))
    line_text = lines[line_num - 1]
    line_text_no_newline = line_text.rstrip("\r\n")
    col_index = max(0, min(col_num - 1, len(line_text_no_newline)))
    offset = min(len(text), prefix + col_index)

before = text[max(0, offset - before_n):offset]
after = text[offset:offset + after_n]
before_path.write_text(before, encoding="utf-8")
after_path.write_text(after, encoding="utf-8")
PY
}

capture_context_window_from_current_line() {
  local before_chars="$1"
  local after_chars="$2"
  local out_before="$3"
  local out_after="$4"
  local line col raw_col col_index prefix suffix

  line="${TM_CURRENT_LINE:-}"
  col="${TM_COLUMN_NUMBER:-1}"
  if [[ ! "$col" =~ ^[0-9]+$ ]]; then
    col=1
  fi
  raw_col=$((col - 1))
  if (( raw_col < 0 )); then
    raw_col=0
  fi

  if (( raw_col > ${#line} )); then
    col_index=${#line}
  else
    col_index=$raw_col
  fi

  prefix="${line:0:col_index}"
  suffix="${line:col_index}"
  if (( ${#prefix} > before_chars )); then
    prefix="${prefix: -before_chars}"
  fi
  if (( ${#suffix} > after_chars )); then
    suffix="${suffix:0:after_chars}"
  fi

  printf '%s' "$prefix" > "$out_before"
  printf '%s' "$suffix" > "$out_after"
}

collect_postprocess_context_window() {
  local before_chars="$1"
  local after_chars="$2"
  local before_file after_file

  POST_CONTEXT_BEFORE=""
  POST_CONTEXT_AFTER=""
  if (( before_chars <= 0 && after_chars <= 0 )); then
    return 0
  fi

  before_file="${TMP_DIR}/context-before.txt"
  after_file="${TMP_DIR}/context-after.txt"

  if ! capture_context_window_from_file "$before_chars" "$after_chars" "$before_file" "$after_file"; then
    capture_context_window_from_current_line "$before_chars" "$after_chars" "$before_file" "$after_file" || true
  fi

  if [[ -f "$before_file" ]]; then
    POST_CONTEXT_BEFORE="$(trim_text_file "$before_file")"
  fi
  if [[ -f "$after_file" ]]; then
    POST_CONTEXT_AFTER="$(trim_text_file "$after_file")"
  fi

  append_log "INFO" "postprocess context window before_chars=$(printf '%s' "$POST_CONTEXT_BEFORE" | wc -m | tr -d ' ') after_chars=$(printf '%s' "$POST_CONTEXT_AFTER" | wc -m | tr -d ' ')"
}

normalize_post_output_lang() {
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
      printf 'invalid\n'
      ;;
  esac
}

post_output_lang_name() {
  local normalized="${1:-auto}"
  case "$normalized" in
    en)
      printf 'English\n'
      ;;
    zh)
      printf 'Simplified Chinese\n'
      ;;
    ja)
      printf 'Japanese\n'
      ;;
    ko)
      printf 'Korean\n'
      ;;
    *)
      printf 'Original transcript language\n'
      ;;
  esac
}

looks_like_ai_refusal_response() {
  local text="$1"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *"i apologize"*|*"cannot work with the text"*|*"incomplete or corrupted"*|*"please share it"*|*"please share"*|*"cannot help with that request"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_punctuation_only_edit() {
  local original="$1"
  local edited="$2"
  TM_VOICE_ORIGINAL_TEXT="$original" TM_VOICE_EDITED_TEXT="$edited" python3 - <<'PY'
import os
import unicodedata

orig = os.getenv("TM_VOICE_ORIGINAL_TEXT", "")
edit = os.getenv("TM_VOICE_EDITED_TEXT", "")

def strip_punct_and_space(text: str) -> str:
    out = []
    for ch in text:
        if ch.isspace():
            continue
        if unicodedata.category(ch).startswith("P"):
            continue
        out.append(ch)
    return "".join(out)

raise SystemExit(0 if strip_punct_and_space(orig) == strip_punct_and_space(edit) else 1)
PY
}

exit_with_empty_output() {
  local reason="${1:-empty_output}"
  append_log "INFO" "empty output suppressed reason=${reason}"
  exit 0
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
  local post_lang_raw post_lang_normalized post_lang_name
  local context_before context_after

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
  post_lang_raw="${TM_VOICE_POST_OUTPUT_LANG:-auto}"
  post_lang_normalized="$(normalize_post_output_lang "$post_lang_raw")"
  if [[ "$post_lang_normalized" == "invalid" ]]; then
    append_log "WARN" "unknown TM_VOICE_POST_OUTPUT_LANG=${post_lang_raw}, fallback to auto"
    post_lang_normalized="auto"
  fi
  post_lang_name="$(post_output_lang_name "$post_lang_normalized")"
  context_before="${POST_CONTEXT_BEFORE:-}"
  context_after="${POST_CONTEXT_AFTER:-}"
  TM_OAI_MODEL="$model" \
  TM_VOICE_POST_OUTPUT_LANG_NORM="$post_lang_normalized" \
  TM_VOICE_POST_OUTPUT_LANG_NAME="$post_lang_name" \
  TM_VOICE_CONTEXT_BEFORE="$context_before" \
  TM_VOICE_CONTEXT_AFTER="$context_after" \
  python3 - "$in_file" > "$payload_file" <<'PY'
import json
import os
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").strip()
model = os.getenv("TM_OAI_MODEL", "gpt-4o-mini")
lang_mode = os.getenv("TM_VOICE_POST_OUTPUT_LANG_NORM", "auto").strip().lower()
lang_name = os.getenv("TM_VOICE_POST_OUTPUT_LANG_NAME", "Original transcript language").strip()
context_before = os.getenv("TM_VOICE_CONTEXT_BEFORE", "").strip()
context_after = os.getenv("TM_VOICE_CONTEXT_AFTER", "").strip()
default_system_prompt = (
    "You are a strict transcript punctuation corrector. "
    "Only correct punctuation and spacing. "
    "Keep words, characters, order, and meaning unchanged. "
    "Do not paraphrase, summarize, rewrite, translate, or expand. "
    "Return only the corrected text."
)
system_prompt = os.getenv("TM_VOICE_POST_SYSTEM_PROMPT", default_system_prompt).strip()
legacy_system_prompt = "You are a writing assistant. Improve punctuation and readability while preserving meaning. Return only the rewritten text."
legacy_system_prompt_v2 = (
    "You are a strict transcript post-editor. Do minimal edits only: punctuation, spacing, and obvious ASR mistakes. "
    "Preserve wording, line breaks, tone, imagery, and sentence order. Do not paraphrase, summarize, embellish, or expand. "
    "Return only the edited text."
)
legacy_system_prompt_v3 = (
    "You are a strict transcript post-editor. Do minimal edits only: punctuation, spacing, and obvious ASR mistakes. "
    "Preserve wording, line breaks, tone, imagery, and sentence order. For Chinese content, prefer Simplified Chinese and "
    "correct obvious homophone ASR errors. Do not paraphrase, summarize, embellish, or expand. Return only the edited text."
)
if system_prompt in {legacy_system_prompt, legacy_system_prompt_v2, legacy_system_prompt_v3}:
    system_prompt = default_system_prompt

raw_user_prompt = os.getenv("TM_VOICE_USER_PROMPT", "").strip() or os.getenv("TM_VOICE_POST_PROMPT", "").strip()
legacy_user_prompt = "Polish this transcript into concise writing."
legacy_user_prompt_v2 = "Minimal edit only: fix punctuation, spacing, and obvious ASR errors. Keep original wording and line breaks."
legacy_user_prompt_v3 = (
    "Minimal edit only: fix punctuation, spacing, and obvious ASR errors. Keep original wording and line breaks. "
    "If the transcript is Chinese, correct obvious homophone misrecognitions while keeping Simplified Chinese."
)
if raw_user_prompt in {legacy_user_prompt, legacy_user_prompt_v2, legacy_user_prompt_v3}:
    raw_user_prompt = ""

user_prompt = raw_user_prompt
if not user_prompt:
    if lang_mode == "auto":
        user_prompt = "Punctuation-only pass: add/fix punctuation and spacing. Do not change words or meaning."
    else:
        user_prompt = (
            f"Translate the transcript faithfully to {lang_name}. "
            "Keep line structure as much as possible, and avoid embellishment."
        )
else:
    if lang_mode == "auto":
        user_prompt = (
            f"{user_prompt} Apply punctuation-only correction. "
            "Do not rewrite wording or meaning."
        ).strip()
    else:
        user_prompt = (
            f"{user_prompt} Required output language: {lang_name}. "
            f"Translate faithfully to {lang_name} and output only {lang_name}. "
            "Avoid paraphrasing and embellishment."
        ).strip()

if lang_mode != "auto":
    system_prompt = (
        f"{system_prompt} Strict requirement: final output must be entirely in {lang_name}. "
        "Do not mix languages."
    ).strip()
if context_before or context_after:
    system_prompt = (
        f"{system_prompt} Use context snippets only for continuity and terminology; "
        "do not copy context text verbatim."
    ).strip()

content_parts = [f"Instruction:\n{user_prompt}"]
if context_before:
    content_parts.append(
        "Context Before Caret (reference only):\n"
        f"{context_before}"
    )
content_parts.append(f"Transcript:\n{text}")
if context_after:
    content_parts.append(
        "Context After Caret (reference only):\n"
        f"{context_after}"
    )
user_content = "\n\n".join(content_parts)

payload = {
    "model": model,
    "temperature": 0.0,
    "messages": [
        {"role": "system", "content": system_prompt},
        {
            "role": "user",
            "content": user_content,
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
  TM_VOICE_POST_OUTPUT_LANG \
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

ensure_bin_dir_in_path() {
  local bin_path="$1"
  local bin_dir
  [[ -n "$bin_path" ]] || return 0
  bin_dir="$(dirname "$bin_path")"
  case ":${PATH:-}:" in
    *":${bin_dir}:"*) ;;
    *) export PATH="${bin_dir}:${PATH:-}" ;;
  esac
}

# mlx_whisper internally runs `ffmpeg` by command name.
# TextMate runtime PATH may miss Homebrew bin, so inject resolved ffmpeg dir.
ensure_bin_dir_in_path "$FFMPEG_BIN"

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
  wait_for_file_stable "$AUDIO_FILE_INPUT" 12 0.2
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
  if grep -qi "FileNotFoundError: .*ffmpeg\\|No such file or directory: 'ffmpeg'" "${TMP_DIR}/whisper.stderr" "${TMP_DIR}/whisper.stdout"; then
    persist_debug_artifacts "transcribe-failed-ffmpeg-path"
    show_tip_and_exit "Transcription failed: ffmpeg not found in TextMate runtime PATH. Set TM_FFMPEG_BIN=/opt/homebrew/bin/ffmpeg, then reload bundles."
  fi
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
  exit_with_empty_output "no_speech_detected"
fi

trim_text_file "${TMP_DIR}/transcript.txt" > "$RAW_TXT"
if [[ ! -s "$RAW_TXT" ]]; then
  exit_with_empty_output "empty_raw_transcript"
fi
raw_text="$(trim_text_file "$RAW_TXT")"

POSTPROCESS_ENABLED=0
case "$POSTPROCESS_MODE" in
  off|none|0|false|no)
    POSTPROCESS_ENABLED=0
    ;;
  openai|openai-compatible|1|true|yes)
    POSTPROCESS_ENABLED=1
    ;;
  auto|""|*)
    if [[ -n "$POSTPROCESS_MODE" && "$POSTPROCESS_MODE" != "auto" ]]; then
      append_log "WARN" "unknown postprocess mode=${POSTPROCESS_MODE}, treating as auto"
    fi
    if [[ -n "${TM_OAI_API_KEY:-${OPENAI_API_KEY:-}}" ]]; then
      POSTPROCESS_ENABLED=1
    fi
    ;;
esac

if [[ "$POSTPROCESS_ENABLED" == "1" ]]; then
  collect_postprocess_context_window 200 200
  status_notify "Polishing" "🪩 AI后处理..."
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

result_text="$(trim_text_file "$FINAL_TXT")"
result_text="$(printf '%s' "$result_text" | sed -E 's/^Recording started\. Press Option\+Command\+F1 to stop\.//')"
result_text="$(printf '%s' "$result_text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ "$POSTPROCESS_ENABLED" == "1" ]] && looks_like_ai_refusal_response "$result_text"; then
  raw_chars="$(printf '%s' "$raw_text" | wc -m | tr -d ' ')"
  append_log "WARN" "postprocess returned non-content/refusal text, raw_chars=${raw_chars}"
  if [[ "$raw_chars" -le 12 ]]; then
    exit_with_empty_output "postprocess_refusal_with_short_raw"
  fi
  result_text="$raw_text"
fi

if [[ "$POSTPROCESS_ENABLED" == "1" ]]; then
  post_output_lang_norm="$(normalize_post_output_lang "${TM_VOICE_POST_OUTPUT_LANG:-auto}")"
  if [[ "$post_output_lang_norm" == "auto" ]] && ! is_punctuation_only_edit "$raw_text" "$result_text"; then
    append_log "WARN" "postprocess changed non-punctuation content in punct-only mode, fallback to raw transcript"
    result_text="$raw_text"
  fi
fi

if [[ -z "$result_text" ]]; then
  exit_with_empty_output "empty_final_output"
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

append_log "INFO" "success mode=$MODE effective_mode=$EFFECTIVE_MODE postprocess=$POSTPROCESS_MODE enabled=$POSTPROCESS_ENABLED output_chars=$(printf '%s' "$result_text" | wc -m | tr -d ' ')"
printf '%s' "$result_text"
