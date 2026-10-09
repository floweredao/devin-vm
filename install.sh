#!/bin/bash
# Link dvm and macrun into a bin directory on PATH (default ~/.local/bin) and check what they need.
# Usage: ./install.sh [--prefix DIR] [--force]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$HOME/.local/bin"
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,3s/^# //p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || echo "install.sh: warning: macrun uses macOS tools (lockf, tar --no-mac-metadata); dvm alone may work elsewhere" >&2

mkdir -p "$PREFIX"
for tool in dvm macrun; do
  target="$PREFIX/$tool"
  if [ -e "$target" ] && [ ! -L "$target" ] && [ "$FORCE" -ne 1 ]; then
    echo "skip   $target exists and is not a symlink (rerun with --force to replace it)"
    continue
  fi
  ln -sfn "$ROOT/bin/$tool" "$target"
  echo "linked $target -> $ROOT/bin/$tool"
done

missing=0
for cmd in devin jq curl rsync ssh git perl /usr/bin/python3; do
  if command -v "$cmd" >/dev/null 2>&1; then echo "ok     $cmd"
  else echo "MISSING $cmd"; missing=1
  fi
done
if ! command -v devin >/dev/null 2>&1; then
  echo "        install the Devin CLI: brew install --cask devin-cli  (or curl -fsSL https://cli.devin.ai/install.sh | bash)"
fi
case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo "note   $PREFIX is not on PATH; add: export PATH=\"$PREFIX:\$PATH\"" ;;
esac
echo
echo "Next: devin auth login && dvm doctor && dvm up --mode swe-2-medium"
exit "$missing"
