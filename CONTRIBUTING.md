# Contributing

Remige is a small Swift package. Keep it that way.

1. `swift test` must pass.
2. `swift-format lint --recursive Sources Tests` must be clean (config in `.swift-format`; use the
   `swift-format` bundled with Xcode).
3. New package-manager behavior belongs in a detector behind `CommandRunning` and `HTTPGetting`; add a
   fixture test, not a live-network test.
4. Never add a third-party runtime dependency without a strong reason; the current app has none.
5. Upgrade plans must remain argv arrays. No shell interpolation.
6. If you change an exported model, update the JSON schema section of the README and the snapshot cache
   schema if needed.

## Local app builds

For UI work, build and relaunch the working tree (uncommitted changes included) with:

```sh
remige-dev
```

It packages a debug app into `dist-dev/Remige.app` with a `-dev` version suffix, quits the running
Remige, and opens the new bundle. Release artifacts in `dist/` stay untouched. Without the global
command, the equivalent is `CONFIG=debug DIST=dist-dev VERSION=<VersionInfo.current>-dev make app`
then `open dist-dev/Remige.app` (quit Remige first).

## Adding a standalone tool

Add a `CLITool` to `ToolCatalog` with a GitHub repo or text latest source, version args, optional regex, and
a self-update argv if the tool genuinely supports one. Managed binaries are skipped by path, so brew/npm
installations will not duplicate.

## Adding a source

Implement `OutdatedSourceDetector`, add a `SourceKind` case if it is not covered by an existing one, wire it
into `Scanner.detectors`, and extend `Scanner.merge` if it can duplicate another source's install. Add the
source to settings localization and the README table.

## Website

The site in `site/` is Astro + Tailwind CSS with Astro i18n routing (`/` English, `/zh/` Chinese).
Build it before opening a PR that touches it:

```sh
npm --prefix site ci
npm --prefix site run build
```

The public changelog is generated from `CHANGELOG.md` at build time. Add release notes under
`## Unreleased`, and keep user-facing docs in both `site/src/pages/docs/` and
`site/src/pages/zh/docs/`.

## Release

```sh
VERSION=0.1.1 ARCHS=universal Scripts/package.sh
git tag v0.1.1
git push origin main v0.1.1
```

The release workflow builds and uploads the universal app, CLI, and checksums.
