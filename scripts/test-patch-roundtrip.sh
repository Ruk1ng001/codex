#!/usr/bin/env bash
# 补丁工作流端到端可靠性测试：证明「改动 → 导出 → 还原 → 重应用」闭环无损。
#
# 流程：
#   1. 前置校验 codex/ 干净（否则中止，绝不清掉你未保存的工作）；
#   2. 给 patches.manifest 声明的**每个补丁组**注入一处已知标记改动
#      （每组都要有改动，apply-patches.sh 才不会因某组缺 .patch 而前置校验失败）；
#   3. 记录“期望”改动内容（git diff）；
#   4. make-patches.sh   —— 把改动导出成 brand/patches/<组名>.patch；
#   5. reset-src.sh      —— 把 codex/ 还原到基线，随后校验：工作区干净 + HEAD == BASE_SHA；
#   6. apply-patches.sh  —— 把补丁重新应用回去；
#   7. 记录“实际”改动内容（git diff），与第 3 步逐字节 diff 比对，一致即闭环无损。
#
# 全程**不触发任何编译**：本脚本从不调用 cargo / make / 任何构建命令，只走
# 补丁的导出与应用；结束时无论成败都把 codex/ 与 brand/patches/ 还原到测试前状态。
#
# 用法：
#   ./scripts/test-patch-roundtrip.sh
# 退出码：0 = 闭环无损通过；非 0 = 某步失败（已打印中文原因）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE_SHA="$(read_base_sha)"
MARKER="e2e-roundtrip-marker  // 补丁闭环测试注入行（测试结束会自动清除）"

# —— 记录测试前状态，用于结束时无条件还原 ——
TMP="$(mktemp -d)"
PATCH_BACKUP="$(mktemp -d)"
if [ -d "$PATCHES_DIR" ] && [ -n "$(ls -A "$PATCHES_DIR" 2>/dev/null)" ]; then
  cp -a "$PATCHES_DIR/." "$PATCH_BACKUP/"
fi

cleanup() {
  # 还原 codex/ 到基线（丢弃测试注入的改动 / 重应用的补丁）
  git -C "$SRC_DIR" reset --hard "$BASE_SHA" >/dev/null 2>&1 || true
  git -C "$SRC_DIR" clean -fd          >/dev/null 2>&1 || true
  # 还原 brand/patches/ 到测试前内容（清掉测试生成的补丁，恢复原有补丁）
  if [ -d "$PATCHES_DIR" ]; then rm -rf "${PATCHES_DIR:?}/"* 2>/dev/null || true; fi
  if [ -n "$(ls -A "$PATCH_BACKUP" 2>/dev/null)" ]; then
    mkdir -p "$PATCHES_DIR"
    cp -a "$PATCH_BACKUP/." "$PATCHES_DIR/"
  fi
  rm -rf "$TMP" "$PATCH_BACKUP" 2>/dev/null || true
}
trap cleanup EXIT

# —— 步骤 1：前置校验 codex/ 干净 ——
log "步骤 1/7  校验 codex/ 工作区干净"
ensure_clean_src

# —— 从 manifest 解析每个组及其第一个真实文件，作为标记注入点 ——
# 逐组注入是必须的：apply-patches.sh 要求每个声明的组都有 <组名>.patch，
# 若只改一个组的文件，另一个组导不出补丁，apply 前置校验会报缺失。
declare -a GNAMES
declare -A GFILES
cur=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="$(trim "$line")"
  [ -z "$line" ] && continue
  if [[ "$line" == \[*\] ]]; then
    cur="${line#\[}"; cur="${cur%\]}"
    GNAMES+=("$cur")
    GFILES["$cur"]=""
  else
    [ -n "$cur" ] || die "manifest 格式错误：路径 '$line' 出现在任何 [组名] 段之前"
    GFILES["$cur"]+="$line"$'\n'
  fi
done < "$MANIFEST_FILE"

[ "${#GNAMES[@]}" -gt 0 ] || die "patches.manifest 未声明任何补丁组，无法测试"

# 为每个组挑选第一个存在的真实文件（跳过目录前缀）
declare -a TARGETS
for g in "${GNAMES[@]}"; do
  chosen=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ -f "$SRC_DIR/$p" ]; then chosen="$p"; break; fi
  done <<< "${GFILES[$g]}"
  [ -n "$chosen" ] || die "补丁组 [$g] 在 codex/ 下找不到可注入标记的真实文件（清单里全是目录前缀？）"
  TARGETS+=("$chosen")
done

# —— 步骤 2：注入已知标记改动（每组一处，追加一行注释，不影响任何逻辑，且不编译） ——
log "步骤 2/7  向 ${#GNAMES[@]} 个补丁组各注入一处已知改动"
for i in "${!GNAMES[@]}"; do
  f="${TARGETS[$i]}"
  printf '\n%s\n' "$MARKER" >> "$SRC_DIR/$f"
  log "  ✎ [${GNAMES[$i]}]  $f"
done

# —— 步骤 3：记录期望改动 ——
# 用 `git diff HEAD`（相对基线，含已暂存与未暂存），因为 apply-patches.sh 的
# `git apply --3way` 隐含 --index，会把改动写进暂存区；普通 `git diff` 只看未暂存，
# 两步基准不一致会误判。统一用 `diff HEAD` 抹平暂存状态差异。
log "步骤 3/7  记录期望改动内容（git diff HEAD）"
git -C "$SRC_DIR" diff HEAD > "$TMP/expected.diff"
if [ ! -s "$TMP/expected.diff" ]; then
  die "注入标记后 codex/ 无改动，测试无法进行（文件可能不可写？）"
fi

# —— 步骤 4：导出补丁 ——
log "步骤 4/7  make-patches.sh 导出补丁"
"$SCRIPT_DIR/make-patches.sh"

# —— 步骤 5：还原到基线并校验 ——
log "步骤 5/7  reset-src.sh 还原到基线"
"$SCRIPT_DIR/reset-src.sh"

# 校验：还原后 submodule 干净且回到基线 SHA
after_status="$(git -C "$SRC_DIR" status --porcelain)"
[ -z "$after_status" ] || die "还原后校验失败：codex/ 仍有未清理的改动：
$after_status"
after_head="$(git -C "$SRC_DIR" rev-parse HEAD)"
[ "$after_head" = "$BASE_SHA" ] || die "还原后校验失败：codex/ HEAD=$after_head，与基线 $BASE_SHA 不符"
log "  ✓ codex/ 已回到基线且干净"

# —— 步骤 6：重新应用补丁 ——
log "步骤 6/7  apply-patches.sh 重新应用补丁"
"$SCRIPT_DIR/apply-patches.sh"

# —— 步骤 7：比对重应用后的改动与期望是否逐字节一致 ——
log "步骤 7/7  比对重应用结果与原始改动"
git -C "$SRC_DIR" diff HEAD > "$TMP/actual.diff"

if diff -u "$TMP/expected.diff" "$TMP/actual.diff" > "$TMP/roundtrip.diff"; then
  log "══════════════════════════════════════════════"
  log "✓ 端到端闭环无损：重应用后的改动与原始改动逐字节一致"
  log "  覆盖补丁组：${GNAMES[*]}"
  log "  全程未触发任何编译。"
  log "══════════════════════════════════════════════"
  exit 0
else
  err "✗ 闭环校验失败：重应用后的改动与原始改动不一致，差异如下："
  cat "$TMP/roundtrip.diff" >&2
  exit 1
fi
