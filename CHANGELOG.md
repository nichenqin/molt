# Changelog

## Unreleased

- Menu bar popup rows, the refresh button and footer actions now show hover feedback; disabled
  actions stay flat.

## 0.3.0 — 2026-10-19

- Renamed the product from Molt to Remige after brand collisions with existing products. The app, CLI,
  bundle identifier (`com.nichenqin.remige`), config/cache paths, website and Homebrew tap all use the
  new name.

- Detect Magpie updates through its bundle ID and official `yetone/magpie-releases` source, including
  installations without Sparkle metadata or a CLI on PATH. Show versions and GitHub release notes under
  Apps; unmanaged installations open the release page instead of replacing the running app.
- Detect app updates from standard Electron Builder `app-update.yml` metadata (GitHub releases and
  HTTPS generic manifests, including Apple Silicon variants), with `appUpdates` config overrides and a
  separate bundle-id catalog. Unsupported apps are listed as unchecked in source details instead of
  being guessed or silently dropped; cask-managed apps stay owned by Homebrew.
- Expand the verified app catalog beyond Magpie to common macOS apps with official GitHub releases:
  Clash Verge, v2rayN, Zed, Obsidian, Rectangle, Stats, Maccy, AltTab, UTM, Keka, LocalSend, Transmission,
  Hammerspoon, BetterDisplay, and drawio. Entries require a stable bundle identifier, an official release
  page, and a matching version sequence.
- Close the menu bar panel when "Open Remige" or "Update All" opens the main window, instead of
  leaving the panel covering the window it just opened.

## 0.2.0 — 2026-10-19

The distribution release.

- Website at `remige.vercel.app` with English and Chinese landing pages, docs, download and release notes.
- Universal DMG alongside the ZIP, with SHA-256 checksums.
- In-app self-update: checks the static feed, verifies SHA-256, swaps the app bundle with rollback, and relaunches.
- `remige update` / `remige update --check` for the CLI, including a Homebrew guard.
- Static update feed and Homebrew Formula/Cask generated from the release assets.
- Optional Developer ID signing, hardened runtime, notarisation and stapling in the release pipeline.
- 67 deterministic tests, including update feed, checksum, atomic CLI replacement, app-swap helpers and cataloged app detection.

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
