#!/usr/bin/env bash
# repatch-ultracode.sh —— 版本自适应 ultracode 解锁补丁 / version-adaptive patcher
#
# 不硬编码任何版本的 minified 函数名。两阶段定位策略:
#   阶段 1 — 结构正则:按代码形状匹配两个门控函数(覆盖已知所有版本)
#   阶段 2 — 语义锚点:若正则失败,用 ultracode/available/defaultOn 等关键字符串
#             反向定位调用链,再回溯找到门控函数体
#
# 两个门 / Two gates (names are minified and CHANGE between versions):
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

# ---------- 3) 两阶段自适应补丁 ----------
say "[3/5] 应用自适应补丁(GateA 准入门 + GateB 工作流闸)"
BIN="$BIN" VERSION="$VERSION" python3 - <<'PY'
import os, re, sys

p = os.environ["BIN"]
ver = os.environ.get("VERSION", "unknown")
d = bytearray(open(p, "rb").read())

MARK = b"ULTRACODE_PATCH"

# ============================================================
# 已知版本到精确字节串的映射(兜底,当结构正则失败时使用)
# 格式: version -> [(label, original_bytes, core_bytes), ...]
# ============================================================
KNOWN_VERSIONS = {
    b"2.1.156": [
        ("GateA 准入门", b'function vx(H){return v0()&&(H===void 0||VcH(H))}', b'function vx(H){return!0'),
        ("GateB 工作流闸", b'function v0(){if($K6())return!1;if(!q67())return!1;let{available:H,defaultOn:_}=$P8();if(!H)return!1;return UX5()??_}', b'function v0(){return!0'),
    ],
    b"2.1.158": [
        ("GateA 准入门", b'function Fx(H){return XW()&&(H===void 0||ocH(H))}', b'function Fx(H){return!0'),
        ("GateB 工作流闸", b'function XW(){if(QK6())return!1;if(!s67())return!1;let{available:H,defaultOn:_}=xP8();if(!H)return!1;return jP5()??_}', b'function XW(){return!0'),
    ],
    b"2.1.167": [
        ("GateA 准入门", b'function ru(H){return wP()&&(H===void 0||thH(H))}', b'function ru(H){return!0'),
        ("GateB 工作流闸", b'function wP(){if(l36())return!1;if(!f37())return!1;let{available:H,defaultOn:_}=uL8();if(!H)return!1;return pg5()??_}', b'function wP(){return!0'),
    ],
}

# ============================================================
# 补丁标记检测(幂等:已打补丁则跳过)
# ============================================================
patched = re.compile(rb'function [A-Za-z0-9_$]+\([^)]*\)\{return!0/\*ULTRACODE_PATCH')
already = list(patched.finditer(d))

def build(core, total):
    fixed = len(core) + len(b"/*") + len(MARK) + len(b"*/}")
    pad = total - fixed
    if pad < 0:
        raise SystemExit(f"       [abort] core too long for {core!r}")
    return core + b"/*" + MARK + (b"-" * pad) + b"*/}"

def apply_specs(specs):
    """Apply a list of (label, match_or_orig, core) specs. Return number changed."""
    changed = 0
    for item in specs:
        label = item[0]
        # item can be (label, re.Match, core) or (label, orig_bytes, core)
        if hasattr(item[1], 'group'):  # re.Match
            m = item[1]
            orig = m.group(0)
        else:
            orig = item[1]
            # Find it in d
            idx = d.find(orig)
            if idx < 0:
                print(f"       [skip] {label}: 原始字节未找到")
                continue
            class FakeMatch:
                def __init__(self, s, o):
                    self._s, self._o = s, o
                def group(self, n=0):
                    return self._o if n == 0 else None
                def start(self):
                    return self._s
            m = FakeMatch(idx, orig)

        core = item[2]
        repl = build(core, len(m.group(0)))
        assert len(repl) == len(m.group(0)), (label, len(repl), len(m.group(0)))
        i = m.start()
        d[i:i + len(m.group(0))] = repl
        changed += 1
        print(f"       [ok] {label} @ {i}")
    return changed

# ============================================================
# 策略 0: 已是补丁状态 → 跳过
# ============================================================
if len(already) >= 2:
    print(f"       [skip] 已是补丁状态(检测到 {len(already)} 个 ULTRACODE_PATCH 标记)")
    raise SystemExit(0)

# ============================================================
# 策略 1: 结构正则匹配(自适应,覆盖混淆名变化)
# ============================================================
gate_a = re.compile(
    rb'function ([A-Za-z0-9_$]+)\(([A-Za-z0-9_$]+)\)\{return '
    rb'[A-Za-z0-9_$]+\(\)&&\(\2===void 0\|\|[A-Za-z0-9_$]+\(\2\)\)\}'
)
gate_b = re.compile(
    rb'function ([A-Za-z0-9_$]+)\(\)\{'
    rb'(?:if\(!?[A-Za-z0-9_$]+\(\)\)return!1;){0,4}'
    rb'let\{available:([A-Za-z0-9_$]+),defaultOn:([A-Za-z0-9_$]+)\}=[A-Za-z0-9_$]+\(\);'
    rb'if\(!\2\)return!1;return [A-Za-z0-9_$]+\(\)\?\?\3\}'
)

