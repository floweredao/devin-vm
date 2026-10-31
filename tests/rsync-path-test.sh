#!/bin/bash
# Runs dvm push and dvm pull with the real rsync over an ssh stand-in that executes the remote
# command with sh in a scratch "VM home", the way the VM's login shell does. Remote paths with
# spaces must arrive as one path, and pull must still expand * on the VM.
# shellcheck disable=SC2016 # literal stub script
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp="${TMPDIR:-/tmp}"
T="$(mktemp -d "${tmp%/}/dvm-rsync.XXXXXX")"
trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
mkdir -p "$T/vm" "$T/local" "$T/bin"
cat > "$T/bin/fakessh" <<'EOF'
#!/bin/bash
# ssh [-o opt]... [-l user] [-T] HOST CMD... -> run CMD in $VM_HOME like the VM's login shell.
# rsync on Linux passes the remote user as "-l user host"; openrsync passes "user@host".
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-l|-p|-i|-F|-E) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
cd "$VM_HOME" && exec sh -c "$*"
EOF
chmod +x "$T/bin/fakessh"
export VM_HOME="$T/vm"
lib="$T/dvm-lib"
sed '$d' "$ROOT/bin/dvm" > "$lib"
pass=0 fail=0
check() { # NAME RC - a failure prints what rsync said, so CI explains itself
  if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1))
  else echo "FAIL $1"; sed 's/^/     | /' "$T/out" 2>/dev/null; fail=$((fail + 1))
  fi
}
dvmf() { # FUNCTION ARGS... with the transport replaced by fakessh
  bash -c 'source "$1"; shift
    session() { echo stubsession; }
    ssh_base() { printf "%s" "$FAKESSH"; }
    ssh_argv() { SSH_ARGV=("$FAKESSH"); }
    with_reconnect() { shift; "$@"; }
    "$@"' _ "$lib" "$@"
}
export FAKESSH="$T/bin/fakessh"
echo "rsync: $(rsync --version 2>&1 | head -1)"

mkdir -p "$T/local/My App/sub"
printf 'one\n' > "$T/local/My App/a.txt"; printf 'two\n' > "$T/local/My App/sub/b.log"
dvmf cmd_push "$T/local/My App" "work/macrun/My App-1a2b3c4d" > "$T/out" 2>&1
[ "$(cat "$T/vm/work/macrun/My App-1a2b3c4d/a.txt" 2>/dev/null)" = one ] && [ ! -e "$T/vm/work/macrun/My" ]
check "push copies into a remote folder whose name has a space" $?

dvmf cmd_push "$T/local/My App" > "$T/out" 2>&1
[ -f "$T/vm/work/My App/sub/b.log" ]
check "push uses work/<name> for a local folder whose name has a space" $?

dvmf cmd_pull "work/macrun/My App-1a2b3c4d/a.txt" "$T/pulled/" > "$T/out" 2>&1
[ "$(cat "$T/pulled/a.txt" 2>/dev/null)" = one ]
check "pull fetches a remote file whose path has a space" $?

dvmf cmd_pull "work/macrun/My App-1a2b3c4d/sub/*.log" "$T/globbed/" > "$T/out" 2>&1
[ -f "$T/globbed/b.log" ]
check "pull still expands * on the VM" $?

mkdir -p "$T/vm/plain"; printf 'p\n' > "$T/vm/plain/c.txt"
dvmf cmd_pull "plain/c.txt" "$T/plain/" > "$T/out" 2>&1
[ -f "$T/plain/c.txt" ]
check "pull of a plain path still works" $?

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
