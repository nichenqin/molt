# Remige launch kit

Status: **pre-launch**. Public builds are ad-hoc signed until the personal Apple Developer
Program enrollment is approved and Developer ID signing/notarization is enabled. Do not claim
“signed and notarized” before that.

## Positioning

**Tagline:** Every update on your Mac, in one place.

**One-liner:** Remige finds updates from Homebrew, npm, pnpm, Bun, Sparkle apps, the Mac App
Store, and curl-installed tools, then lets you read the release notes and update from one list.

**Short description (≈ 90 characters):** One native macOS app for every update: brew, npm, Bun,
DMG apps, App Store, and CLI tools.

**Long description:** Updaters are fragmented. `brew outdated` does not know about global npm
packages, `npm outdated -g` does not know about IINA, and Sparkle apps only know themselves.
Remige runs those native sources in parallel, deduplicates the results, caches a snapshot for
instant launch, and presents one ledger with one safe next step per row. The SwiftUI window and
menu-bar item share a core with a scriptable CLI. No account, no analytics, no daemon, and no
silent bundle replacement.

**Three bullets:**

- 8 update sources in one list: Homebrew, npm, pnpm, Bun, Sparkle, Electron manifests, Mac App
  Store, and curl tools.
- Read GitHub release notes or Sparkle appcast notes before clicking update.
- Native SwiftUI + CLI. No Electron runtime, no account, no background daemon.

**Links:** [Website](https://remige.app/) · [GitHub](https://github.com/nichenqin/remige) ·
[Press kit](https://remige.app/press/) · [Changelog](https://remige.app/changelog/)

## Product Hunt

**Name:** Remige

**Tagline:** Every macOS update in one place.

**Description:** Remige is a native macOS app and CLI for people who install software from more
than one place. It finds outdated Homebrew formulae and casks, global npm/pnpm/Bun packages,
Sparkle and Electron apps, Mac App Store apps, and curl-installed CLI tools. Read the release
notes, then update with one click or one command. Free, MIT, no account, no telemetry.

**Topics:** macOS, Developer Tools, Productivity, Open Source, Homebrew

**First comment:** I built Remige because checking `brew outdated`, `npm outdated -g`, appcast
feeds, and `mas` separately was a daily chore. It runs those sources in parallel and keeps one
cached list. The app and CLI share the same core; the CLI has stable JSON output. It is free and
open source. I would love feedback on which sources or upgrade paths are missing.

**Gallery order:** main window → release notes/detail → menu bar → CLI output → settings.

## Hacker News

**Title:** Show HN: Remige – every macOS update in one place

**Body:** Remige is a native SwiftUI app plus a CLI that aggregates Homebrew, npm, pnpm, Bun,
Sparkle appcasts, Electron Builder manifests, the Mac App Store, and curl-installed tools into
one update list. It reads release notes before upgrading, caches the last scan for instant
launch, and lets a failed source return partial results instead of blanking the list. No
account, no analytics, no daemon. The app and CLI share the same `RemigeCore`; JSON output and
upgrade plans are stable. Source: https://github.com/nichenqin/remige

## X / Bluesky

**English:** Every macOS update in one place. Remige finds brew, npm, pnpm, Bun, Sparkle,
App Store, and curl-tool updates, shows the release notes, and updates from one list. Native
SwiftUI + CLI, free and open source. https://remige.app

**中文：** 一个窗口，看全 Mac 上的所有更新。Remige 聚合 Homebrew、npm、pnpm、Bun、Sparkle、
App Store 和 curl 工具的更新，先看更新日志，再一键升级。原生 SwiftUI + CLI，免费开源。
https://remige.app

## 中文发布文案

**一句话：** 一个窗口，看全 Mac 上的所有更新。

**短描述：** Remige 是原生 macOS 应用与 CLI，聚合 brew、npm、pnpm、Bun、DMG 应用、App Store
和 curl 工具的更新；看更新日志，在一个列表里完成升级。免费、开源、无账号、无后台进程。

**三条卖点：**

- 8 个更新来源，一个列表：Homebrew、npm、pnpm、Bun、Sparkle、Electron manifest、Mac App
  Store、curl 工具。
- 升级前先看 GitHub Release Notes 或 Sparkle appcast 日志。
- 原生 SwiftUI + CLI，不是 Electron；无账号、无遥测、无常驻进程。

## Pre-launch checklist

- [x] Public site, changelog, privacy, security, support, and press pages
- [x] `SECURITY.md`, issue/PR templates, private vulnerability reporting
- [x] GitHub Discussions enabled
- [x] Repository homepage and social preview
- [ ] Personal Apple Developer Program identity verification approved
- [ ] Developer ID Application certificate and notarization credentials in GitHub Secrets
- [ ] Rebuild release; verify `spctl -a -vv` says `accepted / Notarized Developer ID`
- [ ] Replace “ad-hoc signed” wording in README, docs, FAQ, and security page
- [ ] Add a 20–30 second demo video to `/press/` and the README
- [ ] Product Hunt / Hacker News / social posts
- [ ] Watch GitHub Issues and Discussions for the first 48 hours

## Apple support message

Use after five business days without an enrollment email:

> My individual Apple Developer Program identity verification was submitted on 2026-10-19.
> The status page says my information was successfully submitted and is under review. I have
> not received any email yet. My Apple ID is `nichenqin@hotmail.com`. Could you check the status
> of my personal enrollment? I am also a member of the Teable AI, Inc. organization team
> (Team ID `6RGCFV3CTU`), but this enrollment is for my personal membership.
