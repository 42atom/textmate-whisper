#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_common.sh"
safe_source_tm_bash_init

CONFIG_FILE="${TM_WHISPER_CONFIG_FILE:-$HOME/.config/textmate-whisper/config.env}"
mkdir -p "$(dirname "$CONFIG_FILE")"
DEVICE_MAP_BEGIN="# @tmw:dm:begin"
DEVICE_MAP_END="# @tmw:dm:end"
LEGACY_DEVICE_MAP_BEGIN="# BEGIN_TM_WHISPER_DEVICE_MAP"
LEGACY_DEVICE_MAP_END="# END_TM_WHISPER_DEVICE_MAP"

open_in_textmate() {
  local file="$1"
  if command -v mate >/dev/null 2>&1; then
    mate "$file" >/dev/null 2>&1 || true
    return 0
  fi
  open -a TextMate "$file" >/dev/null 2>&1 || open "$file" >/dev/null 2>&1 || true
}

create_default_config() {
  cat > "$CONFIG_FILE" <<'CONF'
# TextMate Whisper Voice 配置文件
# 保存后生效方式：
# 1) 在 TextMate 执行 Bundles -> Bundle Editor -> Reload Bundles
# 2) 若仍未生效，重启 TextMate
#
# 说明：
# - 统一在这个文件修改配置，不需要多次弹窗。
# - MiniMax / DeepSeek / OpenAI 都走 OpenAI 兼容接口字段。
#
# TextMate Whisper Voice config file
# How to apply changes:
# 1) Run Bundles -> Bundle Editor -> Reload Bundles in TextMate
# 2) If still not applied, restart TextMate
#
# Notes:
# - Edit this single file instead of multiple popups.
# - MiniMax / DeepSeek / OpenAI can all use OpenAI-compatible fields.

# 录音与本地转写
TM_FFMPEG_BIN=ffmpeg
TM_WHISPER_BIN=mlx_whisper
TM_WHISPER_MODEL=mlx-community/whisper-tiny
TM_WHISPER_LANG=zh
TM_WHISPER_TASK=transcribe
TM_WHISPER_MAX_SEC=20
# 设备指定代码修改处
TM_WHISPER_INPUT_DEVICE=auto
TM_VOICE_SHOW_STATUS=1
# TM_WHISPER_STATE_DIR=$HOME/.cache/textmate-whisper
# TM_WHISPER_LOG_DIR=$HOME/.cache/textmate-whisper/logs

# 后处理开关：off | auto | openai
# off: 关闭后处理
# auto: 配置了 API key 才启用后处理（推荐）
# openai: 强制走后处理（API 失败会回退原始转写）
TM_VOICE_POSTPROCESS=auto

# OpenAI 兼容 API（任选其一服务填写）
# DeepSeek 示例：
TM_OAI_BASE_URL=https://api.deepseek.com/v1
TM_OAI_MODEL=deepseek-chat
# OpenAI 示例：
# TM_OAI_BASE_URL=https://api.openai.com/v1
# TM_OAI_MODEL=gpt-4o-mini
# MiniMax 示例：
# TM_OAI_BASE_URL=<your-openai-compatible-endpoint>
# TM_OAI_MODEL=<your-model-name>
TM_OAI_API_KEY=
TM_OAI_TIMEOUT_SEC=45

# 可选：后处理提示词
TM_VOICE_POST_PROMPT=Polish this transcript into concise writing.
TM_VOICE_POST_SYSTEM_PROMPT=You are a writing assistant. Improve punctuation and readability while preserving meaning. Return only the rewritten text.
CONF
}

generate_device_map_block() {
  local ffmpeg_bin_raw ffmpeg_bin devices auto_idx auto_name idx name

  ffmpeg_bin_raw="${TM_FFMPEG_BIN:-ffmpeg}"
  ffmpeg_bin="$(resolve_bin "$ffmpeg_bin_raw" || true)"

  echo "$DEVICE_MAP_BEGIN"
  echo "# 设备参考表（自动生成）/ Device map (auto-generated)"
  echo "# 直接复制下面的 :N 到 TM_WHISPER_INPUT_DEVICE，可避免填错。"
  if [[ -z "$ffmpeg_bin" ]]; then
    echo "# 未检测到 ffmpeg。请安装 ffmpeg 或设置 TM_FFMPEG_BIN 后重新运行 Settings。"
  else
    FFMPEG_BIN="$ffmpeg_bin"
    devices="$(list_audio_devices)"
    if [[ -z "$(printf '%s' "$devices" | tr -d '[:space:]')" ]]; then
      echo "# 未检测到可用输入设备。请先连接麦克风/耳机后重试。"
    else
      echo "# 格式：设备名 = 设备代码"
      while IFS='|' read -r idx name; do
        [[ -n "${idx:-}" ]] || continue
        echo "#   ${name} = :${idx}"
      done <<< "$devices"

      auto_idx="$(auto_pick_audio_device_index "$devices")"
      if [[ -n "$auto_idx" ]]; then
        auto_name="$(printf '%s\n' "$devices" | awk -F'|' -v idx="$auto_idx" '$1 == idx { print $2; exit }')"
        echo "# auto 当前会选择: :${auto_idx} (${auto_name})"
      fi
      echo "# 示例：TM_WHISPER_INPUT_DEVICE=:${auto_idx:-1}"
    fi
  fi
  echo "$DEVICE_MAP_END"
}

refresh_device_map_block() {
  local tmp_file block_file
  tmp_file="$(mktemp /tmp/tm-whisper-config-XXXXXX)"
  block_file="$(mktemp /tmp/tm-whisper-device-map-XXXXXX)"

  generate_device_map_block > "$block_file"

  awk -v begin="$DEVICE_MAP_BEGIN" \
      -v end="$DEVICE_MAP_END" \
      -v legacy_begin="$LEGACY_DEVICE_MAP_BEGIN" \
      -v legacy_end="$LEGACY_DEVICE_MAP_END" \
      -v block_file="$block_file" '
    function print_block(  line) {
      while ((getline line < block_file) > 0) {
        print line
      }
      close(block_file)
    }

    $0 == begin || $0 == legacy_begin { in_block = 1; next }
    $0 == end || $0 == legacy_end { in_block = 0; next }
    in_block { next }

    !inserted && $0 ~ /^[[:space:]]*TM_WHISPER_INPUT_DEVICE=/ {
      print_block()
      inserted = 1
    }

    { print }

    END {
      if (!inserted) {
        print_block()
      }
    }
  ' "$CONFIG_FILE" > "$tmp_file"

  mv "$tmp_file" "$CONFIG_FILE"
  rm -f "$block_file"
}

created=0
if [[ ! -f "$CONFIG_FILE" ]]; then
  create_default_config
  created=1
fi

load_config_env "$CONFIG_FILE" TM_FFMPEG_BIN TM_WHISPER_INPUT_DEVICE
refresh_device_map_block

open_in_textmate "$CONFIG_FILE"

if (( created == 1 )); then
  msg="Created config: $CONFIG_FILE. 编辑保存后请 Reload Bundles 或重启 TextMate. Edit/save, then Reload Bundles or restart TextMate."
else
  msg="Opened config: $CONFIG_FILE. 保存后请 Reload Bundles 或重启 TextMate. Save changes, then Reload Bundles or restart TextMate."
fi

show_tip_and_exit "$msg" 0
