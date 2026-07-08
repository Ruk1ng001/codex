#!/usr/bin/env bash
# build-pkg.sh —— 用 pkgbuild + productbuild 构建 macOS 原生 .pkg 安装包（US-010）。
#
# 产出的 .pkg 可在「安装器」App 中双击运行、按向导完成安装：
#   - payload：把 cx 二进制装到系统级 /usr/local/bin/cx（新终端可直接 `cx`，无需改 PATH）；
#   - postinstall：幂等把打包期注入的内置渠道 config 写入登录用户 ~/.codex/config.toml。
#
# ── 设计约定（与本仓既有工作流一致）──────────────────────────────────
#   - 本机（维护者 ARM64 Linux）不参与打包：pkgbuild/productbuild 是 macOS 专有工具，
#     本脚本只在 CI 的 macos runner 上跑（见 .github/workflows/package-macos.yml 可复用工作流）。
#   - 二进制由 build.yml 编译产出（US-009），config.toml 由 render-config.sh 渲染（US-007），
#     两者作为输入传入本脚本，绝不在此重编译，token 也不落进 git。
#   - config 幂等写入复用 installer/write-default-config.sh（US-008）的行为契约，
#     不在 postinstall 里重复实现。
#
# 用法：
#   packaging/macos/build-pkg.sh --binary PATH --config PATH --version VER [--out PATH] [--arch ARCH]
# 环境变量（等价 flag，flag 优先）：
#   CX_BINARY   cx 二进制路径（编译产物，如 dist/cx）
#   CX_CONFIG   成品 config.toml 路径（render-config.sh 渲染产物）
#   CX_VERSION  版本号（如 0.142.5-cx.1），写进 pkg 元数据
#   CX_PKG_OUT  输出 .pkg 路径（默认 dist/cx-<version>-<arch>.pkg）
#   CX_ARCH     目标架构标签（arm64 / x86_64，仅用于产物命名与展示）
#
# 可选签名 / 公证（验收 7，配置了对应 Secret 才生效）：
#   CX_SIGN_IDENTITY      Developer ID Installer 证书标识（传给 productbuild --sign）
#   CX_NOTARIZE_PROFILE   notarytool 的 keychain profile 名（配置后自动公证 + stapler）
set -euo pipefail

# 包标识（reverse-DNS）。改品牌时同步 uninstall.sh 与文档里的标识。
PKG_IDENTIFIER="com.cx.cli"
COMMAND_NAME="cx"
# payload 里二进制的安装目标：系统级可执行路径，新终端默认在 PATH 中。
INSTALL_PREFIX="/usr/local/bin"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

binary="${CX_BINARY:-}"
config="${CX_CONFIG:-}"
version="${CX_VERSION:-}"
out="${CX_PKG_OUT:-}"
arch="${CX_ARCH:-}"
sign_identity="${CX_SIGN_IDENTITY:-}"
notarize_profile="${CX_NOTARIZE_PROFILE:-}"

log()  { printf '\033[36m[pkg]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[pkg]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[pkg]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
用法: build-pkg.sh --binary PATH --config PATH --version VER [--out PATH] [--arch ARCH]

用 pkgbuild + productbuild 构建 macOS 原生 .pkg 安装包（命令名 $COMMAND_NAME）。

必需:
  --binary PATH   cx 二进制（build.yml 编译产物）。
  --config PATH   成品 config.toml（render-config.sh 渲染产物，含真实渠道值）。
  --version VER   版本号（如 0.142.5-cx.1）。
可选:
  --out PATH      输出 .pkg 路径（默认 dist/cx-<version>-<arch>.pkg）。
  --arch ARCH     架构标签（arm64/x86_64，仅用于命名与展示）。
  -h, --help      显示本帮助。

签名/公证（配置对应环境变量才生效）:
  CX_SIGN_IDENTITY     Developer ID Installer 证书标识 → productbuild --sign。
  CX_NOTARIZE_PROFILE  notarytool keychain profile → 自动公证 + stapler。
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --binary)  [ "$#" -ge 2 ] || die "--binary 需要一个路径参数。"; binary="$2"; shift ;;
    --config)  [ "$#" -ge 2 ] || die "--config 需要一个路径参数。"; config="$2"; shift ;;
    --version) [ "$#" -ge 2 ] || die "--version 需要一个参数。"; version="$2"; shift ;;
    --out)     [ "$#" -ge 2 ] || die "--out 需要一个路径参数。"; out="$2"; shift ;;
    --arch)    [ "$#" -ge 2 ] || die "--arch 需要一个参数。"; arch="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

