#!/usr/bin/env bash
set -euo pipefail

# 用法：
# 1) 配置 TM_FORK_REPO_URL（你的 fork 地址）
# 2) 运行本脚本，自动 clone/fetch/apply/build/export
#
# 说明：这是构建骨架脚本，默认只应用 docs/fork/patches 下的最小补丁。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORK_ASSET_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

: "${TM_FORK_REPO_URL:=git@github.com:<your-org>/textmate-whisper-app.git}"
: "${TM_FORK_DIR:=$HOME/GitProjects/textmate-whisper-app}"
: "${TM_UPSTREAM_REPO_URL:=https://github.com/textmate/textmate.git}"
: "${TM_BASE_BRANCH:=master}"
: "${TM_WORK_BRANCH:=feature/mic-permission}"
: "${TM_PATCH_DIR:=$FORK_ASSET_ROOT/patches}"
: "${TM_EXPORT_DIR:=$HOME/Desktop/textmate-whisper-build}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd"
}

check_xcode_soft_guard() {
  local version major
  version="$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}')"
  if [[ -z "$version" ]]; then
    warn "Cannot read Xcode version. Continue anyway."
    return 0
  fi
  major="${version%%.*}"
  info "Detected Xcode version: $version"
  # 软告警：版本过新时给风险提示，但不阻断。
  if [[ "$major" =~ ^[0-9]+$ ]] && (( major > 17 )); then
    warn "Xcode is newer than verified baseline (17). Continue, but expect potential upstream compile breaks."
  fi
}

check_dependencies() {
  local missing=0
  local deps=(boost capnp google-sparsehash multimarkdown ninja ragel)
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not found. Please ensure dependencies are installed by other package manager."
    return 0
  fi
  for pkg in "${deps[@]}"; do
    if ! brew list --versions "$pkg" >/dev/null 2>&1; then
      warn "Missing dependency package: $pkg"
      missing=1
    fi
  done
  if (( missing == 1 )); then
    die "Install dependencies first. README reference: textmate upstream build section."
  fi
}

resolve_include_lib_paths() {
  local brew_prefix include_dir lib_dir

  brew_prefix=""
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
  fi

  for include_dir in \
    "${brew_prefix:+$brew_prefix/include}" \
    /opt/homebrew/include \
    /usr/local/include; do
    [[ -n "$include_dir" ]] || continue
    if [[ -f "$include_dir/boost/crc.hpp" && -f "$include_dir/capnp/message.h" ]]; then
      break
    fi
  done

  for lib_dir in \
    "${brew_prefix:+$brew_prefix/lib}" \
    /opt/homebrew/lib \
    /usr/local/lib; do
    [[ -n "$lib_dir" ]] || continue
    if compgen -G "$lib_dir/libcapnp.*" >/dev/null 2>&1 && compgen -G "$lib_dir/libkj.*" >/dev/null 2>&1; then
      break
    fi
  done

  if [[ -z "${include_dir:-}" || -z "${lib_dir:-}" ]]; then
    die "Cannot resolve include/lib paths for boost/capnp. Check Homebrew install state."
  fi

  TM_INCLUDE_DIR="$include_dir"
  TM_LIB_DIR="$lib_dir"
  export TM_INCLUDE_DIR TM_LIB_DIR
}

write_local_rave() {
  cd "$TM_FORK_DIR"
  cat > local.rave <<EOF
add FLAGS    "-I$TM_INCLUDE_DIR"
add LN_FLAGS "-L$TM_LIB_DIR"
EOF
  info "Wrote local.rave with include=$TM_INCLUDE_DIR lib=$TM_LIB_DIR"
}

setup_repo() {
  if [[ ! -d "$TM_FORK_DIR/.git" ]]; then
    info "Cloning fork: $TM_FORK_REPO_URL -> $TM_FORK_DIR"
    git clone --recursive "$TM_FORK_REPO_URL" "$TM_FORK_DIR"
  fi

  cd "$TM_FORK_DIR"
  if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$TM_UPSTREAM_REPO_URL"
  fi
  git fetch upstream --prune
  git fetch origin --prune
}

prepare_branch() {
  cd "$TM_FORK_DIR"
  git checkout "$TM_BASE_BRANCH"
  git pull --ff-only upstream "$TM_BASE_BRANCH"
  git checkout -B "$TM_WORK_BRANCH"
}

apply_patches() {
  cd "$TM_FORK_DIR"
  shopt -s nullglob
  local patches=("$TM_PATCH_DIR"/*.patch)
  if (( ${#patches[@]} == 0 )); then
    die "No patch files found under: $TM_PATCH_DIR"
  fi

  for p in "${patches[@]}"; do
    info "Applying patch: $p"
    git apply --3way "$p" || die "Patch apply failed: $p"
  done
}

build_textmate() {
  cd "$TM_FORK_DIR"
  resolve_include_lib_paths
  write_local_rave
  info "Running configure..."
  ./configure
  info "Building TextMate..."
  ninja TextMate
}

export_artifact() {
  local app_path
  mkdir -p "$TM_EXPORT_DIR"
  app_path="$(find "$HOME/build/TextMate" -type d -name TextMate.app 2>/dev/null | head -n 1 || true)"
  [[ -n "$app_path" ]] || die "Cannot locate built TextMate.app under \$HOME/build/TextMate"

  info "Exporting app: $app_path -> $TM_EXPORT_DIR/TextMate.app"
  rm -rf "$TM_EXPORT_DIR/TextMate.app"
  cp -R "$app_path" "$TM_EXPORT_DIR/TextMate.app"
}

main() {
  require_cmd git
  require_cmd xcodebuild
  require_cmd ninja
  check_xcode_soft_guard
  check_dependencies
  setup_repo
  prepare_branch
  apply_patches
  build_textmate
  export_artifact

  info "Done."
  info "Next:"
  info "  1) Open exported app and trigger voice recording once."
  info "  2) Confirm macOS microphone permission prompt appears."
  info "  3) If ok, commit patch branch and publish release notes."
}

main "$@"
