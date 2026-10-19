# Architecture

## Shape

Molt is one Swift package with four targets:

| Target | Role | AppKit? |
| --- | --- | --- |
| `MoltCore` | models, detectors, cache, changelogs, upgrades | no |
| `MoltCLIKit` | argument parsing, table/JSON output, commands | no |
| `molt` | 12-line executable shim | no |
| `MoltApp` | SwiftUI window, menu bar extra, settings | yes |

Both surfaces share the same `Scanner`, `ChangelogService`, and `UpgradeService`. The CLI is not a wrapper
around a bundled binary, and the app does not shell out to `molt`; they call the same async APIs in-process.
That keeps behavior identical and makes every code path testable without a UI.

The design follows magpie's most useful architectural choices: a single distributable, a CLI that exposes
the full capability set, JSON as a first-class output, local-first state, and a thin presentation layer.
Molt differs where a native utility benefits: SwiftUI/AppKit instead of a WebView, and no daemon.

## Data flow

```
CommandRunning / HTTPGetting (protocols)
        │
        ├── HomebrewDetector ── brew outdated + formulae.brew.sh metadata
        ├── NpmGlobalDetector ─ npm outdated + registry metadata
        ├── PnpmGlobalDetector ─ pnpm list + registry
        ├── BunGlobalDetector ─ global package.json + registry
        ├── AppUpdateDetector ─ Info.plist + Sparkle appcasts or cataloged GitHub releases
        ├── MacAppStoreDetector ─ mas list/outdated
        ├── CLIToolDetector ─── catalog + --version + latest tag
        └── CustomToolDetector ─ config + same machinery
                    │
              DetectorOutput
                    │
     per-source timeout / partial failure
                    │
              merge + dedupe
                    │
             ScanSnapshot ──► DiskCache (atomic JSON)
                    │
          ┌─────────┴──────────┐
       SwiftUI                CLI
          │                    │
   ChangelogService      JSON / table
          │
   GitHub Atom / appcast
```

## Invariants

1. **A source failure never erases the others.** Detectors run concurrently. Each result is wrapped with
   its own duration, message, and state. If a detector throws, the scanner carries that source's rows from
   the previous snapshot and marks the report `stale`.
2. **Plans are argv arrays, never shell strings.** `UpgradePlan.command(executable, arguments)` is executed
   with `Process`, not `/bin/sh -c`. Package names and versions cannot inject shell syntax.
3. **Only explicit sources can be mutated.** Detectors produce commands for the manager that owns the
   package. Third-party apps that are not cask-managed get an `openURL` plan; the scanner never replaces them.
4. **Everything network-bound is cached and bounded.** Appcasts 15 min, latest tags and release notes 6 h,
   Homebrew metadata 7 days. Every source has a deadline. URLSession uses HTTP/2 and at most six
   connections per host; detector fan-out is capped by `Concurrency.map`.
5. **Stable IDs.** `brew:formula:<name>`, `brew:cask:<name>`, `npm:<pkg>`, `bun:<pkg>`, `app:<bundle-id>`,
   `cli:<name>`, `mas:<id>`, `custom:<name>`. IDs survive scans, so selection and upgrade logs remain valid.
6. **One row per install.** App rows for a cask-managed app are merged into the Homebrew cask row (the
   cask row keeps the app icon and one-click plan). Custom tools win over a catalog entry for the same
   executable path.
7. **The cache is disposable.** Every file is JSON with a timestamp and is written atomically. Deleting the
   cache only costs one fresh scan.

## Detector contract

```swift
public protocol OutdatedSourceDetector: Sendable {
    var source: SourceKind { get }
    func scan(_ context: ScanContext) async throws -> DetectorOutput
}
```

`DetectorOutput` can signal `skipped` (manager not installed) separately from an empty successful scan.
`ScanContext` carries injected `CommandRunning`, `HTTPGetting`, an actor-isolated `DiskCache`, the resolved
`EnvironmentInfo`, user config, and whether this is a forced refresh.

`EnvironmentInfo` composes the PATH a login shell would have without sourcing startup files (important for
GUI launches), finds absolute paths for brew/npm/pnpm/bun/mas, and indexes Caskroom to map a cask token to
the `.app` it installed. That index is built by directory walking, not a subprocess.

## Versioning

`Version` is deliberately pragmatic:

- leading `v`, build metadata `+abc`, and Sparkle/cask `,build` suffixes are ignored for comparison;
- numeric components compare numerically (`1.10 > 1.9`, `2026.10 > 2026.9`);
- `_revision` is a numeric component (`1.2.3_1 > 1.2.3`);
- prereleases sort before their release (`1.0.0-beta < 1.0.0`);
- trailing zero components are equal (`1.0 == 1.0.0`).

No package manager's "is outdated" decision is second-guessed: brew and npm are authoritative. `Version` is
used where Molt must decide (appcasts, cataloged app releases, standalone tools, pnpm/Bun registry comparison).

## Application updates

