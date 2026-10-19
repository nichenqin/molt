---
name: remige-dev
description: Rebuild Remige from the current working tree and relaunch it as the running app. Use after finishing any user-visible change in the Remige repo (Sources/RemigeApp, Sources/RemigeCore, Resources), or whenever the user asks to open the latest dev version / 打开最新开发版.
---

# Remige dev build

Global command: `remige-dev` (`~/.local/bin/remige-dev`).

After a change is implemented and the tests/lint for it pass, run:

```sh
remige-dev
```

## What it does

1. Builds the **current working tree** of `~/projects/remige` (uncommitted changes included), `CONFIG=debug`.
2. Packages into `dist-dev/Remige.app` with version `<VersionInfo.current>-dev` (for example `0.3.1-dev`).
3. Quits any running `Remige` process (release or previous dev build), waits for exit, then `open`s the new bundle.
4. Prints `Remige <version> (<sha>[-dirty]) is running from <path>`.

`dist/` (release artifacts, DMG/zip) is never touched.

## Verification

```sh
pgrep -fl Remige
defaults read ~/projects/remige/dist-dev/Remige.app/Contents/Info.plist CFBundleShortVersionString
```

The process path must be `dist-dev/Remige.app/Contents/MacOS/Remige`; the version must end in `-dev`.

## Rules

- Run it only after the change is verified; it restarts the user's app, so do not run it mid-edit or between unrelated steps.
- If the user-visible behavior does not match, fix and run `remige-dev` again instead of asking the user to rebuild.
- Docs-only, test-only, or CLI-only changes do not need a relaunch; `swift run -c release remige …` is enough for CLI checks.
- Env overrides: `REMIGE_REPO`, `REMIGE_DEV_DIST`, `REMIGE_DEV_CONFIG`, `REMIGE_DEV_VERSION`.
- If `remige-dev` is missing from `PATH`, `~/.local/bin` is not exported; invoke it by absolute path.
