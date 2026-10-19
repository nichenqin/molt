# Distribution and release

Remige is distributed as a universal macOS app plus a universal CLI. The app has a built-in updater; the CLI
has `remige update`; both read the same static feed.

## Public URLs

| Thing | URL |
| --- | --- |
| Website | https://remige.app/ |
| Update feed | https://remige.app/latest.json |
| Installer | https://remige.app/install.sh |
| Releases | https://github.com/nichenqin/remige/releases |
| Homebrew tap | `brew tap nichenqin/remige https://github.com/nichenqin/remige` |

The website is the static `site/` directory, connected to the Vercel project `remige` for automatic
deployment from `main`. The release workflow writes `site/latest.json`, `Formula/remige.rb`, and
`Casks/remige-app.rb` and commits them to `main`; Vercel redeploys the site from that push. There is no server
and no database.

## Accounts and money

### Required for a Gatekeeper-clean public release

**Apple Developer Program — $99/year** (individual or organization).

1. Enroll at https://developer.apple.com/programs/.
2. Create a **Developer ID Application** certificate in Certificates, Identifiers & Profiles.
3. Export the certificate and private key as a `.p12` with a password.
4. Create an App Store Connect API key (Users and Access → Integrations → App Store Connect API) with the
   **Developer** role, or use an Apple ID with an app-specific password.

Without this, Remige can still ship, but the app is **ad-hoc signed** and macOS may say it cannot verify the
developer. The install script clears the quarantine bit for the downloaded app, but Gatekeeper behavior on
first launch still depends on the user's settings.

### Optional

- **Custom domain** — about $10–20/year. The site is fully usable on `remige.app`. A domain
  such as `remige.nichenqin.com` only requires changing `RemigeLinks.website` / `configuredFeed`, the site
  canonical/OG URLs, and adding the domain in Vercel; Vercel is free.
- **CDN or worker** — optional; the static Vercel deployment is enough for downloads and the update feed.
- **Apple notarization** is included in the Developer Program; no separate fee.
- **GitHub Actions** — public repositories get free minutes; no payment needed for this workload.

### Not required

- No server, database, analytics, or login service.
- No paid Homebrew account. The tap lives in the main public repo.

## GitHub secrets

Set these in **Settings → Secrets and variables → Actions**:

| Secret | Purpose |
| --- | --- |
| `MAC_CERTIFICATE_P12` | base64 of the Developer ID Application `.p12` |
| `MAC_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `APPLE_API_KEY_P8` | contents of the App Store Connect API `.p8` key |
| `APPLE_API_KEY_ID` | API key ID |
| `APPLE_API_ISSUER` | issuer UUID |
| `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` | alternative to the API key |
| `NOTARY_PROFILE` | optional local keychain profile name |

If `MAC_CERTIFICATE_P12` is absent, the release workflow builds ad-hoc signed and prints a warning. If the
certificate exists but notarization credentials are absent, the app is signed but not notarized; the package
script prints that warning too.

Base64 the certificate:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Local signed build:

```sh
security find-identity -v -p codesigning
CODESIGN_ID="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="remige-notary" \
  VERSION=0.2.0 ARCHS=universal Scripts/package.sh
```

Create the local notary profile once:

```sh
xcrun notarytool store-credentials "remige-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

The package script:

1. builds arm64 + x86_64 and lipos them;
2. signs the app with hardened runtime;
3. builds `Remige-macos.dmg` with an Applications symlink;
4. signs the DMG;
5. submits the DMG to `notarytool --wait`;
6. staples both the DMG and the app;
7. runs `spctl` on both;
8. writes `Remige-macos.zip`, `remige-cli`, and `Remige-macos.zip.sha256`.

## Release checklist

```sh
# 1. bump RemigeVersion.current and Resources/Info.plist
# 2. update CHANGELOG.md
swift test
make lint
ARCHS=universal VERSION=0.2.1 Scripts/package.sh
swift Scripts/make-feed.swift 0.2.1 dist site
Scripts/update-homebrew.sh 0.2.1 dist
git add -A && git commit -m "release: 0.2.1"
git tag -a v0.2.1 -m "Remige 0.2.1"
git push origin main v0.2.1
```

The tag-triggered workflow rebuilds, signs/notarizes when secrets exist, publishes the release, regenerates
the feed and Homebrew files on `main`, and the Pages workflow redeploys the site.

## Verifying a release

```sh
codesign -dv --verbose=4 /Applications/Remige.app
spctl -a -vv /Applications/Remige.app
shasum -a 256 Remige-macos.zip Remige-macos.dmg remige-cli
curl -fsSL https://remige.app/latest.json
remige update --check
```

`spctl` should print `accepted` and `source=Notarized Developer ID` once the Apple credentials are enabled.

## Updater mechanics

`site/latest.json` is the only update source:

```json
{
  "schema": 1,
  "version": "0.2.0",
  "published": "2026-10-19T00:00:00Z",
  "notes": "## 0.2.0 ...",
  "pageURL": "https://github.com/nichenqin/remige/releases/tag/v0.2.0",
  "assets": {
    "Remige-macos.zip": { "url": "...", "sha256": "...", "size": 2777376 }
  }
}
```

The updater requires HTTPS, verifies SHA-256 and size, validates the app bundle's version, stages the new
bundle next to the old one, runs a small `/bin/sh` helper after the app exits, and rolls back if the move
fails. `remige update` atomically replaces the CLI and refuses to overwrite a Homebrew-owned binary.

If you add a custom domain, update `RemigeLinks.website`, `RemigeLinks.feed`, `RemigeLinks.installScript`, the
installer one-liners in both READMEs and site pages, canonical/OG URLs, `sitemap.xml`, and `robots.txt`.
