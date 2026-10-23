#!/bin/bash
# Offline check of windows/SKILL.md against the scripts: a fake HOME, install.sh links, and a
# stub dvm, so nothing connects to a VM. Windows resolves ".." in a path by its text, so a link
# from the skill is checked the same way, as seen through a skills folder linked to windows/.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/dvm-windows.XXXXXX)"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }

# README: "For an agent running on Windows, link windows/ instead".
mkdir -p "$T/skills"
ln -s "$ROOT/windows" "$T/skills/devin-vm-windows"
missing="$(python3 -I - "$T/skills/devin-vm-windows" <<'EOF'
import os, re, sys
skill = sys.argv[1]
with open(os.path.join(skill, "SKILL.md")) as f:
  text = f.read()
for target in re.findall(r"\]\(([^)]+)\)", text):
  if re.match(r"[a-z]+:", target) or target.startswith("#"): continue
  path = os.path.normpath(os.path.join(skill, target.split("#")[0]))
  if not os.path.exists(path): print(target)
EOF
)"
[ -z "$missing" ]
check "relative links resolve from a skills folder linked to windows/ ($missing)" $?

# WSL home after README step 2: Ubuntu's ~/.profile puts ~/.local/bin on PATH, install.sh links.
H="$T/home"
mkdir -p "$H"
printf 'if [ -d "$HOME/.local/bin" ] ; then\n    PATH="$HOME/.local/bin:$PATH"\nfi\n' > "$H/.profile"
HOME="$H" "$ROOT/install.sh" >/dev/null 2>&1
cmd="$(sed -n 's/^ *wsl -e bash -lc "\(.*SKILL\.md.*\)"$/\1/p' "$ROOT/windows/SKILL.md" | head -1)"
[ -n "$cmd" ] && env -i HOME="$H" PATH=/usr/bin:/bin bash -lc "$cmd" 2>/dev/null | cmp -s - "$ROOT/SKILL.md"
check "the documented wsl command prints the full SKILL.md" $?

# macrun's default log and wake log on Linux are where the skill says.
if [ "$(uname -s)" = Linux ]; then
  mkdir -p "$T/bin" "$T/proj"
  printf 'x\n' > "$T/proj/a.swift"
  cat > "$T/bin/dvm" <<'EOF'
#!/bin/bash
case "$1" in
  current) echo stubsession0000000000 ;;
  wake) echo 'woke stubsession0000000000 (swe-2-medium)' ;;
esac
EOF
  chmod +x "$T/bin/dvm"
  run() { env -i HOME="$H" PATH=/usr/bin:/bin DVM="$T/bin/dvm" DVM_WAKE_AFTER=0 "$ROOT/bin/macrun" "$@" >/dev/null 2>&1; }
  run "$T/proj" true && run --wake-tick
  logs="$H/.local/state/mac-offload/logs/macrun"
  ls "$logs"/*-proj-*.log >/dev/null 2>&1 && grep -q 'session=stubsession0000000000 action=sent' "$logs/wake.log"
  check "macrun logs and wake.log go to ~/.local/state/mac-offload/logs/macrun/" $?
else
  echo "SKIP macrun Linux log path (not Linux)"
fi

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
