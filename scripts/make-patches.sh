#!/usr/bin/env bash
# 从 codex/ 当前工作区改动导出补丁到 brand/patches/。
#
# 工作方式:
#   - 读取 brand/patches.manifest,把改动的文件按「补丁组」归类;
#   - 对每个组用 `git diff` 生成一个 <组名>.patch(组名已含序号前缀);
#   - 未在 manifest 中列出的已改动文件会被警告(避免漏进补丁)。
#
# 用法:
#   1. ./scripts/reset-src.sh          # 先回到干净基线
#   2. ./scripts/apply-patches.sh      # (可选)先套上已有补丁
#   3. 手动编辑 codex/ 里的源码
#   4. ./scripts/make-patches.sh       # 导出补丁
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MANIFEST="$BRAND_DIR/patches.manifest"
[ -f "$MANIFEST" ] || die "找不到清单文件: $MANIFEST"

cd "$SRC_DIR"

# 收集当前所有已改动/新增的文件(相对 codex/ 的路径)
mapfile -t CHANGED < <(git -C "$SRC_DIR" diff --name-only; git -C "$SRC_DIR" ls-files --others --exclude-standard)
if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "codex/ 没有任何改动,无补丁可导出。"
  exit 0
fi

# 解析 manifest（分段格式，与 patches.manifest 一致）:
#   [组名]              段头，组名已含序号前缀，如 01-rename-cx
#   codex-rs/.../x.rs   属于该组的文件路径或目录前缀，一行一个
#   # 开头 / 行内 # 之后为注释
# 组名直接作为输出文件名 <组名>.patch。
# 例如:
#   [01-rename-cx]
#   codex-rs/cli/src/main.rs
#   [02-brand-i18n]
#   codex-rs/tui/src/onboarding/
declare -a GROUP_NAME
declare -a GROUP_PREFIXES                  # 每元素为该组所有前缀，换行分隔
cur=-1
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"                       # 去掉行内注释
  line="$(echo "$line" | xargs || true)"   # 去首尾空白
  [ -z "$line" ] && continue
  if [[ "$line" == \[*\] ]]; then          # 段头 [组名]
    name="${line#\[}"; name="${name%\]}"
    GROUP_NAME+=("$name")
    GROUP_PREFIXES+=("")
    cur=$(( ${#GROUP_NAME[@]} - 1 ))
  else                                     # 组内文件路径 / 前缀
    [ "$cur" -lt 0 ] && die "manifest 格式错误: 路径 '$line' 出现在任何 [组名] 段之前"
    GROUP_PREFIXES[$cur]+="$line"$'\n'
  fi
done < "$MANIFEST"

[ "${#GROUP_NAME[@]}" -gt 0 ] || die "清单为空,无法分组"

# 为每个改动文件找到所属组(在所有组的所有前缀里做最长前缀匹配),未匹配的收集到 orphans
declare -A GROUP_FILES
orphans=()
for f in "${CHANGED[@]}"; do
  best_idx=-1; best_len=-1
  for i in "${!GROUP_PREFIXES[@]}"; do
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      case "$f" in
        "$p"*) if [ "${#p}" -gt "$best_len" ]; then best_len="${#p}"; best_idx="$i"; fi ;;
      esac
    done <<< "${GROUP_PREFIXES[$i]}"
  done
  if [ "$best_idx" -ge 0 ]; then
    GROUP_FILES["$best_idx"]+="$f"$'\n'
  else
    orphans+=("$f")
  fi
done

if [ "${#orphans[@]}" -gt 0 ]; then
  echo "⚠ 以下已改动文件未在 patches.manifest 中归类,不会进补丁:" >&2
  printf '   %s\n' "${orphans[@]}" >&2
  echo "   如需纳入,请在 brand/patches.manifest 增加对应前缀。" >&2
fi

mkdir -p "$PATCHES_DIR"

# 按组导出补丁
exported=0
for i in "${!GROUP_NAME[@]}"; do
  files_blob="${GROUP_FILES[$i]:-}"
  [ -z "$files_blob" ] && continue
  mapfile -t files < <(printf '%s' "$files_blob" | sed '/^$/d')
  out="$PATCHES_DIR/${GROUP_NAME[$i]}.patch"
  # 对新增文件需要 git add -N 才能进 diff
  for f in "${files[@]}"; do
    git -C "$SRC_DIR" add -N -- "$f" 2>/dev/null || true
  done
  git -C "$SRC_DIR" diff -- "${files[@]}" > "$out"
  # 导出后校验：匹配到了文件却生成空补丁，是静默失败（见 TODO「已知问题 #1」），报错退出
  if [ ! -s "$out" ]; then
    rm -f "$out"
    die "导出失败：补丁组 [${GROUP_NAME[$i]}] 匹配到 ${#files[@]} 个已改动文件，但 git diff 生成的补丁为空。
    可能这些文件的改动已被 add/commit 到 codex/ 的 index，或路径匹配到了未真正改动的文件。
    受影响文件：${files[*]}"
  fi
  echo "✓ 导出 $(basename "$out")  (${#files[@]} 个文件)"
  exported=$((exported+1))
done

echo "完成,共导出 $exported 个补丁到 $PATCHES_DIR"
echo "提示:导出后可运行 ./scripts/reset-src.sh 把 codex/ 还原为干净基线。"
