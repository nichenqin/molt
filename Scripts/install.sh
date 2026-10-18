#!/bin/sh
# Molt installer. Installs the app and the CLI from the latest GitHub release.
set -eu

REPO="nichenqin/molt"
APP_NAME="Molt.app"
CLI_NAME="molt"
BASE="https://github.com/$REPO/releases/latest/download"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME" 2>/dev/null || true
  rm -f "/usr/local/bin/$CLI_NAME" "$HOME/.local/bin/$CLI_NAME" 2>/dev/null || true
  say "Removed Molt.app and the molt CLI."
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || fail "Molt is macOS only."

say "Downloading the latest Molt release…"
curl -fsSL "$BASE/Molt-macos.zip" -o "$TMP/Molt-macos.zip" || fail "Could not download Molt."
curl -fsSL "$BASE/Molt-macos.zip.sha256" -o "$TMP/checksums" || fail "Could not download checksums."
curl -fsSL "$BASE/molt-cli" -o "$TMP/molt" || fail "Could not download the CLI."
chmod +x "$TMP/molt"

EXPECTED="$(grep ' Molt-macos.zip$' "$TMP/checksums" | awk '{print $1}')"
if [ -n "$EXPECTED" ]; then
  ACTUAL="$(shasum -a 256 "$TMP/Molt-macos.zip" | awk '{print $1}')"
  [ "$EXPECTED" = "$ACTUAL" ] || fail "Checksum mismatch."
fi

ditto -x -k "$TMP/Molt-macos.zip" "$TMP/extract"
[ -d "$TMP/extract/$APP_NAME" ] || fail "Archive did not contain $APP_NAME."
xattr -dr com.apple.quarantine "$TMP/extract/$APP_NAME" 2>/dev/null || true

if [ -w /Applications ]; then
  rm -rf "/Applications/$APP_NAME"
  ditto "$TMP/extract/$APP_NAME" "/Applications/$APP_NAME"
  APP_PATH="/Applications/$APP_NAME"
else
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$APP_NAME"
  ditto "$TMP/extract/$APP_NAME" "$HOME/Applications/$APP_NAME"
  APP_PATH="$HOME/Applications/$APP_NAME"
fi

if [ -w /usr/local/bin ]; then
  install -m 0755 "$TMP/molt" "/usr/local/bin/$CLI_NAME"
  CLI_PATH="/usr/local/bin/$CLI_NAME"
else
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$TMP/molt" "$HOME/.local/bin/$CLI_NAME"
  CLI_PATH="$HOME/.local/bin/$CLI_NAME"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) say "Note: add ~/.local/bin to PATH to use \`molt\` directly." ;;
  esac
fi

say "Installed $APP_PATH"
say "Installed $CLI_PATH"
say "Open Molt from Applications or run: molt"
