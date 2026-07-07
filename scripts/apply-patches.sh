#!/usr/bin/env bash
# 把 brand/patches/*.patch 按 patches.manifest 声明的顺序应用到干净的官方基线上。
# 先重置到基线，保证每次应用都是可复现的。
# CI 和本机验证都用这个脚本。
#
# 校验（消除静默失败，见 TODO「已知问题 #1」）：
#   - 应用前：patches.manifest 声明的每个补丁组都必须有对应 <组名>.patch 文件，
#             缺失则报错退出（避免「没补丁可应用」却假装成功、编译出未打补丁的原版）；
#   - 应用后：codex/ 必须确有改动，否则说明补丁是空操作，报错退出。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

BASE_SHA="$(read_base_sha)"

# 从清单解析出应有的补丁组（manifest 顺序即应用顺序，组名前缀 NN- 保证确定性）。
# 注意：不能用变量名 GROUPS——它是 bash 特殊数组（当前用户组 ID），赋值会被内置语义污染。
[ -f "$MANIFEST_FILE" ] || die "找不到清单文件: $MANIFEST_FILE"
mapfile -t PATCH_GROUPS < <(manifest_group_names)

if [ "${#PATCH_GROUPS[@]}" -eq 0 ]; then
  log "patches.manifest 未声明任何补丁组，无补丁可应用"
  exit 0
fi

# —— 应用前校验：每个声明的补丁组都要有对应 .patch 文件 ——
missing=()
for name in "${PATCH_GROUPS[@]}"; do
  [ -f "$PATCHES_DIR/$name.patch" ] || missing+=("$name.patch")
done
if [ "${#missing[@]}" -gt 0 ]; then
  err "补丁缺失：patches.manifest 声明的以下补丁文件不存在于 $PATCHES_DIR："
  for m in "${missing[@]}"; do err "    - $m"; done
  err "处理：运行 make-patches.sh 导出补丁，或从 patches.manifest 移除未使用的补丁组。"
  exit 1
fi

# 先确保 codex/ 停在干净基线（CI 里 codex 是新 checkout，本机可能有残留）
git -C "$SRC_DIR" reset --hard "$BASE_SHA" >/dev/null
git -C "$SRC_DIR" clean -fd >/dev/null

log "共 ${#PATCH_GROUPS[@]} 个补丁，开始应用到 $BASE_SHA"
for name in "${PATCH_GROUPS[@]}"; do
  p="$PATCHES_DIR/$name.patch"
  # --3way 让 git 在上下文变动时用三方合并，比纯 apply 更能容错
  if git -C "$SRC_DIR" apply --3way --whitespace=nowarn "$p"; then
    log "  ✓ $name.patch"
  else
    err "  ✗ $name.patch 应用失败"
    err "    基线 SHA 可能与补丁生成时不一致，或官方改动与补丁冲突。"
    err "    处理：手动解决冲突后运行 make-patches.sh 重新导出。"
    exit 1
  fi
done

# —— 应用后校验：codex/ 必须确有改动，否则补丁是空操作（静默失败） ——
if [ -z "$(git -C "$SRC_DIR" status --porcelain)" ]; then
  err "应用后校验失败：codex/ 无任何改动。"
  err "    ${#PATCH_GROUPS[@]} 个补丁全部「应用成功」却未改动任何文件，补丁可能为空或已失效。"
  err "    处理：检查 $PATCHES_DIR 下的 .patch 内容，或重新运行 make-patches.sh 导出。"
  exit 1
fi

log "全部补丁应用完成"
