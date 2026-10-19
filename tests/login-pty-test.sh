#!/bin/bash
# Offline check that dvm gives `devin ssh` a pseudo-terminal for its login when dvm runs without
# one (agent shells, launchd, WSL). devin and curl are stubs; the stub devin records whether it
# could open /dev/tty, so nothing leaves this machine.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/dvm-pty.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state" "$T/bin" "$T/home/.ssh"
sid=stubsession0000000000000000000000
printf '%s' "$sid" > "$T/state/current"
printf 'org-stub' > "$T/state/org_id"
cat > "$T/bin/devin" <<'EOF'
#!/bin/bash
{ if (: </dev/tty) 2>/dev/null; then echo "tty=yes"; else echo "tty=no"; fi
  echo "args=$*"
  echo "ssh=$(command -v ssh)"
  echo "control=${DVM_CONTROL_PATH:-}"; } >> "$STUB_LOG"
EOF
printf '#!/bin/bash\necho "{}"\n' > "$T/bin/curl"
# Reports the gateway host key as known, so dvm does not call ssh-keyscan. (Linux OpenSSH reads
# ~/.ssh from the passwd home, not $HOME, so a fake known_hosts would not be seen.)
printf '#!/bin/bash\nexit 0\n' > "$T/bin/ssh-keygen"
chmod +x "$T/bin/devin" "$T/bin/curl" "$T/bin/ssh-keygen"
export HOME="$T/home" DVM_STATE_DIR="$T/state" PATH="$T/bin:$PATH" STUB_LOG="$T/calls" DEVIN_API_KEY=stub
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }

# New session without a controlling terminal; the stub never logs in, so no master opens.
out="$(perl -MPOSIX -e 'if (my $pid = fork) { waitpid $pid, 0; exit($? >> 8) } POSIX::setsid(); exec @ARGV' \
  "$ROOT/bin/dvm" run -- true </dev/null 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q "cannot open an SSH connection to $sid" <<<"$out"
check "run without a master fails with the connection message" $?
grep -qx 'tty=yes' "$STUB_LOG"
check "devin ssh gets a terminal for its login" $?
grep -qx "args=ssh $sid true" "$STUB_LOG"
check "the login is 'devin ssh <session> true'" $?
grep -qx "ssh=$ROOT/libexec/ssh" "$STUB_LOG" && grep -qx "control=$T/state/cm-${sid:0:16}" "$STUB_LOG"
check "the login uses libexec/ssh and the session's control path" $?

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