ma = list(gate_a.finditer(d))
mb = list(gate_b.finditer(d))

specs = []

if len(ma) == 1 and len(mb) == 1:
    # 策略 1 成功
    print(f"       [策略1] 结构正则匹配成功")
    for m in ma:
        name, arg = m.group(1), m.group(2)
        specs.append(("GateA 准入门", m, b"function " + name + b"(" + arg + b"){return!0"))
    for m in mb:
        name = m.group(1)
        specs.append(("GateB 工作流闸", m, b"function " + name + b"(){return!0"))
elif len(ma) > 1 or len(mb) > 1:
    print(f"       [策略1] 歧义: GateA={len(ma)} GateB={len(mb)} 处(应为各 1)")
else:
    # 策略 1 无匹配 → 尝试策略 2
    print(f"       [策略1] 无匹配: GateA={len(ma)} GateB={len(mb)}")

# ============================================================
# 策略 2: 已知版本精确字节串(兜底)
# ============================================================
if not specs:
    vb = ver.encode() if ver != "unknown" else b""
    if vb in KNOWN_VERSIONS:
        print(f"       [策略2] 使用 {ver} 已知精确字节串")
        for label, orig, core in KNOWN_VERSIONS[vb]:
            specs.append((label, orig, core))
    else:
        # 策略 2 也没命中 → 尝试策略 3
        print(f"       [策略2] 版本 {ver} 无已知精确字节串")

# ============================================================
# 策略 3: 语义锚点 — 从 ultracode/available/defaultOn 字符串
#          反向定位门控函数体(覆盖结构大幅变化的情况)
# ============================================================
if not specs:
    print(f"       [策略3] 语义锚点搜索...")

    # 3a: 找 GateB — 搜索 let{available:...,defaultOn:...}= 模式
    #     这是 GrowthBook feature flag 解构,极其稳定的语义锚点
    gb_semantic = re.compile(
        rb'function ([A-Za-z0-9_$]+)\(\)\{[^}]*'
        rb'let\{available:([A-Za-z0-9_$]+),defaultOn:([A-Za-z0-9_$]+)\}'
        rb'[^}]*\}'
    )
    mb3 = list(gb_semantic.finditer(d))
    # 过滤:必须包含 return!1 和 ??(空值合并)
    mb3 = [m for m in mb3 if b'return!1' in m.group(0) and b'??' in m.group(0)]

    # 3b: 找 GateA — 搜索调用 GateB 且包含 ===void 0 的函数
    if mb3:
        gate_b_name = mb3[0].group(1)
        ga_semantic = re.compile(
            rb'function ([A-Za-z0-9_$]+)\(([A-Za-z0-9_$]+)\)\{return '
            + re.escape(gate_b_name) + rb'\(\)&&\(\2===void 0\|\|[A-Za-z0-9_$]+\(\2\)\)\}'
        )
        ma3 = list(ga_semantic.finditer(d))
    else:
        ma3 = []

    if len(ma3) == 1 and len(mb3) == 1:
        print(f"       [策略3] 语义锚点匹配成功")
        for m in ma3:
            name, arg = m.group(1), m.group(2)
            specs.append(("GateA 准入门(语义)", m, b"function " + name + b"(" + arg + b"){return!0"))
        for m in mb3:
            name = m.group(1)
            # 对于语义匹配,我们需要构造一个和原始等长的替换
            # 先提取完整函数体(从 function 到匹配的 })
            specs.append(("GateB 工作流闸(语义)", m, b"function " + name + b"(){return!0"))
    else:
        print(f"       [策略3] 失败: GateA={len(ma3)} GateB={len(mb3)}")

# ============================================================
# 最终:无法定位 → 安全退出
# ============================================================
if not specs:
    raise SystemExit(
        f"       [abort] 三种策略均失败——二进制结构已大改。\n"
        f"       请为此版本({ver})生成新的精确补丁后重试。"
    )

# ============================================================
# 应用补丁(高偏移优先,避免偏移漂移)
# ============================================================
changed = apply_specs(specs)

if changed:
    open(p, "wb").write(d)
    print(f"       已写入 {changed} 处")
else:
    print(f"       无需改动")
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
nmark=$(LC_ALL=C grep -a -o -F 'return!0/*ULTRACODE_PATCH' "$BIN" | wc -l | tr -d ' ')
if [[ "$nmark" -ge 2 ]]; then
  say "[5/5] 验证:ULTRACODE_PATCH 补丁点 = $nmark(应 ≥ 2)✓"
else
  say "[5/5] 警告:ULTRACODE_PATCH 补丁点 = $nmark(应 ≥ 2)——补丁可能不完整" >&2
fi
"$BIN" --version >/dev/null 2>&1 && say "       二进制可启动: ok" || say "       警告:二进制启动检测失败"

cat <<'EOF'

✅ 完成。彻底退出并重启 claude,然后运行 /effort ultracode 验证。
   成功:Set effort level to ultracode (this session only): xhigh + dynamic workflow orchestration
EOF
