#!/bin/bash
# Link dvm and macrun into a bin directory on PATH (default ~/.local/bin) and check what they need.
# Works on macOS and on Linux, including WSL on Windows. Usage: ./install.sh [--prefix DIR] [--force]
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

wsl=0
case "$(uname -s)" in
  Darwin)
    needs=(devin jq curl rsync ssh git perl /usr/bin/python3)
    hint="brew install jq rsync  (git, perl and /usr/bin/python3 come with: xcode-select --install)" ;;
  Linux)
    needs=(devin jq curl rsync ssh git perl python3 script flock)
    hint="sudo apt install jq curl rsync openssh-client git perl python3 util-linux"
    grep -qi microsoft /proc/version 2>/dev/null && wsl=1 ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "install.sh: Git Bash/MSYS/Cygwin is not supported: dvm needs OpenSSH connection sharing" >&2
    echo "            (ControlMaster), which Windows OpenSSH lacks. Install WSL (wsl --install) and" >&2
    echo "            run this script inside the Ubuntu shell; see README, Windows (WSL)." >&2
    exit 1 ;;
  *) echo "install.sh: warning: untested system $(uname -s); continuing as on Linux" >&2
    needs=(devin jq curl rsync ssh git perl python3 script flock); hint="" ;;
esac
case "$ROOT" in
  /mnt/[a-z]/*) [ "$wsl" -eq 1 ] && echo "note   this clone is on a Windows drive ($ROOT); a clone in the WSL home (~) is faster and keeps file modes" ;;
esac

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
for cmd in "${needs[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then echo "ok     $cmd"
  else echo "MISSING $cmd"; missing=1
  fi
done
if [ "$missing" -ne 0 ] && [ -n "$hint" ]; then echo "        $hint"; fi
if ! command -v devin >/dev/null 2>&1; then
  if [ "$(uname -s)" = Darwin ]; then
    echo "        install the Devin CLI: brew install --cask devin-cli  (or curl -fsSL https://cli.devin.ai/install.sh | bash)"
  else
    echo "        install the Devin CLI: curl -fsSL https://cli.devin.ai/install.sh | bash"
  fi
fi
case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo "note   $PREFIX is not on PATH; add: export PATH=\"$PREFIX:\$PATH\"" ;;
esac
echo
echo "Next: devin auth login && dvm doctor && dvm up --mode swe-2-medium"
exit "$missing"
