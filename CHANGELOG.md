# Changelog

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
