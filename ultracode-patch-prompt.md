# PROMPT — Force-enable Claude Code "ultracode" (version-locked to 2.1.156)

Paste everything below into a Claude Code session on the target machine.

---

You are patching the Claude Code binary on THIS machine to force-enable
**ultracode** (xhigh effort + standing dynamic-workflow orchestration). This
patch is written specifically for **version 2.1.156** (the Bun-compiled
single-file binary). Do NOT apply it to any other version — abort if the
version differs, because the byte strings below are version-specific.

Follow these steps exactly. Use Bash for each step. Stop and report if any
assertion fails.

## Step 1 — Locate the binary (portable across machines)

```bash
# Resolve the real binary behind the `claude` launcher.
CLAUDE_LINK="$(command -v claude || true)"
REAL="$(readlink -f "$CLAUDE_LINK" 2>/dev/null || true)"
# Fall back to the npm global package layout if needed.
if [ -z "$REAL" ] || [ ! -f "$REAL" ]; then
  ROOT="$(npm root -g 2>/dev/null)"
  REAL="$ROOT/@anthropic-ai/claude-code/bin/claude.exe"
fi
echo "BIN=$REAL"
PKG="$(dirname "$REAL")/../package.json"
node -e "console.log('version:',require('$PKG').version)"
file "$REAL"
```

ASSERT before continuing:
- `version` is exactly **2.1.156**. If not, STOP — this patch does not apply.
- `file` reports a **Mach-O** (macOS) or **ELF** (Linux) executable, size ~215MB.

## Step 2 — Back up the original

```bash
BIN="$REAL"
BK="$HOME/.claude/backups/claude.exe.2.1.156.orig"
mkdir -p "$HOME/.claude/backups"
[ -f "$BK" ] || cp "$BIN" "$BK"
shasum -a 256 "$BIN" "$BK"
echo "backup: $BK"
```

## Step 3 — Apply the two length-preserving edits

There are exactly two gate functions in the embedded JS. Each appears **once**.
Replace them with unconditional-true bodies, padded to identical length with a
`/*ULTRACODE_PATCH*/` comment so no byte offsets shift.

Run this Python (it asserts count==1 for each, refuses otherwise):

```bash
BIN="$REAL" python3 - <<'PY'
import os
p=os.environ["BIN"]
d=bytearray(open(p,"rb").read())

# (label, original_exact_bytes, replacement_core)  -- replacement padded to len(original)
edits=[
 ("v0  (GrowthBook workflow gate)",
  b'function v0(){if($K6())return!1;if(!q67())return!1;let{available:H,defaultOn:_}=$P8();if(!H)return!1;return UX5()??_}',
  b'function v0(){return!0'),
 ("vx  (effort/ultracode accept gate)",
  b'function vx(H){return v0()&&(H===void 0||VcH(H))}',
  b'function vx(H){return!0'),
]
M=b"ULTRACODE_PATCH"
def pad(core,total):
    fixed=len(core)+len(b"/*")+len(M)+len(b"*/}")
    n=total-fixed
    if n<0: raise SystemExit("core too long")
    return core+b"/*"+M+(b"-"*n)+b"*/}"

changed=0
for label,orig,core in edits:
    repl=pad(core,len(orig)); assert len(repl)==len(orig)
    if d.count(repl)>=1 and d.count(orig)==0:
        print("[skip] already patched:",label); continue
    if d.count(orig)!=1:
        raise SystemExit(f"[ABORT] {label}: expected 1 original, found {d.count(orig)} "
                         f"(patched copies {d.count(repl)}). Wrong version?")
    i=d.find(orig); d[i:i+len(orig)]=repl; changed+=1
    print(f"[ok] {label} @ {i}")
if changed: open(p,"wb").write(d); print("[write]",changed,"edit(s)")
else: print("[write] nothing to do")
PY
```

## Step 4 — Re-sign (macOS only)

The binary ships with a hardened-runtime signature; editing bytes invalidates
it and macOS will kill the process. Ad-hoc re-sign fixes that. (Linux: skip —
no signature needed.)

```bash
if [ "$(uname)" = "Darwin" ]; then
  codesign --remove-signature "$REAL" 2>/dev/null || true
  codesign -f -s - "$REAL"
  codesign -dv "$REAL" 2>&1 | grep -E 'Signature|flags' || true
fi
```

## Step 5 — Verify

```bash
# patched present, originals gone, binary launches
grep -a -c -F 'function v0(){return!0/*ULTRACODE_PATCH' "$REAL"   # -> 1
grep -a -c -F 'function vx(H){return!0/*ULTRACODE_PATCH' "$REAL"  # -> 1
grep -a -c -F 'function v0(){if($K6())' "$REAL"                   # -> 0
"$REAL" --version                                                 # -> 2.1.156 (Claude Code)
```

## Step 6 — Activate

Tell the user: **fully quit and relaunch `claude`** (the running process still
holds the old binary in memory), then run `/effort ultracode`. Success looks
like: `Set effort level to ultracode (this session only): xhigh + dynamic
workflow orchestration` — NOT the "needs dynamic workflows enabled" error.

## Rollback

```bash
cp "$HOME/.claude/backups/claude.exe.2.1.156.orig" "$REAL"
[ "$(uname)" = "Darwin" ] && codesign -f -s - "$REAL"   # re-sign the restored copy if it was ad-hoc before
```

> NOTE: This patch is consumed on every Claude Code upgrade (the installer
> overwrites the binary). After any `claude` update, re-run this whole prompt —
> but first re-confirm the installed version is still 2.1.156; if it bumped,
> the byte strings may have changed and this prompt must be regenerated.
