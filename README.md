# claude-ultracode-patch

强制开启 Claude Code 的 **ultracode** 模式(xhigh 推理 + 常驻动态工作流编排)。
针对 Bun 编译的单文件二进制。

*Force-enable Claude Code's **ultracode** effort mode (xhigh + standing
dynamic-workflow orchestration) on the Bun-compiled binary.*

> **版本锁定:仅适用于 Claude Code `2.1.156`。**
> ultracode 在任何 Node(`cli.js`)版本里都不存在——它是从 Bun 单文件二进制时代
> (2.1.113+)才引入的。下面的字节特征是 2.1.156 专属的,脚本会拒绝在其他版本上运行。
>
> *Version-locked to `2.1.156`. ultracode exists only in the Bun single-file
> binary (2.1.113+), never in Node `cli.js` builds. The byte patterns are
> version-specific; the script refuses other versions.*

## 原理 / How it works

Claude Code 把 `/effort ultracode` 卡在内嵌 JS 的两个判定函数后面:

*Claude Code gates `/effort ultracode` behind two predicates in its embedded JS:*

| 函数 Function | 原含义 Original meaning | 改为 Patched to |
|---|---|---|
| `v0()` | 动态工作流是否开启?(GrowthBook `tengu_workflows_enabled` / `allow_workflows`) | `return!0`(恒真 always on) |
| `vx(H)` | ultracode 准入门:`v0() && (H===undefined \|\| VcH(H))`(VcH=xhigh 兼容模型) | `return!0`(恒真 always accept) |

两处改动都是**等长替换**(用 `/*ULTRACODE_PATCH*/` 注释补齐),不移动任何字节偏移。
macOS 上改完字节会使原 hardened-runtime 签名失效、被系统拦杀,所以脚本会自动做
ad-hoc 重签名(`codesign -f -s -`);Linux/ELF 无需签名,自动跳过。

脚本**幂等**(可重复运行)、**自适应主机**(自动定位二进制),并把原件备份到
`~/.claude/backups/claude.exe.2.1.156.orig`。

*Both edits are length-preserving (no offsets shift). macOS re-signs ad-hoc
because byte edits invalidate the hardened-runtime signature; Linux skips it.
The script is idempotent, host-adaptive, and backs up the original.*

## 安装 / Install

**🚀 傻瓜版一键(推荐)All-in-one (recommended):**

一个脚本搞定全部:自动定位 + 版本校验 + 备份 + **关闭自动更新**(防补丁被覆盖)+ 打补丁 + 重签名 + 验证。

*One script does everything: locate + version-check + backup + **disable auto-update** (so the patch isn't overwritten) + patch + re-sign + verify.*

```bash
curl -fsSL https://raw.githubusercontent.com/Shiyao-Huang/unlock-claude-ultracode/main/unlock-ultracode.sh | bash
```

或克隆后运行 / or clone and run:

```bash
git clone https://github.com/Shiyao-Huang/unlock-claude-ultracode.git
cd unlock-claude-ultracode
bash unlock-ultracode.sh
```

---

**仅打补丁(不关自动更新)Patch only:**

```bash
curl -fsSL https://raw.githubusercontent.com/Shiyao-Huang/unlock-claude-ultracode/main/patch-ultracode.sh | bash
```

**自动定位失败时,手动传入路径 Pass an explicit path if auto-detect fails:**

```bash
bash unlock-ultracode.sh /custom/path/to/claude.exe
```

> ⚠️ **为什么要关自动更新?** Claude Code 后台自动更新会用官方原版二进制覆盖
> 打过补丁的 `claude.exe`,导致 ultracode 消失。傻瓜版通过往
> `~/.claude/settings.json` 注入 `env.DISABLE_AUTOUPDATER=1` 根治。
> 日后升级:手动 `npm i -g @anthropic-ai/claude-code@latest`,升级后重跑脚本。
>
> *Auto-update overwrites the patched binary with the stock one, so ultracode
> vanishes. The all-in-one sets `DISABLE_AUTOUPDATER=1` to prevent this. To
> upgrade later, update manually and re-run the script.*

## 打补丁后 / After patching

1. **彻底退出并重启 `claude`** —— 当前进程仍在内存里持有旧二进制。
   *Fully quit and relaunch `claude` (the running process holds the old binary).*
2. 运行 `/effort ultracode`。 *Run `/effort ultracode`.*
3. 成功提示 Success looks like:
   `Set effort level to ultracode (this session only): xhigh + dynamic workflow orchestration`
   —— 而不是 `Ultracode needs dynamic workflows enabled` 报错。

## 升级后需重跑 / Re-run after every upgrade

Claude Code 每次升级都会覆盖二进制,补丁会丢失。升级后请**先确认版本仍是 2.1.156**
再重跑脚本。若版本号变了,字节特征可能已改变,需为新版本重新生成补丁(脚本检测到
版本不符会拒绝运行)。

*Each upgrade overwrites the binary and loses the patch. Re-confirm the version
is still 2.1.156, then re-run. If it bumped, regenerate the patch — the script
refuses on a version mismatch.*

## 回滚 / Rollback

```bash
BIN="$(readlink -f "$(command -v claude)" 2>/dev/null || echo "$(npm root -g)/@anthropic-ai/claude-code/bin/claude.exe")"
cp ~/.claude/backups/claude.exe.2.1.156.orig "$BIN"
[ "$(uname)" = "Darwin" ] && codesign -f -s - "$BIN"
```

## 依赖 / Requirements

- `python3`(字节补丁)、`node`(读版本号)、`npm`(路径兜底)
- macOS:`codesign`(随 Xcode CLT 提供)
- 已安装 Claude Code **2.1.156**

## 注意 / Caveats

- 本补丁会修改 Anthropic 分发的二进制,原签名被替换为 ad-hoc 签名,自行斟酌使用。
  *This modifies an Anthropic-distributed binary; the signature becomes ad-hoc.*
- ultracode 本身设计为「仅本会话生效」,不会写入持久化设置。
  *ultracode is "this session only" by design — not persisted to settings.*

## 文件 / Files

- `unlock-ultracode.sh` —— **🚀 傻瓜版一键**:关自动更新 + 打补丁 + 重签名,全自动
  *All-in-one: disable auto-update + patch + re-sign, fully automated.*
- `patch-ultracode.sh` —— 仅打补丁(自适应、幂等、带版本守卫与回滚说明)
  *Patch only.*
- `inline-command.sh` —— 免脚本文件的单条内联命令(适合临时机器)
  *Inline one-shot command, no script file needed.*
