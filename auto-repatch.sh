#!/usr/bin/env bash
# auto-repatch.sh —— 每日自动检查更新 + 自适应重打补丁 + 版本分支
# auto-repatch.sh — daily auto-upgrade + adaptive re-patch + per-version branch
#
# 做三件事 / Does three things:
#   1. 查 npm registry 有无新版 Claude Code → 有则 npm i -g 升级
#   2. 对当前二进制跑 repatch-ultracode.sh(自适应,跨版本)
#   3. 每个新版本在 git 里建独立分支(如 patch/2.1.158),记录补丁状态
#
# 幂等;无更新则跳过;已补丁则跳过;分支已存在则跳过。适合 cron 调度。
#
# 用法:
#   bash auto-repatch.sh           # 交互(带颜色输出)
#   bash auto-repatch.sh --cron    # 静默模式(仅输出关键行,适合日志)
#
# 日志: ~/.claude/backups/auto-repatch.log

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${HOME}/.claude/backups/auto-repatch.log"
QUIET=0
[[ "${1:-}" == "--cron" ]] && QUIET=1

log()  { printf '%s\n' "$*"; }
quiet() { (( QUIET )) || printf '%s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

mkdir -p "$(dirname "$LOG")"

# ---------- helpers ----------

resolve_bin() {
  local link real root
  link="$(command -v claude 2>/dev/null || true)"
  if [[ -n "$link" ]]; then
    real="$(readlink -f "$link" 2>/dev/null || true)"
    [[ -z "$real" ]] && real="$(node -e 'console.log(require("fs").realpathSync(process.argv[1]))' "$link" 2>/dev/null || true)"
    [[ -n "$real" && -f "$real" ]] && { printf '%s\n' "$real"; return; }
  fi
  root="$(npm root -g 2>/dev/null || true)"
  [[ -n "$root" ]] && printf '%s\n' "$root/@anthropic-ai/claude-code/bin/claude.exe"
}

installed_version() {
  local pkg
  pkg="$(dirname "$(resolve_bin)")/../package.json"
  node -e "try{console.log(require('$pkg').version)}catch(e){console.log('unknown')}" 2>/dev/null || echo unknown
}

latest_version() {
  npm view @anthropic-ai/claude-code version 2>/dev/null || echo unknown
}

# ---------- main ----------

NOW="$(date '+%Y-%m-%d %H:%M:%S')"
quiet "[$NOW] auto-repatch 开始"

CUR="$(installed_version)"
LAT="$(latest_version)"

quiet "  当前: $CUR  /  最新: $LAT"

if [[ "$CUR" == "unknown" || "$LAT" == "unknown" ]]; then
  die "无法获取版本(当前=$CUR, 最新=$LAT)"
fi

# --- 1) 升级 ---
UPGRADED=0
if [[ "$CUR" != "$LAT" ]]; then
  quiet "  升级 $CUR -> $LAT ..."
  if npm i -g "@anthropic-ai/claude-code@$LAT" >/dev/null 2>&1; then
    UPGRADED=1
    quiet "  升级完成: $(installed_version)"
  else
    quiet "  升级失败(下次重试)"
  fi
else
  quiet "  无需升级(已是最新)"
fi

# --- 2) 补丁 ---
REPATCH="$HERE/repatch-ultracode.sh"
if [[ ! -f "$REPATCH" ]]; then
  die "找不到 repatch-ultracode.sh (期望在同目录: $HERE)"
fi

quiet "  运行自适应补丁..."
PATCH_OK=0
if OUTPUT="$(bash "$REPATCH" 2>&1)"; then
  PATCH_OK=1
  quiet "  补丁结果: ok"
  (( QUIET )) || printf '%s\n' "$OUTPUT"
else
  quiet "  补丁结果: FAILED"
  printf '%s\n' "$OUTPUT"
fi

# --- 3) 版本分支 ---
# 每个打补丁的版本建一个 git 分支 patch/<version>,记录补丁元数据
# 分支内容:一个 JSON 文件记录版本号、补丁时间、结果、原始二进制 sha256
FINAL_VER="$(installed_version)"
BRANCH="patch/${FINAL_VER}"

if [[ "$PATCH_OK" == "1" ]] && [[ -d "$HERE/.git" ]]; then
  quiet "  处理版本分支 $BRANCH ..."
  # 在 repo 内操作 git(不影响用户当前工作分支)
  (
    cd "$HERE"
    # 分支已存在则跳过
    if git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
      quiet "  分支 $BRANCH 已存在,跳过"
      exit 0
    fi

    # 计算原始备份的 sha256(如果有的话)
    BK="$HOME/.claude/backups/claude.exe.${FINAL_VER}.orig"
    ORIG_SHA="n/a"
    [[ -f "$BK" ]] && ORIG_SHA="$(shasum -a 256 "$BK" | awk '{print $1}')"

    # 从 main 创建版本分支
    git branch "$BRANCH" main 2>/dev/null

    # 在临时索引上写元数据文件,commit 到分支(不切换工作树)
    TMPINDEX="$(mktemp)"
    GIT_INDEX_FILE="$TMPINDEX" git read-tree "$BRANCH"

    # 写版本元数据
    META="$HERE/.patch-meta-${FINAL_VER}.json"
    cat > "$META" <<METAEOF
{
  "version": "${FINAL_VER}",
  "patched_at": "${NOW}",
  "status": "ok",
  "original_sha256": "${ORIG_SHA}",
  "patcher": "repatch-ultracode.sh",
  "gates": {
    "workflow": "matched by shape: function NAME(){...let{available:A,defaultOn:B}=...;if(!A)return!1;return ...??B}",
    "admission": "matched by shape: function NAME(ARG){return FN()&&(ARG===void 0||FN2(ARG))}"
  }
}
METAEOF

    GIT_INDEX_FILE="$TMPINDEX" git add -f "patch-meta.json" 2>/dev/null || true
    # 用 hash-object + update-index 直接注入(更可靠)
    BLOB="$(git hash-object -w "$META")"
    rm -f "$META"
    GIT_INDEX_FILE="$TMPINDEX" git update-index --add --cacheinfo "100644,$BLOB,patch-meta.json"
    TREE="$(GIT_INDEX_FILE="$TMPINDEX" git write-tree)"
    PARENT="$(git rev-parse "$BRANCH")"
    COMMIT_MSG="patch: Claude Code ${FINAL_VER} — adaptive ultracode gate patch

Tested on ${FINAL_VER}: both gate functions matched by structural regex.
Patched at ${NOW}.

Gate A (admission): function NAME(ARG){return FN()&&(ARG===void 0||FN2(ARG))} -> return!0
Gate B (workflow):  function NAME(){...let{available:A,defaultOn:B}=FN();...}  -> return!0"

    NEW_COMMIT="$(git commit-tree "$TREE" -p "$PARENT" -m "$COMMIT_MSG")"
    git update-ref "refs/heads/$BRANCH" "$NEW_COMMIT"

    rm -f "$TMPINDEX"
    quiet "  分支 $BRANCH 已创建(commit: ${NEW_COMMIT:0:8})"
  )
fi

# --- 4) 日志 ---
{
  echo "[$NOW] version=$FINAL_VER upgrade=$([[ "$CUR" != "$LAT" ]] && echo "$CUR->$LAT" || echo "none") patch=$([[ "$PATCH_OK" == "1" ]] && echo "ok" || echo "fail") branch=$([[ "$PATCH_OK" == "1" ]] && echo "$BRANCH" || echo "n/a")"
} >> "$LOG"

# 裁剪日志:保留最近 200 行
LOG_LINES="$(wc -l < "$LOG" | tr -d ' ')"
if [[ "$LOG_LINES" -gt 200 ]]; then
  tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

quiet "[$NOW] auto-repatch 完成"

# 补丁失败时以非零退出(cron 可据此发告警)
[[ "$PATCH_OK" == "1" ]] || exit 1
