# claude-ultracode-patch

Force-enable Claude Code's **ultracode** effort mode (xhigh reasoning + standing
dynamic-workflow orchestration) on the Bun-compiled single-file binary.

> 中文版见 [README.md](./README.md).

Claude Code ships new builds almost daily, and every upgrade overwrites the
binary and loses the patch. So this repo gives you two things:

1. A **version-adaptive** patcher that locates the gates by *code shape* instead
   of by hard-coded minified names — so it keeps working across daily releases
   without a rewrite.
2. An **auto-update switch** so a patched binary isn't silently replaced.

> ultracode exists only in the Bun single-file binary (2.1.113+), never in the
> Node `cli.js` builds.

## How it works

Claude Code gates `/effort ultracode` behind two predicates in its embedded JS.
Their names are **minified and change between versions** (e.g. `v0`/`vx` in
2.1.156 became `XW`/`Fx` in 2.1.158), so the adaptive patcher matches them by
structure:

| Gate | Original meaning | Patched to |
|---|---|---|
| **Workflow gate** | Are dynamic workflows enabled? `let{available,defaultOn}=…(); if(!available)return!1; return …()??defaultOn` | `return!0` (always on) |
| **Admission gate** | ultracode accept: `WORKFLOW() && (arg===undefined \|\| XHIGH_OK(arg))` | `return!0` (always accept) |

Both edits are **length-preserving** — the patched body is padded back to the
original length with a `/*ULTRACODE_PATCH---*/` comment, so no byte offsets
shift. On macOS, editing bytes invalidates the hardened-runtime signature and
the OS kills the process, so the script **ad-hoc re-signs** (`codesign -f -s -`);
Linux/ELF needs no signature and is skipped.

The scripts are **idempotent**, **host-adaptive** (auto-locate the binary), and
back the original up to `~/.claude/backups/claude.exe.<version>.orig`.

## Install

**All-in-one, version-adaptive, update-resilient (recommended):**

Disables auto-update (so the patch isn't overwritten) **and** applies the
adaptive patch + re-sign + verify, in one run:

```bash
git clone https://github.com/Shiyao-Huang/unlock-claude-ultracode.git
cd unlock-claude-ultracode
bash disable-autoupdate.sh
```

**Adaptive patch only (don't touch auto-update):**

```bash
bash repatch-ultracode.sh
# or pass an explicit path if auto-detect fails:
bash repatch-ultracode.sh /custom/path/to/claude.exe
```

> **Why disable auto-update?** Claude Code's background updater replaces the
> patched `claude.exe` with the stock binary, so ultracode vanishes. The
> all-in-one injects `env.DISABLE_AUTOUPDATER=1` into `~/.claude/settings.json`
> to prevent this. To upgrade later: manually
> `npm i -g @anthropic-ai/claude-code@latest`, then re-run the script.

## After patching

1. **Fully quit and relaunch `claude`** — the running process still holds the
   old binary in memory.
2. Run `/effort ultracode`.
3. Success looks like:
   `Set effort level to ultracode (this session only): xhigh + dynamic workflow orchestration`
   — not the `Ultracode needs dynamic workflows enabled` error.

## Keeping up with daily releases

Each upgrade overwrites the binary and drops the patch. The adaptive scripts are
built for exactly this — just re-run after any update:

```bash
bash disable-autoupdate.sh   # or: bash repatch-ultracode.sh
```

The adaptive patcher matches by structure, so it survives minified-name churn.
It **refuses to write** if it can't find the gates unambiguously — if a future
release reshapes the predicates it aborts cleanly (binary untouched) rather than
corrupting anything, and the gate regexes can be updated for the new shape.

## Rollback

```bash
BIN="$(readlink -f "$(command -v claude)" 2>/dev/null || echo "$(npm root -g)/@anthropic-ai/claude-code/bin/claude.exe")"
VER="$(node -e "console.log(require(require('path').join(require('path').dirname('$BIN'),'..','package.json')).version)")"
cp "$HOME/.claude/backups/claude.exe.$VER.orig" "$BIN"
[ "$(uname)" = "Darwin" ] && codesign -f -s - "$BIN"
```

## Requirements

- `python3` (byte patch), `node` (read version), `npm` (path fallback)
- macOS: `codesign` (ships with Xcode CLT)
- Claude Code 2.1.113+ (Bun single-file binary; tested on 2.1.156 and 2.1.158)

## Caveats

- This modifies an Anthropic-distributed binary; the signature becomes ad-hoc.
  Use at your own discretion.
- ultracode is "this session only" by design — it is not persisted to settings.

## Files

| File | Role | Version handling |
|---|---|---|
| `disable-autoupdate.sh` | **All-in-one**: disable auto-update + adaptive patch + re-sign + verify | adaptive (prefers `repatch`) |
| `repatch-ultracode.sh` | Adaptive patch only — locates gates by code shape, refuses on ambiguity | adaptive ✅ |
| `unlock-ultracode.sh` | Older all-in-one (disable update + patch + re-sign) | **locked to 2.1.156** |
| `patch-ultracode.sh` | Older patch-only | **locked to 2.1.156** |
| `inline-command.sh` | No-file copy-paste one-liner | **locked to 2.1.156** |
| `ultracode-patch-prompt.md` | Prompt to drive the patch via a Claude Code session | **locked to 2.1.156** |

> The `*-locked to 2.1.156*` scripts hard-code that version's minified names and
> refuse other versions. For daily-updated installs, use the **adaptive** path
> (`disable-autoupdate.sh` / `repatch-ultracode.sh`).