The app scanner reads `CFBundleShortVersionString`, `CFBundleVersion`, `SUFeedURL`, and `SUUpdateChannel`
from each app's `Info.plist`. Appcasts are parsed with `XMLParser`:

- namespace prefixes are retained by Foundation and normalized by the parser;
- items on a channel are ignored unless the app opts into that exact channel;
- `sparkle:minimumSystemVersion` is enforced against the host OS;
- delta enclosures (`sparkle:deltaFrom` or `.delta`) are dropped; the full enclosure is the download link;
- duplicate versions are collapsed, preferring the item with notes and a full enclosure.

Sparkle's own EdDSA signatures are not verified because Molt does not install the payload; it opens the
full download or hands the cask to Homebrew.

Apps without a Sparkle feed can have an explicit bundle-ID-to-repository entry in `AppUpdateDetector`.
Magpie (`com.yetone.magpie`) uses `yetone/magpie-releases`, its official updater's release repository.
The detector reads the installed version from the bundle, compares the latest tag using the shared
`LatestTagResolver`, and attaches GitHub release notes. This works without a CLI on PATH and does not
execute the app. Sparkle takes precedence when a feed exists; unknown apps are not inferred by name.
Cask-managed apps retain their brew upgrade plan; other cataloged apps open the release page.
Sparkle feeds and cataloged releases are checked concurrently, with per-source failures reported
without hiding successful checks. Tests inject application directories to exercise real plist discovery.

## Changelogs

GitHub releases are read from `https://github.com/<owner>/<repo>/releases.atom` rather than the REST API.
That avoids token management and the 60-request hourly unauthenticated API limit, and embeds release-note
HTML in each entry. The app renders notes as text (the AppKit HTML importer retained hundreds of MB across
several releases); the full formatted page is one click away. Sparkle notes come from the appcast's
`description` CDATA or `releaseNotesLink`.

## Upgrade runner

`StreamingProcessRunner` uses `Process` with stdout/stderr pipes and `readabilityHandler`s, while retaining
the full transcript for result reporting. A timeout task terminates then SIGKILLs. Cancellation terminates
the child. The app displays the live stream in a sheet; the CLI prints it or collects it under `--json`.
After a successful batch, the app rescans; the CLI does not, so scripts can decide when to refresh.

## Performance choices

- Snapshot first, network second in the app.
- One `brew outdated` call, one `npm outdated` call; metadata and registry calls are parallel.
- `formulae.brew.sh` metadata is cached for a week; latest GitHub tags come from the lightweight
  `/releases/latest` redirect, not the API.
- App icons are downsampled once to 128 pt and cached with `NSCache`.
- No background polling or login agent unless the user enables "Open at login".
- Universal app bundle ≈7.4 MB, zip ≈2.8 MB, DMG ≈3.2 MB, CLI ≈4.4 MB; warm scan ≈0.8–1.3 s, cold/network-bound scans up to ~5 s.

## Distribution and self-update

The website is a static GitHub Pages deployment of `site/`; there is no server component. A release writes
`site/latest.json` with the version, release notes, and SHA-256/size for the ZIP, DMG and CLI. Both the app
and CLI read that one manifest.

- The app checks at launch (throttled to 24 h) and from **Check for Updates…**. A downloaded ZIP is verified
  against the manifest, extracted with `ditto`, version-checked against `CFBundleShortVersionString`, staged
  next to the current bundle, and swapped by a detached `/bin/sh` helper only after Molt exits. The old
  bundle is kept as a rollback until the move succeeds.
- `molt update` downloads `molt-cli`, verifies SHA-256 and size, writes a temp file in the target directory,
  atomically replaces the executable and restores mode `0755`. A binary owned by Homebrew is refused with a
  `brew upgrade` hint.
- `Scripts/package.sh` optionally signs with Developer ID + hardened runtime, builds and signs a DMG,
  submits it to `notarytool`, staples the ticket to DMG and app, and runs `spctl`. Without credentials it
  falls back to ad-hoc signing and says so.
- `Formula/molt.rb` and `Casks/molt-app.rb` live in this repo, so the repository itself is the Homebrew tap;
  the release workflow regenerates them from the published asset hashes.

The update channel is HTTPS + SHA-256, not EdDSA-signed. HTTPS protects transport and the hash protects
against a corrupted or substituted asset; adding a signed manifest is a future hardening step, not a
requirement for the current ad-hoc distribution.

## Tradeoffs

- **Native Swift vs Go/WebView.** Native gives the smallest artifact and the fastest launch, at the cost of
  reimplementing a UI for macOS only. This tool is macOS-only by definition.
- **Curated standalone catalog vs scanning every binary.** Querying unknown binaries for a GitHub repo is
  guesswork. The catalog covers common curl tools; `customTools` is the explicit escape hatch.
- **Download-only for unmanaged apps.** Replacing an app bundle from arbitrary appcast payloads would
  require signature verification and a privileged installer. Handing the full download to the user is
  boring and safe.
- **Text release notes.** Less pretty than rendered HTML, drastically lighter.
