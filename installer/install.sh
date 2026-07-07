#!/bin/sh
# Mac 安装器 —— 一条命令完成本地安装并可直接使用 `cx`。
#
# 改自官方 codex/scripts/install/install.sh，做了三处裁剪与改造：
#   1. 去掉全部 GitHub 下载 / 校验 / 版本解析逻辑：二进制随安装器本地分发，
#      不再从 releases 下载（官方那套 download_file / digest / release_dir 全部移除）。
#   2. 去掉 standalone releases/current 软链多版本布局：直接把本地二进制装成
#      $BIN_DIR/cx（单文件，改名为 cx），布局更简单。
#   3. 命令名 codex → cx；并在装完二进制后调用 US-008 的
#      installer/write-default-config.sh 幂等写入内置渠道 config。
#
# 保留官方成熟的 PATH 注入逻辑（pick_profile / add_to_path / 标记块重写），
# 保证「安装完成后 cx 可在新终端直接调用」。
#
# ── 二进制从哪来 ─────────────────────────────────────────────────
#   优先级：--binary PATH > $CX_BINARY > 脚本同目录自动探测。
#   自动探测按当前 Mac 架构找脚本同目录下的：
#     arm64 → cx-aarch64-apple-darwin，x64 → cx-x86_64-apple-darwin，
#   都没有则回退到通用文件名 cx。
#   这些文件由 GitHub Actions（build.yml）编译产出（US-009），打包时随安装器分发。
#
# 用法：
#   installer/install.sh [--binary PATH] [--config PATH]
# 环境变量：
#   CX_INSTALL_DIR   安装目录（默认 $HOME/.local/bin）
#   CX_BINARY        本地 cx 二进制路径（覆盖自动探测）
#   CX_CONFIG        随安装器分发的成品 config.toml 路径（默认脚本同目录 config.toml）
#   CODEX_HOME       配置目录（默认 $HOME/.codex，与 codex 本体一致）
set -eu

COMMAND_NAME="cx"

BIN_DIR="${CX_INSTALL_DIR:-$HOME/.local/bin}"
BIN_PATH="$BIN_DIR/$COMMAND_NAME"

script_dir="$(cd "$(dirname "$0")" && pwd)"

binary_override="${CX_BINARY:-}"
config_override="${CX_CONFIG:-}"

path_action="already"
path_profile=""

step() {
  printf '==> %s\n' "$1"
}

warn() {
  printf 'WARNING: %s\n' "$1" >&2
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --binary)
        if [ "$#" -lt 2 ]; then
          echo "--binary 需要一个路径参数。" >&2
          exit 1
        fi
        binary_override="$2"
        shift
        ;;
      --config)
        if [ "$#" -lt 2 ]; then
          echo "--config 需要一个路径参数。" >&2
          exit 1
        fi
        config_override="$2"
        shift
        ;;
      --help | -h)
        cat <<EOF
用法: install.sh [--binary PATH] [--config PATH]

在本地安装 $COMMAND_NAME（不联网下载），写入内置渠道配置并加入 PATH。

选项:
  --binary PATH   指定本地 cx 二进制（覆盖自动探测）。
  --config PATH   指定随安装器分发的成品 config.toml（默认脚本同目录）。

环境变量:
  CX_INSTALL_DIR  安装目录（默认 \$HOME/.local/bin）。
  CX_BINARY       本地 cx 二进制路径（等价 --binary）。
  CX_CONFIG       成品 config.toml 路径（等价 --config）。
  CODEX_HOME      配置目录（默认 \$HOME/.codex）。
EOF
        exit 0
        ;;
      *)
        echo "未知参数: $1" >&2
        exit 1
        ;;
    esac
    shift
  done
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required to install $COMMAND_NAME." >&2
    exit 1
  fi
}

pick_profile() {
  # 沿用官方按 shell 拆分的策略：macOS/Linux 的登录/交互 shell 没有统一的启动文件，
  # 这里参照 Homebrew 文档的做法按 SHELL 选择对应 profile。
  case "$os:${SHELL:-}" in
    darwin:*/zsh)
      printf '%s\n' "$HOME/.zprofile"
      ;;
    darwin:*/bash)
      printf '%s\n' "$HOME/.bash_profile"
      ;;
    linux:*/zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    linux:*/bash)
      printf '%s\n' "$HOME/.bashrc"
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

append_path_block() {
  profile="$1"
  begin_marker="$2"
  end_marker="$3"
  path_line="$4"

  {
    printf '\n%s\n' "$begin_marker"
    printf '%s\n' "$path_line"
    printf '%s\n' "$end_marker"
  } >>"$profile"
}

rewrite_path_block() {
  profile="$1"
  begin_marker="$2"
  end_marker="$3"
  path_line="$4"
  tmp_profile="$tmp_dir/profile.$$.tmp"

  awk -v begin="$begin_marker" -v end="$end_marker" -v line="$path_line" '
    BEGIN {
      in_block = 0
      replaced = 0
    }
    $0 == begin {
      if (!replaced) {
        print begin
        print line
        print end
        replaced = 1
      }
      in_block = 1
      next
    }
    in_block {
      if ($0 == end) {
        in_block = 0
      }
      next
    }
    {
      print
    }
    END {
      if (in_block != 0) {
        exit 1
      }
    }
  ' "$profile" >"$tmp_profile"
  mv "$tmp_profile" "$profile"
}

