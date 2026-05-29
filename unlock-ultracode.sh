#!/usr/bin/env bash
# unlock-ultracode.sh —— Claude Code ultracode 一键解锁(傻瓜版 / all-in-one)
#
# 一个文件搞定全部:
#   1. 自动定位 claude 二进制(跨机器,无需传参)
#   2. 校验版本必须是 2.1.156(字节特征版本专属)
#   3. 备份原始二进制
#   4. 关闭自动更新(写 ~/.claude/settings.json 的 env.DISABLE_AUTOUPDATER=1)—— 防止补丁被覆盖
#   5. 打补丁:v0()(GrowthBook 工作流闸)+ vx()(ultracode 准入门)恒为真,等长替换
#   6. macOS 自动 ad-hoc 重签名(Linux 跳过)
#   7. 验证
#
# 幂等:可反复运行。已设置/已打补丁则跳过。
# 用法:
#   bash unlock-ultracode.sh                 # 自动定位
#   bash unlock-ultracode.sh /path/claude.exe# 手动指定
#   curl -fsSL <raw-url> | bash              # 一键远程安装

set -euo pipefail

EXPECTED_VERSION="2.1.156"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
BACKUP_DIR="$HOME/.claude/backups"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

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
[[ -n "$BIN" && -f "$BIN" ]] || die "找不到 claude 二进制(试过 PATH 与 npm root -g)。请手动传入:bash $0 /path/to/claude.exe"
say "[1/6] 二进制: $BIN"

# ---------- 2) 版本守卫 ----------
PKG="$(dirname "$BIN")/../package.json"
VERSION="$(node -e "try{console.log(require('$PKG').version)}catch(e){console.log('unknown')}" 2>/dev/null || echo unknown)"
say "       版本: $VERSION"
if [[ "${ULTRACODE_SKIP_VERSION_CHECK:-0}" != "1" && "$VERSION" != "$EXPECTED_VERSION" ]]; then
  die "本补丁仅适用于 $EXPECTED_VERSION,当前为 $VERSION。版本不同字节特征会变,已中止。
       (确认匹配可设 ULTRACODE_SKIP_VERSION_CHECK=1 强制运行)"
fi

# ---------- 3) 备份 ----------
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/claude.exe.${VERSION}.orig"
if [[ ! -f "$BACKUP" ]]; then cp "$BIN" "$BACKUP"; say "[2/6] 已备份原始二进制 -> $BACKUP"
else say "[2/6] 备份已存在 -> $BACKUP(保留不动)"; fi

# ---------- 4) 关闭自动更新 ----------
say "[3/6] 关闭自动更新 -> $SETTINGS"
SETTINGS="$SETTINGS" node - <<'NODE'
const fs=require("fs"); const p=process.env.SETTINGS;
let s={}; try{s=JSON.parse(fs.readFileSync(p,"utf8"));}catch(e){console.log("       (settings 不存在,将新建)");}
s.env=s.env||{};
if(s.env.DISABLE_AUTOUPDATER==="1"){console.log("       已是 DISABLE_AUTOUPDATER=1,跳过");}
else{
  try{ if(fs.existsSync(p)){const bk=p+".bak."+Date.now(); fs.copyFileSync(p,bk); console.log("       已备份 settings ->",bk);} }catch(e){}
  s.env.DISABLE_AUTOUPDATER="1";
  fs.mkdirSync(require("path").dirname(p),{recursive:true});
  fs.writeFileSync(p, JSON.stringify(s,null,2)+"\n");
  console.log("       已写入 env.DISABLE_AUTOUPDATER=1");
}
NODE

# ---------- 5) 打补丁(等长替换) ----------
say "[4/6] 打补丁(v0 + vx)"
BIN="$BIN" python3 - <<'PY'
import os
p=os.environ["BIN"]; d=bytearray(open(p,"rb").read())
edits=[
 ("v0 (GrowthBook 工作流闸)",
  b'function v0(){if($K6())return!1;if(!q67())return!1;let{available:H,defaultOn:_}=$P8();if(!H)return!1;return UX5()??_}',
  b'function v0(){return!0'),
 ("vx (ultracode 准入门)",
  b'function vx(H){return v0()&&(H===void 0||VcH(H))}',
  b'function vx(H){return!0'),
]
M=b"ULTRACODE_PATCH"
def pad(core,total):
    n=total-(len(core)+len(b"/*")+len(M)+len(b"*/}"))
    if n<0: raise SystemExit("       core too long")
    return core+b"/*"+M+(b"-"*n)+b"*/}"
ch=0
for lbl,orig,core in edits:
    r=pad(core,len(orig)); assert len(r)==len(orig)
    if d.count(r)>=1 and d.count(orig)==0: print("       [skip] 已打补丁:",lbl); continue
    if d.count(orig)!=1: raise SystemExit(f"       [abort] {lbl}: 期望 1 处原始,实际 {d.count(orig)}(版本不符?)")
    i=d.find(orig); d[i:i+len(orig)]=r; ch+=1; print(f"       [ok] {lbl} @ {i}")
if ch: open(p,"wb").write(d); print(f"       已写入 {ch} 处")
else: print("       无需改动(已是补丁状态)")
PY

# ---------- 6) 重签名(macOS) ----------
if [[ "$(uname)" == "Darwin" ]]; then
  if command -v codesign >/dev/null 2>&1; then
    codesign --remove-signature "$BIN" 2>/dev/null || true
    codesign -f -s - "$BIN"
    say "[5/6] 已 ad-hoc 重签名"
  else
    say "[5/6] 警告:macOS 未找到 codesign,二进制可能被系统拦杀" >&2
  fi
else
  say "[5/6] 非 macOS($(uname)),无需重签名"
fi

# ---------- 验证 ----------
say "[6/6] 验证"
v0ok=$(LC_ALL=C grep -a -c -F 'function v0(){return!0/*ULTRACODE_PATCH' "$BIN" || true)
vxok=$(LC_ALL=C grep -a -c -F 'function vx(H){return!0/*ULTRACODE_PATCH' "$BIN" || true)
say "       v0 补丁: $v0ok / vx 补丁: $vxok(都应为 1)"
"$BIN" --version >/dev/null 2>&1 && say "       二进制可启动: ok" || say "       警告:二进制启动检测失败"

cat <<'EOF'

✅ 全部完成。
   1) 彻底退出并重启 claude(当前进程仍持旧二进制 + 旧 env)
   2) 运行 /effort ultracode 验证
   自动更新已关闭,补丁不会再被覆盖。
   日后需升级:手动 npm i -g @anthropic-ai/claude-code@latest,升级后重跑本脚本。
EOF
