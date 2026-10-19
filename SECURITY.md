# Security policy

## Supported versions

Remige is pre-1.0. Only the latest published release receives security fixes.

| Version | Supported |
| --- | --- |
| latest `v0.3.x` | yes |
| older releases | no |

## Reporting a vulnerability

Use GitHub's private vulnerability reporting:

<https://github.com/nichenqin/remige/security/advisories/new>

Do not open a public issue for a suspected vulnerability. Include:

- the affected component: app, CLI, installer, update feed, or release workflow;
- the version and macOS version;
- reproduction steps or a proof of concept;
- the impact you believe it has;
- any suggested fix.

You can expect an acknowledgement within three business days and a status update after the report is
triaged. This is a small project; fixes are best effort. There is no bug bounty.

## Scope

In scope:

- `Remige.app`, the `remige` CLI, and `Scripts/install.sh`;
- the update manifest at `https://remige.app/latest.json` and the app/CLI update path;
- the release workflow and published release assets.

Out of scope:

- vulnerabilities in Homebrew, npm, pnpm, Bun, the Mac App Store, Sparkle appcasts, or third-party apps
  that Remige only detects or invokes;
- social engineering and physical access;
- issues that require an already-compromised local account or a modified system.

## Update integrity

The app and CLI read `https://remige.app/latest.json`, require HTTPS, verify the download's SHA-256 and
size, validate the app bundle version, and stage the replacement with rollback. Release assets are served
by GitHub and the feed by Vercel.

Builds are currently **ad-hoc signed**; Developer ID signing and Apple notarization are not enabled yet.
Until they are, Gatekeeper cannot vouch for the download, and the update path is only as strong as the
GitHub and Vercel origins. Report suspected feed or asset tampering immediately.
