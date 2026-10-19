# Changelog

## Unreleased

- Detect Magpie updates through its bundle ID and official `yetone/magpie-releases` source, including
  installations without Sparkle metadata or a CLI on PATH. Show versions and GitHub release notes under
  Apps; unmanaged installations open the release page instead of replacing the running app.

## 0.2.0 — 2026-10-19

The distribution release.

- Website at `molt-site-five.vercel.app` with English and Chinese landing pages, docs, download and release notes.
- Universal DMG alongside the ZIP, with SHA-256 checksums.
- In-app self-update: checks the static feed, verifies SHA-256, swaps the app bundle with rollback, and relaunches.
- `molt update` / `molt update --check` for the CLI, including a Homebrew guard.
- Static update feed and Homebrew Formula/Cask generated from the release assets.
- Optional Developer ID signing, hardened runtime, notarisation and stapling in the release pipeline.
- 55 deterministic tests, including update feed, checksum, atomic CLI replacement, app-swap helpers and cataloged app detection.

## 0.1.0 — 2026-10-18

Initial release.

- Native SwiftUI window + menu bar extra and a shared CLI.
- Homebrew formulae and casks (`--greedy`), including pinned badges.
- Global npm, pnpm, and Bun packages.
- Sparkle appcast detection for DMG apps: channels, minimum OS, full-vs-delta enclosure handling, and
  Caskroom-aware one-click upgrades.
- Mac App Store updates when `mas` is installed.
- Standalone curl/installer tool catalog with self-update commands plus a custom-tool config.
- GitHub releases Atom changelogs and Sparkle release notes, cached for six hours.
- Atomic snapshot cache for instant launch; stale rows survive source failures.
- JSON/table CLI output, dry-run upgrades, streamed command output, doctor, cache, and config commands.
- 44 deterministic tests with fake process/HTTP transports.