add_to_path() {
  path_action="already"
  path_profile=""

  case ":$PATH:" in
    *":$BIN_DIR:"*)
      return
      ;;
  esac

  profile="$(pick_profile)"
  path_profile="$profile"
  begin_marker="# >>> cx installer >>>"
  end_marker="# <<< cx installer <<<"
  path_line="export PATH=\"$BIN_DIR:\$PATH\""

  if [ -f "$profile" ] && grep -F "$begin_marker" "$profile" >/dev/null 2>&1; then
    if grep -F "$path_line" "$profile" >/dev/null 2>&1; then
      path_action="configured"
      return
    fi

    if grep -F "$end_marker" "$profile" >/dev/null 2>&1; then
      rewrite_path_block "$profile" "$begin_marker" "$end_marker" "$path_line"
      path_action="updated"
      return
    fi
  fi

  append_path_block "$profile" "$begin_marker" "$end_marker" "$path_line"
  path_action="added"
}

print_launch_instructions() {
  case "$path_action" in
    added)
      step "当前终端: export PATH=\"$BIN_DIR:\$PATH\" && $COMMAND_NAME"
      step "新终端: 打开新终端后直接运行: $COMMAND_NAME"
      step "已把 PATH 写入 $path_profile"
      ;;
    updated)
      step "当前终端: export PATH=\"$BIN_DIR:\$PATH\" && $COMMAND_NAME"
      step "新终端: 打开新终端后直接运行: $COMMAND_NAME"
      step "已更新 $path_profile 中的 PATH"
      ;;
    configured)
      step "当前终端: export PATH=\"$BIN_DIR:\$PATH\" && $COMMAND_NAME"
      step "新终端: 打开新终端后直接运行: $COMMAND_NAME"
      step "PATH 已配置在 $path_profile"
      ;;
    *)
      step "当前终端: $COMMAND_NAME"
      step "新终端: 打开新终端后直接运行: $COMMAND_NAME"
      ;;
  esac
}

# 定位本地二进制：--binary/CX_BINARY 优先，否则按当前 Mac 架构在脚本同目录探测，
# 依次找 cx-<vendor_target>，回退到通用文件名 cx。
resolve_binary() {
  if [ -n "$binary_override" ]; then
    if [ ! -f "$binary_override" ]; then
      echo "指定的二进制不存在: $binary_override" >&2
      exit 1
    fi
    printf '%s\n' "$binary_override"
    return
  fi

  for candidate in "$script_dir/$COMMAND_NAME-$vendor_target" "$script_dir/$COMMAND_NAME"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  echo "找不到本地 $COMMAND_NAME 二进制（在 $script_dir 下查找 $COMMAND_NAME-$vendor_target 或 $COMMAND_NAME）。" >&2
  echo "请用 --binary PATH 指定，或把 CI 产出的二进制放到安装器同目录。" >&2
  exit 1
}

install_binary() {
  binary_src="$1"
  mkdir -p "$BIN_DIR"
  tmp_bin="$BIN_DIR/.$COMMAND_NAME.$$"

  rm -f "$tmp_bin"
  cp "$binary_src" "$tmp_bin"
  chmod 0755 "$tmp_bin"
  mv -f "$tmp_bin" "$BIN_PATH"
}

write_default_config() {
  writer="$script_dir/write-default-config.sh"
  config_src="$config_override"
  if [ -z "$config_src" ]; then
    config_src="$script_dir/config.toml"
  fi

  if [ ! -f "$writer" ]; then
    warn "未找到 $writer，跳过内置渠道配置写入。首次运行 $COMMAND_NAME 前请手动配置 ~/.codex/config.toml。"
    return
  fi

  if [ ! -f "$config_src" ]; then
    warn "未找到成品配置 $config_src，跳过内置渠道配置写入。首次运行 $COMMAND_NAME 前请手动配置。"
    return
  fi

  # write-default-config.sh 是 bash 脚本（用了 set -o pipefail / BASH_SOURCE），
  # 必须用 bash 调用，不能用 sh（macOS /bin/sh 虽是 bash，但显式 bash 更稳妥）。
  if ! command -v bash >/dev/null 2>&1; then
    warn "未找到 bash，跳过内置渠道配置写入。首次运行 $COMMAND_NAME 前请手动配置 ~/.codex/config.toml。"
    return
  fi

  step "写入内置渠道配置（幂等）"
  bash "$writer" "$config_src"
}

verify_visible_command() {
  "$BIN_PATH" --version >/dev/null
}

parse_args "$@"

require_command mktemp
require_command uname

case "$(uname -s)" in
  Darwin)
    os="darwin"
    ;;
  *)
    echo "install.sh 仅支持 macOS。Windows 请用 install.ps1。" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64 | amd64)
    arch="x86_64"
    ;;
  arm64 | aarch64)
    arch="aarch64"
    ;;
  *)
    echo "不支持的架构: $(uname -m)" >&2
    exit 1
    ;;
esac

# 在 Rosetta 下运行的 x86_64 进程实际跑在 Apple Silicon 上，应装 arm64 原生二进制。
if [ "$arch" = "x86_64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = "1" ]; then
    arch="aarch64"
  fi
fi

if [ "$arch" = "aarch64" ]; then
  vendor_target="aarch64-apple-darwin"
  platform_label="macOS (Apple Silicon)"
else
  vendor_target="x86_64-apple-darwin"
  platform_label="macOS (Intel)"
fi

binary_src="$(resolve_binary)"

step "安装 $COMMAND_NAME CLI"
step "检测到平台: $platform_label"
step "使用本地二进制: $binary_src"

tmp_dir="$(mktemp -d)"
cleanup() {
  if [ -n "${tmp_dir:-}" ]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT INT TERM

step "安装二进制到 $BIN_PATH"
install_binary "$binary_src"

write_default_config

add_to_path

verify_visible_command

case "$path_action" in
  added | updated | configured)
    print_launch_instructions
    ;;
  *)
    step "$BIN_DIR 已在 PATH 中"
    print_launch_instructions
    ;;
esac

printf '%s CLI 安装成功。\n' "$COMMAND_NAME"
