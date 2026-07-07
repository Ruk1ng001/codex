#!/usr/bin/env bash
# 首启动幂等写入(Mac / Linux 安装器)——把内置渠道配置写入 ~/.codex/config.toml。
#
# 目标：用户首次启动就有可用配置，且绝不覆盖其后续的手动修改。
#
# ── 行为契约（与 installer/write-default-config.ps1 逐条对齐）─────────────
#   1. 配置目录：尊重 $CODEX_HOME（与 codex 本体解析一致），未设置则用 ~/.codex
#      （保持官方默认目录，不改动）。配置文件固定为 <目录>/config.toml。
#   2. 幂等判定：目标 config.toml 已存在且含段头 [model_providers.newapi]
#      ⇒ 完全不动，尊重用户的手动修改（幂等，退出码 0）。
#   3. 不存在      ⇒ 创建目录并写入内置渠道配置。
#   4. 存在但缺该段 ⇒ 追加内置渠道配置（带注释分隔块），不动用户原有内容。
#
# ── 要写入的内容从哪来 ──────────────────────────────────────────────
#   第 1 个参数 = 成品配置文件路径；省略时默认取脚本同目录的 config.toml。
#   该成品配置由打包期 scripts/render-config.sh 渲染（占位符已替换成真实渠道值），
#   随安装器一起分发。含 token，按敏感文件处理（写入后 chmod 600）。
#
# 用法：
#   installer/write-default-config.sh [成品配置路径]
set -euo pipefail

# 段头标记：幂等判定的唯一依据（TOML 段头，允许前导空白与行尾注释）。
PROVIDER_SECTION_RE='^[[:space:]]*\[model_providers\.newapi\][[:space:]]*(#.*)?$'

log()  { printf '\033[36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[install]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[install]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_config="${1:-$script_dir/config.toml}"

# 配置目录：CODEX_HOME 优先，否则 ~/.codex（保持不变）。
codex_home="${CODEX_HOME:-$HOME/.codex}"
config_path="$codex_home/config.toml"

[ -f "$source_config" ] || die "找不到成品配置: $source_config（应由 render-config.sh 渲染后随安装器分发）"

# 情况 2：已存在且含内置渠道段 ⇒ 幂等，不动。
if [ -f "$config_path" ] && grep -qE "$PROVIDER_SECTION_RE" "$config_path"; then
  log "已存在内置渠道配置（$config_path 含 [model_providers.newapi]），保持不变。"
  exit 0
fi

mkdir -p "$codex_home"

if [ ! -f "$config_path" ]; then
  # 情况 3：文件不存在 ⇒ 写入完整内置配置。
  cat "$source_config" > "$config_path"
  chmod 600 "$config_path"
  log "已写入内置渠道配置到 $config_path（权限 600）。"
else
  # 情况 4：文件存在但缺内置渠道段 ⇒ 追加，不动用户原有内容。
  {
    printf '\n# ---- 内置渠道配置（由安装器追加，缺失时补全）----\n'
    cat "$source_config"
  } >> "$config_path"
  chmod 600 "$config_path"
  log "已在 $config_path 追加内置渠道配置（原有内容保留，权限 600）。"
  warn "若原文件已含顶层 model / model_provider，TOML 不允许重复键，请手动核对。"
fi
