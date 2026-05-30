#!/usr/bin/env bash
# repatch-ultracode.sh —— 版本自适应的 ultracode 解锁补丁 / version-adaptive patcher
#
# 与 patch-ultracode.sh 的区别:不再硬编码 2.1.156 的函数名/字节串,而是用
# **结构正则** 定位两个门控函数,因此可跨小版本自适应(2.1.156 / 2.1.158 / …)。
#
# 两个门 / Two gates (names are minified and CHANGE between versions, so we match by shape):
#   GateB 工作流闸:  function NAME(){ ...let{available:A,defaultOn:B}=FN();if(!A)return!1;return FN2()??B }
#   GateA 准入门:    function NAME(ARG){return FN()&&(ARG===void 0||FN2(ARG))}
# 两处都被等长改写为 `return!0`,用 /*ULTRACODE_PATCH---*/ 注释补齐,不移动任何字节偏移。
#
# 幂等;macOS 自动 ad-hoc 重签名;自动备份到 ~/.claude/backups/claude.exe.<version>.orig。
#
# 用法:
#   bash repatch-ultracode.sh                  # 自动定位
#   bash repatch-ultracode.sh /path/claude.exe # 手动指定

set -euo pipefail

BACKUP_DIR="${HOME}/.claude/backups"

say()  { printf '%s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------- 1) 定位二进制 ----------
resolve_bin() {
  if [[ -n "${1:-}" ]]; then printf '%s\n' "$1"; return; fi
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

BIN="$(resolve_bin "${1:-}")"
[[ -n "$BIN" && -f "$BIN" ]] || die "找不到 claude 二进制。手动传入:bash $0 /path/to/claude.exe"
say "[1/5] 二进制: $BIN"

PKG="$(dirname "$BIN")/../package.json"
VERSION="$(node -e "try{console.log(require('$PKG').version)}catch(e){console.log('unknown')}" 2>/dev/null || echo unknown)"
say "       版本: $VERSION (自适应,不做版本锁)"

# ---------- 2) 备份 ----------
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/claude.exe.${VERSION}.orig"
if [[ ! -f "$BACKUP" ]]; then cp "$BIN" "$BACKUP"; say "[2/5] 已备份 -> $BACKUP"
else say "[2/5] 备份已存在 -> $BACKUP(保留)"; fi

# ---------- 3) 自适应正则补丁(等长替换) ----------
say "[3/5] 应用自适应补丁(GateA 准入门 + GateB 工作流闸)"
BIN="$BIN" python3 - <<'PY'
import os, re, sys
p = os.environ["BIN"]
d = bytearray(open(p, "rb").read())

MARK = b"ULTRACODE_PATCH"

# GateA: function NAME(ARG){return FN()&&(ARG===void 0||FN2(ARG))}
gate_a = re.compile(
    rb'function ([A-Za-z0-9_$]+)\(([A-Za-z0-9_$]+)\)\{return '
    rb'[A-Za-z0-9_$]+\(\)&&\(\2===void 0\|\|[A-Za-z0-9_$]+\(\2\)\)\}'
)
# GateB: function NAME(){ [0-4 guards] let{available:A,defaultOn:B}=FN();if(!A)return!1;return FN2()??B }
gate_b = re.compile(
    rb'function ([A-Za-z0-9_$]+)\(\)\{'
    rb'(?:if\(!?[A-Za-z0-9_$]+\(\)\)return!1;){0,4}'
    rb'let\{available:([A-Za-z0-9_$]+),defaultOn:([A-Za-z0-9_$]+)\}=[A-Za-z0-9_$]+\(\);'
    rb'if\(!\2\)return!1;return [A-Za-z0-9_$]+\(\)\?\?\3\}'
)
patched = re.compile(rb'function [A-Za-z0-9_$]+\([^)]*\)\{return!0/\*ULTRACODE_PATCH')

def build(core, total):
    fixed = len(core) + len(b"/*") + len(MARK) + len(b"*/}")
    pad = total - fixed
    if pad < 0:
        raise SystemExit(f"       [abort] core too long for {core!r}")
    return core + b"/*" + MARK + (b"-" * pad) + b"*/}"

# Collect matches first (so we can refuse on ambiguity before writing anything).
specs = []  # (label, match, core_without_padding)
ma = list(gate_a.finditer(d))
mb = list(gate_b.finditer(d))
already = len(list(patched.finditer(d)))

if not ma and not mb:
    if already >= 2:
        print(f"       [skip] 已是补丁状态(检测到 {already} 个 ULTRACODE_PATCH 标记)")
        raise SystemExit(0)
    raise SystemExit("       [abort] 两个门都没匹配到,且未检测到既有补丁——二进制结构可能已大改。")

for m in ma:
    name, arg = m.group(1), m.group(2)
    specs.append(("GateA 准入门", m, b"function " + name + b"(" + arg + b"){return!0"))
for m in mb:
    name = m.group(1)
    specs.append(("GateB 工作流闸", m, b"function " + name + b"(){return!0"))

# Refuse if any gate matched more than once (ambiguous → wrong target risk).
if len(ma) > 1: raise SystemExit(f"       [abort] GateA 匹配 {len(ma)} 处(应为 1),已中止。")
if len(mb) > 1: raise SystemExit(f"       [abort] GateB 匹配 {len(mb)} 处(应为 1),已中止。")

# Apply high-offset-first so earlier replacements don't shift later offsets
# (lengths are preserved anyway, but this is robust).
changed = 0
for label, m, core in sorted(specs, key=lambda s: s[1].start(), reverse=True):
    orig = m.group(0)
    repl = build(core, len(orig))
    assert len(repl) == len(orig), (label, len(repl), len(orig))
    i = m.start()
    d[i:i + len(orig)] = repl
    changed += 1
    print(f"       [ok] {label} @ {i}  ({m.group(1).decode()})")

if changed:
    open(p, "wb").write(d)
    print(f"       已写入 {changed} 处")
PY

# ---------- 4) 重签名(macOS) ----------
if [[ "$(uname)" == "Darwin" ]]; then
  if command -v codesign >/dev/null 2>&1; then
    codesign --remove-signature "$BIN" 2>/dev/null || true
    codesign -f -s - "$BIN"
    say "[4/5] 已 ad-hoc 重签名"
  else
    say "[4/5] 警告:未找到 codesign,二进制可能被系统拦杀" >&2
  fi
else
  say "[4/5] 非 macOS($(uname)),无需重签名"
fi

# ---------- 5) 验证 ----------
nmark=$(LC_ALL=C grep -a -c -F 'return!0/*ULTRACODE_PATCH' "$BIN" || true)
say "[5/5] 验证:ULTRACODE_PATCH 标记数 = $nmark(应为 2)"
"$BIN" --version >/dev/null 2>&1 && say "       二进制可启动: ok" || say "       警告:二进制启动检测失败"

cat <<'EOF'

✅ 完成。彻底退出并重启 claude,然后运行 /effort ultracode 验证。
   成功:Set effort level to ultracode (this session only): xhigh + dynamic workflow orchestration
EOF