[ -n "$binary" ]  || { usage >&2; die "缺少 --binary（cx 二进制）。"; }
[ -n "$config" ]  || { usage >&2; die "缺少 --config（成品 config.toml）。"; }
[ -n "$version" ] || { usage >&2; die "缺少 --version（版本号）。"; }
[ -f "$binary" ]  || die "找不到二进制: $binary"
[ -f "$config" ]  || die "找不到成品配置: $config"

# 依赖工具（macOS 自带；非 macOS 会缺失，本脚本仅在 macos runner 上跑）。
command -v pkgbuild     >/dev/null 2>&1 || die "缺少 pkgbuild（本脚本只能在 macOS 上运行）。"
command -v productbuild >/dev/null 2>&1 || die "缺少 productbuild（本脚本只能在 macOS 上运行）。"

writer="$script_dir/../../installer/write-default-config.sh"
[ -f "$writer" ] || die "找不到 $writer（首启动幂等写入脚本，US-008）。"

[ -n "$arch" ] || arch="$(uname -m 2>/dev/null || echo unknown)"
[ -n "$out" ]  || out="dist/${COMMAND_NAME}-${version}-${arch}.pkg"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM

# ── 1) 组装 payload（安装到 /usr/local/bin/cx） ──────────────────────
# pkgbuild 的 --root 是一棵「将被铺到目标机」的目录树；这里把 cx 放到
# $work/payload/usr/local/bin/cx，--install-location / 即映射到系统根。
payload="$work/payload"
mkdir -p "$payload$INSTALL_PREFIX"
install -m 0755 "$binary" "$payload$INSTALL_PREFIX/$COMMAND_NAME"
log "payload: $INSTALL_PREFIX/$COMMAND_NAME（0755）"

# ── 2) 组装 scripts（postinstall + 幂等 writer + 成品 config） ────────
# postinstall 运行时同目录能取到 writer 与 config，故一并复制进 scripts 段。
scripts="$work/scripts"
mkdir -p "$scripts"
install -m 0755 "$script_dir/scripts/postinstall" "$scripts/postinstall"
install -m 0755 "$writer" "$scripts/write-default-config.sh"
# config 含 token，按敏感文件处理（0600）。它只随 pkg 分发、装到用户 ~/.codex，不进 git。
install -m 0600 "$config" "$scripts/config.toml"
log "scripts: postinstall + write-default-config.sh + config.toml"

# ── 3) pkgbuild 生成组件包（component pkg） ──────────────────────────
component_pkg="$work/${COMMAND_NAME}-component.pkg"
pkgbuild \
  --root "$payload" \
  --scripts "$scripts" \
  --identifier "$PKG_IDENTIFIER" \
  --version "$version" \
  --install-location "/" \
  "$component_pkg"
log "pkgbuild 完成: $(basename "$component_pkg")"

# ── 4) productbuild 生成可双击的分发包（distribution pkg） ───────────
# distribution.xml 提供安装器向导的标题/欢迎/许可等元信息。
dist_xml="$work/distribution.xml"
cat > "$dist_xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>$COMMAND_NAME CLI</title>
  <organization>$PKG_IDENTIFIER</organization>
  <options customize="never" require-scripts="true" hostArchitectures="arm64,x86_64"/>
  <domains enable_localSystem="true"/>
  <choices-outline>
    <line choice="default"/>
  </choices-outline>
  <choice id="default" title="$COMMAND_NAME CLI" visible="true">
    <pkg-ref id="$PKG_IDENTIFIER"/>
  </choice>
  <pkg-ref id="$PKG_IDENTIFIER" version="$version" onConclusion="none">${COMMAND_NAME}-component.pkg</pkg-ref>
</installer-gui-script>
EOF

mkdir -p "$(dirname "$out")"

productbuild_args=(
  --distribution "$dist_xml"
  --package-path "$work"
)
# 配置了 Developer ID Installer 证书才签名（验收 7 的可选项）。
if [ -n "$sign_identity" ]; then
  log "对 .pkg 做产品签名（identity: $sign_identity）"
  productbuild_args+=(--sign "$sign_identity")
else
  warn "未配置 CX_SIGN_IDENTITY：产出未签名 .pkg，用户需「右键→打开」或 xattr 去隔离绕过 Gatekeeper（见 README）。"
fi

productbuild "${productbuild_args[@]}" "$out"
log "productbuild 完成: $out"

# ── 5) 可选公证 + 装订（配置了 notarytool profile 才做） ─────────────
if [ -n "$notarize_profile" ]; then
  if [ -z "$sign_identity" ]; then
    warn "配置了公证但未签名：公证要求 .pkg 已用 Developer ID 签名，跳过公证。"
  else
    log "提交公证（notarytool profile: $notarize_profile）"
    xcrun notarytool submit "$out" --keychain-profile "$notarize_profile" --wait
    log "装订公证票据（stapler）"
    xcrun stapler staple "$out"
  fi
fi

log "完成：$out"
