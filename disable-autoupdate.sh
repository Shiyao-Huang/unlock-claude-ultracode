#!/usr/bin/env bash
# disable-autoupdate.sh
# 一键:关闭 Claude Code 自动更新 + 重新打 ultracode 补丁。
# One-shot: disable Claude Code auto-update, then (re)apply the ultracode patch.
#
# 背景 / Why: Claude Code 的后台自动更新会用官方原版二进制覆盖打过补丁的 claude.exe,
# 导致 ultracode 消失。决策函数 bLH() 的判定优先级:
#   1. env DISABLE_UPDATES           -> 禁用
#   2. env DISABLE_AUTOUPDATER        -> 禁用   ← 本脚本采用(最可靠,native 安装无例外)
#   3. settings.autoUpdates===false   -> 仅当非 native 或未 protectedForNative 时生效
# 所以这里通过往 ~/.claude/settings.json 的 env 注入 DISABLE_AUTOUPDATER=1 来根治,
# Claude Code 启动时会把 settings.env 注入 process.env。
#
# 幂等:可重复运行。已设置则跳过;已打补丁则 skip。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

echo "[1/3] 关闭自动更新 -> $SETTINGS"

# 用 node 安全改 JSON(保留所有其他字段,不破坏格式语义)。
node - "$SETTINGS" <<'NODE'
const fs = require("fs");
const p = process.argv[2];
let s = {};
try { s = JSON.parse(fs.readFileSync(p, "utf8")); }
catch (e) { console.log("  (settings 不存在或无法解析,将新建)"); s = {}; }

s.env = s.env || {};
if (s.env.DISABLE_AUTOUPDATER === "1") {
  console.log("  已存在 env.DISABLE_AUTOUPDATER=1,跳过");
} else {
  s.env.DISABLE_AUTOUPDATER = "1";
  // 备份一次原文件
  try {
    const bk = p + ".bak." + Date.now();
    if (fs.existsSync(p)) fs.copyFileSync(p, bk), console.log("  已备份 ->", bk);
  } catch (e) {}
  fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n");
  console.log("  已写入 env.DISABLE_AUTOUPDATER=1");
}
NODE

echo "[2/3] 应用 ultracode 补丁(优先用版本自适应的 repatch)"
# 优先 repatch-ultracode.sh:结构正则定位两个门控函数,跨小版本自适应(2.1.156/158/…)。
# 仅当它不存在时,才回退到版本锁定的 patch-ultracode.sh(只认 2.1.156)。
# One-shot: prefer the version-adaptive repatch; fall back to the 2.1.156-locked patch.
if [[ -f "$HERE/repatch-ultracode.sh" ]]; then
  bash "$HERE/repatch-ultracode.sh"
elif [[ -f "$HERE/patch-ultracode.sh" ]]; then
  echo "  (未找到 repatch-ultracode.sh,回退到版本锁定的 patch-ultracode.sh)" >&2
  bash "$HERE/patch-ultracode.sh"
else
  echo "ERROR: 找不到同目录的 repatch-ultracode.sh 或 patch-ultracode.sh" >&2
  exit 1
fi

echo "[3/3] 完成"
echo "  退出并重启 claude 后,自动更新已关闭,ultracode 也已生效。"
echo "  运行 /effort ultracode 验证。"
echo
echo "  注意:DISABLE_AUTOUPDATER 关闭后将不再自动获取新版本;"
echo "        需要升级时,手动改回 settings.json 或 npm i -g @anthropic-ai/claude-code@latest,"
echo "        升级后记得重跑本脚本重新打补丁。"
