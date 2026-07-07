# 公共变量与函数（被其他脚本 source 引用，不单独执行）
# ---------------------------------------------------------------
# 目录约定：
#   PROJECT_ROOT/
#     codex/              官方 Codex 源码（git submodule，停在 BASE_TAG，不手改）
#     brand/patches/      我们的改动，按序号命名的 *.patch
#     brand/BASE_SHA      锁定的官方 commit（CI 和本地都以它为基线）
#     brand/BASE_TAG      跟随的官方 release tag
#     scripts/            本目录

set -euo pipefail

# 解析出项目根目录（scripts/ 的上一级），不依赖调用时的 cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_DIR="$PROJECT_ROOT/codex"
BRAND_DIR="$PROJECT_ROOT/brand"
PATCH_DIR="$BRAND_DIR/patches"
PATCHES_DIR="$PATCH_DIR"   # 别名，兼容其他脚本里用的 PATCHES_DIR
BASE_SHA_FILE="$BRAND_DIR/BASE_SHA"
BASE_TAG_FILE="$BRAND_DIR/BASE_TAG"
MANIFEST_FILE="$BRAND_DIR/patches.manifest"

# 读取锁定的基线 SHA（去掉空白）
read_base_sha() {
  tr -d '[:space:]' < "$BASE_SHA_FILE"
}

# 读取跟随的 release tag（去掉空白）
read_base_tag() {
  tr -d '[:space:]' < "$BASE_TAG_FILE"
}

# 去掉字符串首尾空白（纯 bash，避免 echo|xargs 子管道在 set -e 下的坑）
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"             # 去前导空白
  s="${s%"${s##*[![:space:]]}"}"             # 去尾随空白
  printf '%s' "$s"
}

# 从 patches.manifest 解析出所有补丁组名（[组名] 段头），一行一个。
# 供 apply-patches.sh 校验「清单声明的每个补丁是否都有对应 .patch 文件」。
manifest_group_names() {
  [ -f "$MANIFEST_FILE" ] || die "找不到清单文件: $MANIFEST_FILE"
  local line name
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                       # 去掉行内注释
    line="$(trim "$line")"                    # 去首尾空白
    [ -z "$line" ] && continue
    if [[ "$line" == \[*\] ]]; then
      name="${line#\[}"; name="${name%\]}"
      printf '%s\n' "$name"
    fi
  done < "$MANIFEST_FILE"
  return 0                                    # while 在 EOF 返回非零，显式归零避免 set -e 误伤
}

# 确认 codex/ 是干净的 git 工作区（无未提交改动）
ensure_clean_src() {
  if [ -n "$(git -C "$SRC_DIR" status --porcelain)" ]; then
    echo "错误：codex/ 有未提交的改动。先运行 scripts/reset-src.sh 或 make-patches.sh 导出改动。" >&2
    git -C "$SRC_DIR" status --short >&2
    return 1
  fi
}

log()  { printf '\033[36m[brand]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[brand]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[brand]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
