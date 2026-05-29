#!/usr/bin/env bash
# patch-ultracode.sh
# Force-enable Claude Code "ultracode" effort mode in the Bun-compiled binary.
#
# ultracode = xhigh effort + standing dynamic-workflow orchestration.
# It is gated by two predicates in the embedded JS:
#   v0()  -> "are dynamic workflows enabled" (GrowthBook: tengu_workflows_enabled / allow_workflows)
#   vx(H) -> "/effort ultracode" accept gate: v0() && (H===undefined || VcH(H))  (VcH = xhigh-capable model)
# This script rewrites both to unconditionally return true, length-preserving,
# then re-signs the Mach-O (hardened-runtime requires a valid signature on macOS).
#
# Idempotent + re-runnable: safe to run again after a Claude Code upgrade.

set -euo pipefail

# --- locate the real claude binary (host-adaptive) ----------------------------
# Priority: explicit $1 arg > `claude` on PATH (resolved) > npm global layout.
resolve_bin() {
  if [[ -n "${1:-}" ]]; then printf '%s\n' "$1"; return; fi
  local link real root
  link="$(command -v claude 2>/dev/null || true)"
  if [[ -n "$link" ]]; then
    # readlink -f isn't on stock macOS; fall back to a portable resolver.
    real="$(readlink -f "$link" 2>/dev/null || true)"
    if [[ -z "$real" ]]; then
      real="$(node -e 'console.log(require("fs").realpathSync(process.argv[1]))' "$link" 2>/dev/null || true)"
    fi
    [[ -n "$real" && -f "$real" ]] && { printf '%s\n' "$real"; return; }
  fi
  root="$(npm root -g 2>/dev/null || true)"
  [[ -n "$root" ]] && printf '%s\n' "$root/@anthropic-ai/claude-code/bin/claude.exe"
}

BIN="$(resolve_bin "${1:-}")"
BACKUP_DIR="${HOME}/.claude/backups"

if [[ -z "$BIN" || ! -f "$BIN" ]]; then
  echo "ERROR: could not locate claude binary (tried PATH + npm root -g)." >&2
  echo "       Pass the path explicitly: $0 /path/to/claude.exe" >&2
  exit 1
fi

# Resolve version for the backup name (best effort).
PKG_JSON="$(dirname "$BIN")/../package.json"
VERSION="$(node -e "try{console.log(require('$PKG_JSON').version)}catch(e){console.log('unknown')}" 2>/dev/null || echo unknown)"
BACKUP="${BACKUP_DIR}/claude.exe.${VERSION}.orig"

mkdir -p "$BACKUP_DIR"
if [[ ! -f "$BACKUP" ]]; then
  cp "$BIN" "$BACKUP"
  echo "[backup] saved original -> $BACKUP"
else
  echo "[backup] already exists -> $BACKUP (left untouched)"
fi

echo "[patch] target: $BIN (version $VERSION)"

# --- version guard ------------------------------------------------------------
# The byte strings below are specific to 2.1.156. Refuse other versions so a
# blind `curl | bash` on an upgraded install can't corrupt the binary.
EXPECTED_VERSION="2.1.156"
if [[ "${ULTRACODE_SKIP_VERSION_CHECK:-0}" != "1" && "$VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "ERROR: this patch targets Claude Code $EXPECTED_VERSION, but found $VERSION." >&2
  echo "       The embedded JS byte strings differ between versions — aborting to" >&2
  echo "       avoid corrupting the binary. Regenerate the patch for $VERSION, or" >&2
  echo "       re-run with ULTRACODE_SKIP_VERSION_CHECK=1 if you know they match." >&2
  exit 1
fi

# --- byte-level patch (length-preserving) -------------------------------------
python3 - "$BIN" <<'PY'
import sys

path = sys.argv[1]
data = bytearray(open(path, "rb").read())

# (label, original_exact_bytes, replacement_core_without_padding)
# Replacement is padded to the original length with a /*...*/ block comment.
edits = [
    (
        "v0 (GrowthBook workflow gate)",
        b'function v0(){if($K6())return!1;if(!q67())return!1;let{available:H,defaultOn:_}=$P8();if(!H)return!1;return UX5()??_}',
        b'function v0(){return!0',  # + padding comment + }
    ),
    (
        "vx (effort/ultracode accept gate)",
        b'function vx(H){return v0()&&(H===void 0||VcH(H))}',
        b'function vx(H){return!0',  # + padding comment + }
    ),
]

MARKER = b"ULTRACODE_PATCH"

def build_replacement(core, total_len):
    # core ... /*MARKER<pad>*/}   == total_len bytes
    suffix = b"*/}"
    open_c = b"/*"
    fixed = len(core) + len(open_c) + len(MARKER) + len(suffix)
    pad = total_len - fixed
    if pad < 0:
        raise SystemExit(f"replacement too long for {core!r}: need {total_len}, fixed {fixed}")
    return core + open_c + MARKER + (b"-" * pad) + suffix

changed = 0
for label, orig, core in edits:
    repl = build_replacement(core, len(orig))
    assert len(repl) == len(orig), (label, len(repl), len(orig))

    n_orig = data.count(orig)
    n_repl = data.count(repl)

    if n_repl >= 1 and n_orig == 0:
        print(f"[skip] {label}: already patched")
        continue
    if n_orig != 1:
        raise SystemExit(
            f"[abort] {label}: expected exactly 1 occurrence of original, found {n_orig} "
            f"(already-patched copies: {n_repl}). Binary may be a different version."
        )

    idx = data.find(orig)
    data[idx:idx + len(orig)] = repl
    changed += 1
    print(f"[ok]   {label}: patched at offset {idx}")

if changed:
    open(path, "wb").write(data)
    print(f"[write] {changed} edit(s) applied")
else:
    print("[write] nothing to change (already fully patched)")
PY

# --- re-sign (ad-hoc, macOS only) ---------------------------------------------
# macOS ships the binary with a hardened-runtime signature; any byte edit
# invalidates it and the OS kills the process. Ad-hoc re-sign lets it run
# locally. Linux/ELF has no such requirement, so skip there.
if [[ "$(uname)" == "Darwin" ]]; then
  if command -v codesign >/dev/null 2>&1; then
    echo "[sign] re-signing ad-hoc (codesign -f -s -)"
    codesign --remove-signature "$BIN" 2>/dev/null || true
    codesign -f -s - "$BIN"
    echo "[verify] codesign:"
    codesign -dv "$BIN" 2>&1 | sed 's/^/    /' | head -8
  else
    echo "[sign] WARNING: codesign not found on macOS — binary may be killed by Gatekeeper." >&2
  fi
else
  echo "[sign] non-macOS ($(uname)) — no re-signing needed"
fi

echo
echo "DONE. ultracode gates forced on."
echo "Restart claude (exit this session and relaunch), then run: /effort ultracode"
