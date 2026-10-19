---
layout: ../../layouts/DocsLayout.astro
lang: en
title: Remige Docs — Install, CLI, sources, updates
description: "Remige documentation: install, CLI reference, update sources, custom tools, self-update, security and build instructions."
heading: Documentation
lede: Install Remige, run the CLI, add your own tools, and keep it updated.
---

## Install

### DMG

Download <a data-download="dmg" href="https://github.com/nichenqin/remige/releases/latest">Remige-macos.dmg</a>, drag Remige into Applications, then open it. The DMG is universal (Apple Silicon and Intel) and requires macOS 14+.

### One-line installer

```sh
curl -fsSL https://remige.app/install.sh | sh
```

The installer downloads the latest app and CLI, verifies SHA-256, installs the app to `/Applications` (or `~/Applications`) and the CLI to `/usr/local/bin` (or `~/.local/bin`), and removes the quarantine flag.

### Homebrew

```sh
brew tap nichenqin/remige https://github.com/nichenqin/remige
brew install --cask remige-app
brew install remige
```

Homebrew installations should be updated with `brew upgrade`; Remige detects a Homebrew-managed CLI and says so instead of replacing it.

<div class="notice"><strong>Signing status.</strong> Developer ID signing and Apple notarization are wired into the release workflow. They require an Apple Developer Program membership and are not yet enabled for the public build. If macOS blocks the first launch, right-click → Open, or run <code>xattr -dr com.apple.quarantine /Applications/Remige.app</code>. Current status and the update-integrity model are on the <a href="/security/">security page</a>.</div>

## CLI

```sh
remige                       # scan and list
remige list --json           # stable machine-readable snapshot
remige list --cached         # last snapshot, no network
remige list --source npm     # homebrew npm pnpm bun app cli mas custom
remige upgrade --all --yes
remige upgrade cc-switch --dry-run
remige changelog iina --limit 3
remige open sqlite
remige update --check        # check Remige itself
remige update                # replace the CLI atomically
remige doctor --json
remige cache path|size|clear
remige config path|init|show|edit
```

`remige upgrade` prints the exact argv it will run. Without `--yes` it asks once on a TTY and refuses in scripts. Download-only apps open their release page; Remige does not install them silently.

## Sources

| Source | Detection | Upgrade |
| --- | --- | --- |
| Homebrew | `brew outdated --json=v2 --greedy` | `brew upgrade` |
| npm global | `npm outdated -g --json` | `npm install -g pkg@latest` |
| pnpm global | `pnpm list -g` + registry | `pnpm add -g pkg@latest` |
| Bun global | `~/.bun/install/global` + registry | `bun add -g pkg@latest` |
| Sparkle apps | `SUFeedURL` appcasts | opens the full download; cask-managed apps stay with Homebrew |
| Other apps | Electron Builder `app-update.yml` (GitHub or HTTPS manifest) or bundle-ID catalog/config | opens the release or download page |
| Mac App Store | `mas outdated` | `mas upgrade` |
| Standalone tools | catalog + version command + latest tag | self-update, or release page |

<a id="custom"></a>
## Custom tools

Edit `~/.config/remige/config.json`. Partial documents are accepted:

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

In `upgradeArgs`, the first element is replaced by the detected executable path and the rest is passed through. Omit it to make the row open the release page.

<a id="updates"></a>
## Updating Remige

Remige checks the static feed at `https://remige.app/latest.json`. When a newer version exists, the app shows an update banner; *Remige → Check for Updates…* opens the update sheet. The downloaded ZIP is verified against the feed's SHA-256, then a tiny helper waits for Remige to quit, swaps the app bundle with rollback, and relaunches it.

The CLI uses the same feed:

```sh
remige update --check
remige update
```

Homebrew users should run `brew upgrade remige` for the CLI and `brew upgrade --cask remige-app` for the app. The app also detects when it is running from a directory it cannot write to (for example a translocated quarantine path) and refuses to attempt a swap.

<a id="security"></a>
## Security and limitations

- No account, no analytics, no daemon, no sudo injection.
- Upgrade plans are argv arrays; package names are never interpolated into a shell string.
- Update downloads must be HTTPS and are checked against a SHA-256 from the feed.
- Sparkle delta payloads are ignored; the full download is used.
- Homebrew metadata is not auto-updated during a scan (`HOMEBREW_NO_AUTO_UPDATE=1`); run `brew update` if you want the latest formula metadata immediately.
- Apps are checked from Sparkle feeds, Electron Builder `app-update.yml` (GitHub or HTTPS manifests), or explicit bundle-ID catalog/config entries; display names are never guessed. Magpie uses `com.yetone.magpie` and `yetone/magpie-releases`. Apps without a usable source appear as unchecked in the Apps source details.

<a id="build"></a>
## Build from source

```sh
git clone https://github.com/nichenqin/remige.git
cd remige
swift test
make app
make install
```

Requires Swift 6 and macOS 14+. The app and CLI share `RemigeCore`; there is no daemon and no third-party runtime dependency.
