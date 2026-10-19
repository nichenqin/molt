# Testing

## Run

```sh
swift test
```

The suite is deterministic: no live network, no real Homebrew/npm installs. Protocols are injected:

- `CommandRunning` / `StreamingCommandRunning` for processes;
- `HTTPGetting` for URLs;
- a temporary `DiskCache` directory per test.

Swift Testing is used (`@Test`, `#expect`, `#require`, `#expect(throws:)`), and tests run in parallel by
default.

## Coverage map

| Area | Tests |
| --- | --- |
| Version semantics | numeric ordering, prefixes, trailing zeros, revisions, prereleases, output extraction |
| Version policy | magnitude (major/minor/patch/unknown), 0.x major-line rules, prompt/allow/hold targets, batch eligibility, explicit pins, old-snapshot defaults |
| npm version catalog | abbreviated metadata parsing, prerelease filtering, ordering, cache reuse |
| Homebrew | JSON parsing, pinned formulae, cask detection, metadata/repo mapping, skip when absent |
| npm | global outdated JSON, exit code 1 with valid data, scoped package registry URL, upgrade argv |
| pnpm / Bun | tolerant dependency shapes, registry comparison |
| Mac App Store | `mas list/outdated` parsing |
| Sparkle | namespaced appcast fields, channels, minimum OS, delta vs full enclosure, duplicate versions |
| Apps | Sparkle precedence, Electron GitHub/generic manifests, ARM64 fallback, malformed/insecure metadata, config overrides, Magpie catalog, bundle identity vs display name, cask ownership, dedupe, coverage details for current/newer/unversioned and unavailable sources |
| Self-update | manifest parsing, newer/current versions, malformed feed, SHA-256 and size verification, atomic CLI replacement with mode restore, app ZIP extraction/version check, bundle swap/rollback helper |
| Changelogs | Atom parsing, HTML extraction, six-hour cache, request count |
| Config | missing file defaults, partial document, round-trip, invalid JSON |
| Cache | TTL, `readIgnoringAge`, HTTP ETag entry, snapshot round-trip |
| Merge | cask/Sparkle dedupe, custom-over-catalog precedence |
| Processes | stdout/stderr separation, nonzero exit, timeout termination, streaming events, launch error |
| CLI | long/short options, `--`, unknown option rejection, query resolution, grouping/table text |

The suite is deterministic (`swift test`).

## Fixtures and fakes

- `FakeHTTP` switches on URL or returns a fixed response and counts calls.
- `FakeRunner` records the `CommandSpec` and returns stdout/stderr/exit code.
- `temporaryDirectory()` isolates cache and config tests.
- Appcast and Atom fixtures live inline in the tests so their expected fields are visible next to
  assertions.

## Smoke tests

Build and run the real code:

```sh
make app
swift run -c release remige doctor --json
swift run -c release remige list --json
swift run -c release remige list --cached --json
swift run -c release remige upgrade <safe-package> --dry-run
```

Live one-click path (used during development; not in CI): a custom tool whose `--version` prints `0.0.1`,
whose latest-version URL serves `v2.0.0`, and whose `update` argument writes a marker file. `remige list`
reported it; `remige upgrade custom:faketool --yes` ran the argv array and exited 0; the marker existed.

## CI

`.github/workflows/ci.yml` builds in release mode, runs the full suite, packages the app, and runs
`doctor --json` on a macOS runner. The release workflow runs the tests again before publishing.

## What is intentionally not tested

- Private Homebrew taps and private npm registries.
- Sparkle installing a payload (Remige only opens downloads).
- `mas` upgrades (needs a signed-in App Store account and can mutate the machine).
- Exact visual output of SwiftUI; visual checks are done by launching the app.
