<div align="center">

# Unlock Claude Code Ultracode Mode

**强制解锁 Claude Code `ultracode` 极致模式** — xhigh 推理 + 动态工作流编排

[English](./README.en.md) · 中文

[![GitHub release](https://img.shields.io/github/v/tag/Shiyao-Huang/unlock-claude-ultracode?label=version&color=brightgreen)](https://github.com/Shiyao-Huang/unlock-claude-ultracode)
[![Supported versions](https://img.shields.io/badge/claude%20code-2.1.113%2B-blue)](https://www.npmjs.com/package/@anthropic-ai/claude-code)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](https://github.com/Shiyao-Huang/unlock-claude-ultracode)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Auto-update](https://img.shields.io/badge/daily%20cron-auto%20repatch-orange)](./auto-repatch.sh)

一键解锁 Claude Code 被隐藏的 **ultracode** effort level（最高推理强度 + 常驻动态工作流编排）。<br>
版本自适应 — 自动适配 2.1.156、2.1.158 及后续每日构建版本，无需手动更新补丁。<br>
每日定时自动检查新版本并重打补丁，支持 macOS 和 Linux。

</div>

---

## ✨ 功能特性

- **🔓 一键解锁 ultracode** — `/effort ultracode` 不再报错，直接启用 xhigh + 动态工作流
- **🔄 版本自适应** — 三阶段门控定位（结构正则 → 已知版本 → 语义锚点），跨版本自动适配
- **⏰ 每日自动更新** — cron 定时检查 npm 最新版，自动升级 + 重打补丁 + 版本分支留痕
- **🛡️ 安全可逆** — 幂等、等长替换、自动备份、macOS 重签名，随时可回滚
- **🖥️ 跨平台** — macOS (M1/Intel) + Linux，自动定位二进制，无需手动传参

## 🚀 快速开始

**推荐：自适应一键安装（关自动更新 + 打补丁 + 重签名）**

```bash
git clone https://github.com/Shiyao-Huang/unlock-claude-ultracode.git
cd unlock-claude-ultracode
bash disable-autoupdate.sh
```

**仅打补丁（不动自动更新设置）**

```bash
bash repatch-ultracode.sh
```

**设置每日自动更新（每天凌晨 3 点自动检查新版本并补丁）**

```bash
# 添加到 crontab
(crontab -l 2>/dev/null | grep -v auto-repatch; echo "0 3 * * * /bin/bash $(pwd)/auto-repatch.sh --cron >> ~/.claude/backups/auto-repatch-stdout.log 2>&1") | crontab -
```

补丁后 **彻底退出并重启 claude**，然后运行：

```
/effort ultracode
```

成功提示：`Set effort level to ultracode (this session only): xhigh + dynamic workflow orchestration`

## 🔧 原理

Claude Code 在 Bun 编译的二进制内嵌 JS 中用两个门控函数限制了 ultracode：

| 门控 | 原始逻辑 | 补丁后 |
|---|---|---|
| **工作流闸** (Workflow Gate) | `let{available:A,defaultOn:B}=FN(); if(!A)return!1; return FN2()??B` | `return!0` (恒真) |
| **准入门** (Admission Gate) | `FN() && (arg===void 0 \|\| FN2(arg))` | `return!0` (恒真) |

两个函数名在每次构建时都会被 **minified 混淆**（如 `v0/vx` → `XW/Fx`），因此脚本不依赖函数名，而是按 **代码结构形状** 匹配——即使混淆名完全改变，只要逻辑结构不变就能自动适配。

两处改动均为 **等长替换**（用 `/*ULTRACODE_PATCH---*/` 注释补齐），不移动任何字节偏移。macOS 上编辑字节会使原 hardened-runtime 签名失效，脚本自动做 ad-hoc 重签名 (`codesign -f -s -`)。

### 三阶段门控定位

```
策略 1: 结构正则 ──── 按代码形状匹配（覆盖 2.1.113+ 所有已知版本）
    ↓ 失败
策略 2: 精确字节串 ─── 已注册版本 (2.1.156, 2.1.158) 的精确模式
    ↓ 失败
策略 3: 语义锚点 ──── 从 ultracode/available/defaultOn 反向定位
    ↓ 全部失败
    安全退出，不动二进制
```

## 📅 每日自动更新

`auto-repatch.sh` 实现全自动版本追踪：

1. 查询 npm registry 最新版本号
2. 若有新版本 → `npm i -g @anthropic-ai/claude-code@latest` 升级
3. 运行三阶段自适应补丁
4. 在 git 中创建 `patch/<版本号>` 分支，记录补丁元数据（时间、原始 SHA256）
5. 写入日志 `~/.claude/backups/auto-repatch.log`

日志示例：
```
[2026-06-01 00:30:56] version=2.1.158 upgrade=none patch=ok branch=patch/2.1.158
```

## 📁 文件说明

| 文件 | 功能 | 版本支持 |
|---|---|---|
| `auto-repatch.sh` | 每日自动升级 + 补丁 + 版本分支 | 自适应 ✅ |
| `disable-autoupdate.sh` | 一键：关自动更新 + 自适应补丁 + 重签名 | 自适应 ✅ |
| `repatch-ultracode.sh` | 三阶段自适应补丁（仅补丁） | 自适应 ✅ |
| `unlock-ultracode.sh` | 旧版一键（关更新 + 补丁 + 重签名） | 仅 2.1.156 |
| `patch-ultracode.sh` | 旧版仅补丁 | 仅 2.1.156 |
| `inline-command.sh` | 单条内联命令（免脚本文件） | 仅 2.1.156 |

## 🔄 回滚

```bash
BIN="$(readlink -f "$(command -v claude)" 2>/dev/null || echo "$(npm root -g)/@anthropic-ai/claude-code/bin/claude.exe")"
VER="$(node -e "console.log(require(require('path').join(require('path').dirname('$BIN'),'..','package.json')).version)")"
cp "$HOME/.claude/backups/claude.exe.$VER.orig" "$BIN"
[ "$(uname)" = "Darwin" ] && codesign -f -s - "$BIN"
```

## 📋 依赖

- `python3`（字节补丁）、`node`（读版本号）、`npm`（路径兜底）
- macOS: `codesign`（随 Xcode CLT 提供）
- Claude Code **2.1.113+**（Bun 单文件二进制）

## ⚠️ 注意

- 修改 Anthropic 分发二进制，原签名替换为 ad-hoc，自行斟酌使用
- ultracode 设计为「仅本会话生效」，不写入持久化设置
- 禁用自动更新后，需手动 `npm i -g @anthropic-ai/claude-code@latest` 升级，升级后重跑脚本

## 🤝 贡献

每个新 Claude Code 版本发布后，如果三阶段自适应补丁无法匹配，欢迎提交 issue 附带版本号，我会更新精确字节串映射。

## 📄 许可

MIT License

---

<div align="center">

**Keywords / 关键词:** Claude Code ultracode, effort level, xhigh, dynamic workflow orchestration,
Claude Code patch, unlock ultracode, force enable ultracode, Claude Code 二进制补丁,
ultracode 解锁, 最高推理强度, Claude Code mod, Bun binary patch

</div>
