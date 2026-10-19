#!/bin/sh
# Remige installer. Installs the app and the CLI from the latest GitHub release.
set -eu

REPO="nichenqin/remige"
APP_NAME="Remige.app"
CLI_NAME="remige"
BASE="https://github.com/$REPO/releases/latest/download"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  osascript -e 'quit app "Remige"' >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME" 2>/dev/null || true
  rm -f "/usr/local/bin/$CLI_NAME" "$HOME/.local/bin/$CLI_NAME" 2>/dev/null || true
  say "Removed Remige.app and the remige CLI."
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || fail "Remige is macOS only."

say "Downloading the latest Remige release…"
curl -fsSL "$BASE/Remige-macos.zip" -o "$TMP/Remige-macos.zip" || fail "Could not download Remige."
curl -fsSL "$BASE/Remige-macos.zip.sha256" -o "$TMP/checksums" || fail "Could not download checksums."
curl -fsSL "$BASE/remige-cli" -o "$TMP/remige" || fail "Could not download the CLI."
chmod +x "$TMP/remige"

EXPECTED_CLI="$(grep ' remige-cli$' "$TMP/checksums" | awk '{print $1}')"
if [ -n "$EXPECTED_CLI" ]; then
  ACTUAL_CLI="$(shasum -a 256 "$TMP/remige" | awk '{print $1}')"
  [ "$EXPECTED_CLI" = "$ACTUAL_CLI" ] || fail "CLI checksum mismatch."
fi

EXPECTED="$(grep ' Remige-macos.zip$' "$TMP/checksums" | awk '{print $1}')"
if [ -n "$EXPECTED" ]; then
  ACTUAL="$(shasum -a 256 "$TMP/Remige-macos.zip" | awk '{print $1}')"
  [ "$EXPECTED" = "$ACTUAL" ] || fail "Checksum mismatch."
fi
osascript -e 'quit app "Remige"' >/dev/null 2>&1 || true


ditto -x -k "$TMP/Remige-macos.zip" "$TMP/extract"
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
  install -m 0755 "$TMP/remige" "/usr/local/bin/$CLI_NAME"
  CLI_PATH="/usr/local/bin/$CLI_NAME"
else
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$TMP/remige" "$HOME/.local/bin/$CLI_NAME"
  CLI_PATH="$HOME/.local/bin/$CLI_NAME"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) say "Note: add ~/.local/bin to PATH to use \`remige\` directly." ;;
  esac
fi

say "Installed $APP_PATH"
say "Installed $CLI_PATH"
say "Open Remige from Applications or run: remige"
