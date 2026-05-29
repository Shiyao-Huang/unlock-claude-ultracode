# Inline one-shot command — no script file needed.
# Force-enable Claude Code 2.1.156 ultracode. Copy-paste the whole block into a terminal.
# Host-adaptive (auto-locates binary), idempotent, macOS re-signs / Linux skips.

bash -c '
set -euo pipefail
BIN="$(command -v claude 2>/dev/null || true)"
BIN="$(readlink -f "$BIN" 2>/dev/null || node -e "try{console.log(require(\"fs\").realpathSync(process.argv[1]))}catch(e){}" "$BIN" 2>/dev/null || true)"
[ -f "${BIN:-}" ] || BIN="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/bin/claude.exe"
[ -f "$BIN" ] || { echo "ERROR: claude binary not found"; exit 1; }
VER="$(node -e "console.log(require(require(\"path\").join(require(\"path\").dirname(process.argv[1]),\"..\",\"package.json\")).version)" "$BIN" 2>/dev/null || echo unknown)"
echo "target: $BIN ($VER)"
[ "$VER" = "2.1.156" ] || { echo "ERROR: expected 2.1.156, found $VER — aborting"; exit 1; }
mkdir -p "$HOME/.claude/backups"
BK="$HOME/.claude/backups/claude.exe.$VER.orig"
[ -f "$BK" ] || cp "$BIN" "$BK"
BIN="$BIN" python3 - <<"PY"
import os
p=os.environ["BIN"]; d=bytearray(open(p,"rb").read())
edits=[("v0",b"function v0(){if($K6())return!1;if(!q67())return!1;let{available:H,defaultOn:_}=$P8();if(!H)return!1;return UX5()??_}",b"function v0(){return!0"),
       ("vx",b"function vx(H){return v0()&&(H===void 0||VcH(H))}",b"function vx(H){return!0")]
M=b"ULTRACODE_PATCH"
def pad(c,t):
    n=t-(len(c)+len(b"/*")+len(M)+len(b"*/}"));
    return c+b"/*"+M+(b"-"*n)+b"*/}" if n>=0 else (_ for _ in ()).throw(SystemExit("too long"))
ch=0
for lbl,o,c in edits:
    r=pad(c,len(o)); assert len(r)==len(o)
    if d.count(r)>=1 and d.count(o)==0: print("[skip]",lbl); continue
    if d.count(o)!=1: raise SystemExit(f"[abort] {lbl}: found {d.count(o)} originals")
    i=d.find(o); d[i:i+len(o)]=r; ch+=1; print(f"[ok] {lbl} @ {i}")
if ch: open(p,"wb").write(d); print("[write]",ch)
else: print("[write] nothing to do")
PY
if [ "$(uname)" = "Darwin" ]; then codesign --remove-signature "$BIN" 2>/dev/null || true; codesign -f -s - "$BIN"; echo "[sign] ad-hoc re-signed"; else echo "[sign] non-macOS, skipped"; fi
echo "DONE. Quit and relaunch claude, then run: /effort ultracode"
'
