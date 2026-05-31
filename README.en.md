<div align="center">

# Unlock Claude Code Ultracode Mode

**Force-enable Claude Code `ultracode` effort mode** — xhigh reasoning + dynamic workflow orchestration

English · [中文](./README.md)

[![GitHub release](https://img.shields.io/github/v/tag/Shiyao-Huang/unlock-claude-ultracode?label=version&color=brightgreen)](https://github.com/Shiyao-Huang/unlock-claude-ultracode)
[![Supported versions](https://img.shields.io/badge/claude%20code-2.1.113%2B-blue)](https://www.npmjs.com/package/@anthropic-ai/claude-code)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](https://github.com/Shiyao-Huang/unlock-claude-ultracode)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Auto-update](https://img.shields.io/badge/daily%20cron-auto%20repatch-orange)](./auto-repatch.sh)

One-click unlock for Claude Code's hidden **ultracode** effort level (maximum reasoning + standing
dynamic-workflow orchestration). Version-adaptive — automatically handles 2.1.156, 2.1.158, and
future daily builds without manual patch updates. Ships with a daily cron for auto-upgrade + re-patch.

</div>

---

## Features

- **🔓 One-click ultracode unlock** — `/effort ultracode` just works, enabling xhigh + dynamic workflows
- **🔄 Version-adaptive** — three-stage gate detection (structural regex → known patterns → semantic anchors) adapts across builds
- **⏰ Daily auto-update** — cron checks npm for new versions, auto-upgrades, re-patches, and records a per-version git branch
- **🛡️ Safe & reversible** — idempotent, length-preserving edits, automatic backup, macOS re-signing, full rollback
- **🖥️ Cross-platform** — macOS (Apple Silicon / Intel) + Linux, auto-locates binary, no manual path needed

## Quick Start

**Recommended: all-in-one install (disable auto-update + patch + re-sign)**

```bash
git clone https://github.com/Shiyao-Huang/unlock-claude-ultracode.git
cd unlock-claude-ultracode
bash disable-autoupdate.sh
```

**Patch only (leave auto-update settings untouched)**

```bash
bash repatch-ultracode.sh
```

**Set up daily auto-update (runs at 3 AM every day)**

```bash
(crontab -l 2>/dev/null | grep -v auto-repatch; echo "0 3 * * * /bin/bash $(pwd)/auto-repatch.sh --cron >> ~/.claude/backups/auto-repatch-stdout.log 2>&1") | crontab -
```

After patching, **fully quit and relaunch `claude`**, then run:

```
/effort ultracode
```

Success: `Set effort level to ultracode (this session only): xhigh + dynamic workflow orchestration`

## How It Works

Claude Code gates `/effort ultracode` behind two predicates in the Bun-compiled binary's embedded JS:

| Gate | Original logic | Patched to |
|---|---|---|
| **Workflow Gate** | `let{available:A,defaultOn:B}=FN(); if(!A)return!1; return FN2()??B` | `return!0` (always true) |
| **Admission Gate** | `FN() && (arg===void 0 \|\| FN2(arg))` | `return!0` (always accept) |

The function names are **minified and change with every build** (e.g. `v0/vx` in 2.1.156 → `XW/Fx` in 2.1.158), so the patcher matches by **code shape**, not by name — surviving the obfuscation churn across daily releases.

Both edits are **length-preserving** (padded with `/*ULTRACODE_PATCH---*/`), so no byte offsets shift. macOS re-signs ad-hoc because byte edits invalidate the hardened-runtime signature.

### Three-Stage Gate Detection

```
Stage 1: Structural regex ── matches by code shape (covers all known versions 2.1.113+)
    ↓ no match
Stage 2: Known byte patterns ─ exact patterns for registered versions (2.1.156, 2.1.158)
    ↓ no match
Stage 3: Semantic anchors ── reverse-locates gates via ultracode/available/defaultOn strings
    ↓ all failed
    Safe abort — binary untouched
```

## Daily Auto-Update

`auto-repatch.sh` provides fully automated version tracking:

1. Query npm registry for the latest Claude Code version
2. If newer → `npm i -g @anthropic-ai/claude-code@latest`
3. Run the three-stage adaptive patch
4. Create a `patch/<version>` git branch with patch metadata (timestamp, original SHA256)
5. Append to `~/.claude/backups/auto-repatch.log`

Sample log:
```
[2026-06-01 00:30:56] version=2.1.158 upgrade=none patch=ok branch=patch/2.1.158
```

## Files

| File | Purpose | Version support |
|---|---|---|
| `auto-repatch.sh` | Daily auto-upgrade + patch + per-version branch | Adaptive ✅ |
| `disable-autoupdate.sh` | All-in-one: disable auto-update + adaptive patch + re-sign | Adaptive ✅ |
| `repatch-ultracode.sh` | Three-stage adaptive patch (patch only) | Adaptive ✅ |
| `unlock-ultracode.sh` | Legacy all-in-one (disable update + patch + re-sign) | 2.1.156 only |
| `patch-ultracode.sh` | Legacy patch only | 2.1.156 only |
| `inline-command.sh` | Inline one-liner (no script file needed) | 2.1.156 only |

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
- Claude Code **2.1.113+** (Bun single-file binary)

## Caveats

- Modifies an Anthropic-distributed binary; signature becomes ad-hoc. Use at your own discretion.
- ultracode is "this session only" by design — not persisted to settings.
- With auto-update disabled, upgrade manually: `npm i -g @anthropic-ai/claude-code@latest`, then re-run the patch.

## Contributing

If the adaptive patcher fails on a new version, open an issue with the version number and the patcher output. The exact byte-pattern mapping will be updated.

## License

MIT License

---

<div align="center">

**Keywords:** Claude Code ultracode, effort level, xhigh, dynamic workflow orchestration,
Claude Code patch, unlock ultracode, force enable ultracode, Claude Code binary patch,
Bun binary patch, Claude Code mod, max effort level, Anthropic Claude Code

</div>
