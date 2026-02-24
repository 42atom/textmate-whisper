#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${TM_SUPPORT_PATH:-}" && -f "${TM_SUPPORT_PATH}/lib/bash_init.sh" ]]; then
  # shellcheck source=/dev/null
  . "${TM_SUPPORT_PATH}/lib/bash_init.sh"
fi

MODE="insert"

while [[ $# -gt 0 ]]; do
  case "$1" in
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

show_tip_and_exit() {
  local msg="$1"
  if declare -F exit_show_tool_tip >/dev/null 2>&1; then
    exit_show_tool_tip "$msg"
  fi
  echo "$msg" >&2
  exit 1
}

trim_text_file() {
  local file="$1"
  python3 - "$file" <<'PY'
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8", errors="ignore").replace("\r", "")
print(t.strip(), end="")
PY
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

FFMPEG_BIN="${TM_FFMPEG_BIN:-ffmpeg}"
WHISPER_BIN="${TM_WHISPER_BIN:-mlx_whisper}"
WHISPER_MODEL="${TM_WHISPER_MODEL:-mlx-community/whisper-small}"
WHISPER_LANG="${TM_WHISPER_LANG:-zh}"
WHISPER_TASK="${TM_WHISPER_TASK:-transcribe}"
WHISPER_MAX_SEC="${TM_WHISPER_MAX_SEC:-20}"
WHISPER_INPUT_DEVICE="${TM_WHISPER_INPUT_DEVICE:-:0}"
POSTPROCESS_MODE="${TM_VOICE_POSTPROCESS:-none}"

if ! [[ "$WHISPER_MAX_SEC" =~ ^[0-9]+$ ]] || [[ "$WHISPER_MAX_SEC" -lt 3 ]] || [[ "$WHISPER_MAX_SEC" -gt 300 ]]; then
  show_tip_and_exit "TM_WHISPER_MAX_SEC must be an integer between 3 and 300."
fi

if [[ "$MODE" == "replace" && -z "${TM_SELECTED_TEXT:-}" ]]; then
  show_tip_and_exit "Replace mode requires a non-empty selection."
fi

if ! command -v "$FFMPEG_BIN" >/dev/null 2>&1; then
  show_tip_and_exit "ffmpeg not found. Install it or set TM_FFMPEG_BIN."
fi

if ! command -v "$WHISPER_BIN" >/dev/null 2>&1; then
  show_tip_and_exit "mlx_whisper not found. Install it or set TM_WHISPER_BIN."
fi

TMP_DIR="$(mktemp -d /tmp/tm-whisper-XXXXXX)"
AUDIO_FILE="${TMP_DIR}/voice.wav"
RAW_TXT="${TMP_DIR}/raw.txt"
FINAL_TXT="${TMP_DIR}/final.txt"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error \
    -f avfoundation -i "$WHISPER_INPUT_DEVICE" \
    -ac 1 -ar 16000 -t "$WHISPER_MAX_SEC" "$AUDIO_FILE"; then
  show_tip_and_exit "Recording failed. Check microphone permissions and TM_WHISPER_INPUT_DEVICE (default :0)."
fi

whisper_cmd=(
  "$WHISPER_BIN" "$AUDIO_FILE"
  --model "$WHISPER_MODEL"
  --task "$WHISPER_TASK"
  --output-dir "$TMP_DIR"
  --output-name transcript
  --output-format txt
  --verbose False
)

if [[ -n "$WHISPER_LANG" && "$WHISPER_LANG" != "auto" && "$WHISPER_LANG" != "none" ]]; then
  whisper_cmd+=(--language "$WHISPER_LANG")
fi

if ! "${whisper_cmd[@]}" >/dev/null 2>"${TMP_DIR}/whisper.stderr"; then
  show_tip_and_exit "Transcription failed. Check model or mlx_whisper runtime."
fi

if [[ ! -s "${TMP_DIR}/transcript.txt" ]]; then
  show_tip_and_exit "Whisper returned empty transcript."
fi

trim_text_file "${TMP_DIR}/transcript.txt" > "$RAW_TXT"
if [[ ! -s "$RAW_TXT" ]]; then
  show_tip_and_exit "Transcribed text is empty."
fi

case "$POSTPROCESS_MODE" in
  openai|openai-compatible|1|true|yes)
    if ! postprocess_openai "$RAW_TXT" "$FINAL_TXT"; then
      cp "$RAW_TXT" "$FINAL_TXT"
    fi
    ;;
  *)
    cp "$RAW_TXT" "$FINAL_TXT"
    ;;
esac

trim_text_file "$FINAL_TXT"
