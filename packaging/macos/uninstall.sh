#!/bin/bash
# uninstall.sh —— 卸载由 cx .pkg 安装的内容（US-010）。
#
# macOS 的 .pkg 没有原生卸载器，需手动移除。本脚本把「移除步骤」脚本化，
# 也可当作卸载文档的可执行版本。
#
# 默认移除：
#   1. /usr/local/bin/cx           —— pkg payload 装入的二进制
#   2. pkg 安装收据（forget）       —— 让系统不再认为该包已安装
#
# 默认保留（除非 --purge-config）：
#   ~/.codex/config.toml           —— 用户配置，可能已被手动修改，默认不动
#
# 用法：
#   packaging/macos/uninstall.sh [--purge-config] [--yes]
#     --purge-config   一并删除 ~/.codex/config.toml（默认保留）
#     --yes            跳过确认提示（非交互场景）
#
# 需要写 /usr/local/bin 与执行 pkgutil --forget，通常需 sudo：
#   sudo packaging/macos/uninstall.sh
set -eu

BIN_PATH="/usr/local/bin/cx"
PKG_IDENTIFIER="${CX_PKG_IDENTIFIER:-com.cx.cli}"

purge_config=0
assume_yes=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --purge-config) purge_config=1 ;;
    --yes | -y)     assume_yes=1 ;;
    --help | -h)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
  shift
done

confirm() {
  [ "$assume_yes" -eq 1 ] && return 0
  printf '%s [y/N] ' "$1"
  read -r ans || ans=""
  case "$ans" in
    y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

echo "==> 卸载 cx（.pkg 安装）"

if ! confirm "将移除 $BIN_PATH 与安装收据 $PKG_IDENTIFIER，继续吗?"; then
  echo "已取消。"
  exit 0
fi

# 1. 移除二进制。
if [ -e "$BIN_PATH" ]; then
  rm -f "$BIN_PATH"
  echo "已删除 $BIN_PATH"
else
  echo "未发现 $BIN_PATH（可能已删除或安装到别处）。"
fi

# 2. 遗忘安装收据（不影响文件，只让 pkgutil 不再记录该包已装）。
if pkgutil --pkg-info "$PKG_IDENTIFIER" >/dev/null 2>&1; then
  pkgutil --forget "$PKG_IDENTIFIER" || true
  echo "已遗忘安装收据 $PKG_IDENTIFIER"
else
  echo "未发现安装收据 $PKG_IDENTIFIER（可能未用 .pkg 安装或已遗忘）。"
fi

# 3. 配置文件：默认保留，仅 --purge-config 时删除。
config_home="${CODEX_HOME:-$HOME/.codex}"
config_path="$config_home/config.toml"
if [ "$purge_config" -eq 1 ]; then
  if [ -f "$config_path" ]; then
    rm -f "$config_path"
    echo "已删除配置 $config_path"
  else
    echo "未发现配置 $config_path。"
  fi
else
  if [ -f "$config_path" ]; then
    echo "已保留配置 $config_path（如需删除请加 --purge-config）。"
  fi
fi

echo "cx 卸载完成。"
