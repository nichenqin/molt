---
layout: ../../../layouts/DocsLayout.astro
lang: zh
title: Remige 文档 — 安装、CLI、来源、更新
description: "Remige 文档：安装、CLI 参考、更新来源、自定义工具、自更新、安全与构建。"
heading: 文档
lede: 安装 Remige、使用 CLI、添加自己的工具，以及更新 Remige 本体。
---

## 安装

### DMG

下载 <a data-download="dmg" href="https://github.com/nichenqin/remige/releases/latest">Remige-macos.dmg</a>，拖入 Applications，打开即可。通用二进制支持 Apple Silicon 与 Intel，需要 macOS 14+。

### 一行命令

```sh
curl -fsSL https://remige.app/install.sh | sh
```

安装脚本会下载最新 App 和 CLI、校验 SHA-256、安装到 `/Applications`（或 `~/Applications`）与 `/usr/local/bin`（或 `~/.local/bin`），并移除 quarantine 属性。

### Homebrew

```sh
brew tap nichenqin/remige https://github.com/nichenqin/remige
brew install --cask remige-app
brew install remige
```

Homebrew 安装的版本用 `brew upgrade` 更新；Remige 检测到 CLI 由 Homebrew 管理时会提示，而不会自行覆盖。

<div class="notice"><strong>签名状态。</strong> Developer ID 签名和 Apple 公证已接入发布流水线，但需要 Apple Developer Program 账号，当前公开构建尚未启用。若 macOS 首次拦截，右键 → 打开，或执行 <code>xattr -dr com.apple.quarantine /Applications/Remige.app</code>。</div>

## CLI

```sh
remige                       # 扫描并列出
remige list --json           # 稳定 JSON
remige list --cached         # 上次快照，不联网
remige list --source npm     # homebrew npm pnpm bun app cli mas custom
remige upgrade --all --yes
remige upgrade cc-switch --dry-run
remige changelog iina --limit 3
remige open sqlite
remige update --check        # 检查 Remige 本体
remige update                # 原子替换 CLI
remige doctor --json
remige cache path|size|clear
remige config path|init|show|edit
```

`remige upgrade` 会先显示完整 argv。没有 `--yes` 时在 TTY 上询问一次，在脚本中拒绝执行。只提供下载页的应用不会被静默安装。

## 来源

| 来源 | 检测 | 升级 |
| --- | --- | --- |
| Homebrew | `brew outdated --json=v2 --greedy` | `brew upgrade` |
| npm 全局 | `npm outdated -g --json` | `npm install -g pkg@latest` |
| pnpm 全局 | `pnpm list -g` + registry | `pnpm add -g pkg@latest` |
| Bun 全局 | `~/.bun/install/global` + registry | `bun add -g pkg@latest` |
| Sparkle 应用 | `SUFeedURL` appcast | 打开完整下载页；cask 管理的应用由 Homebrew 负责 |
| 其他应用 | Electron Builder `app-update.yml`（GitHub 或 HTTPS manifest）或 bundle id 目录/配置 | 打开发布页或下载页 |
| Mac App Store | `mas outdated` | `mas upgrade` |
| 独立工具 | 目录 + 版本命令 + latest tag | 自更新，或发布页 |

<a id="custom"></a>
## 自定义工具

编辑 `~/.config/remige/config.json`，支持只写需要的字段：

```json
{
  "disabledSources": ["mas"],
  "customTools": [
    {
      "name": "mytool",
      "path": "/usr/local/bin/mytool",
      "versionArgs": ["--version"],
      "versionRegex": "mytool (\\d+\\.\\d+\\.\\d+)",
      "github": "acme/mytool",
      "upgradeArgs": ["mytool", "self-update"]
    }
  ]
}
```

`upgradeArgs` 的第一个元素会被检测到的可执行文件路径替换，其余原样传入。不写则打开发布页。

<a id="updates"></a>
## 更新 Remige 本体

Remige 检查静态 feed：`https://remige.app/latest.json`。有新版本时应用顶部会出现更新条；*Remige → 检查更新…* 打开更新面板。下载的 ZIP 会按 feed 中的 SHA-256 校验，然后由一个很小的 helper 等待 Remige 退出、带回滚地替换 App 包并重启。

CLI 使用同一个 feed：

```sh
remige update --check
remige update
```

Homebrew 用户应使用 `brew upgrade remige` 和 `brew upgrade --cask remige-app`。如果 App 运行在不可写目录（例如 quarantine translocation 路径），Remige 会拒绝替换。

<a id="security"></a>
## 安全与限制

- 无账号、无统计、无常驻进程、不注入 sudo。
- 升级计划是 argv 数组，包名不会被拼进 shell 字符串。
- 更新下载必须 HTTPS，并用 feed 中的 SHA-256 校验。
- 忽略 Sparkle delta 包，使用完整下载。
- 扫描时设置 `HOMEBREW_NO_AUTO_UPDATE=1`；想立刻拿最新 formula 元数据需自行 `brew update`。
- 应用更新来自 Sparkle feed、Electron Builder `app-update.yml`（GitHub 或 HTTPS manifest）或显式的 bundle id 目录/配置项；绝不按显示名称猜测。Magpie 使用 `com.yetone.magpie` 与 `yetone/magpie-releases`。没有可用更新源的应用会以“未检查”出现在应用来源详情中。

<a id="build"></a>
## 从源码构建

```sh
git clone https://github.com/nichenqin/remige.git
cd remige
swift test
make app
make install
```

需要 Swift 6 与 macOS 14+。App 和 CLI 共用 `RemigeCore`，无常驻进程，无第三方运行时依赖。
