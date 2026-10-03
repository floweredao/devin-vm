#!/bin/bash
# Live check against the current session, on a private master so other dvm users are not touched:
# when the connection drops mid-command and the next logins fail while the session wakes,
# dvm keeps logging in (DVM_RECONNECT_TRIES) and reruns the command.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/dvr.XXXXXX)" # short: the control socket path must fit in 104 bytes
mkdir -p "$T/state" "$T/bin"
cp "$ROOT/.state/current" "$ROOT/.state/org_id" "$T/state/" || exit 1
sid="$(cat "$T/state/current")"
cm="$T/state/cm-${sid:0:16}"
host="devin-$sid@${DVM_SSH_GATEWAY:-ssh.devin.ai}"
trap '/usr/bin/ssh -o ControlPath="$cm" -O exit "$host" >/dev/null 2>&1; rm -rf "$T"' EXIT
real="$(command -v devin)" || exit 1
cat > "$T/bin/devin" <<EOF
#!/bin/bash
n=\$(cat "$T/fails" 2>/dev/null || echo 0)
if [ "\$1" = ssh ] && [ "\$n" -gt 0 ]; then echo \$((n - 1)) > "$T/fails"; exit 1; fi
exec "$real" "\$@"
EOF
chmod +x "$T/bin/devin"
export DVM_STATE_DIR="$T/state" DVM_RECONNECT_PAUSE=2 PATH="$T/bin:$PATH"
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }

drop_mid_command() { # TRIES -> output of a command whose master is killed after 5 s
  "$ROOT/bin/dvm" run -- true >/dev/null 2>&1 || return 1
  echo 2 > "$T/fails"
  (sleep 5; /usr/bin/ssh -o ControlPath="$cm" -O exit "$host" >/dev/null 2>&1) &
  DVM_RECONNECT_TRIES="$1" "$ROOT/bin/dvm" run -- 'sleep 15; echo RERUN_OK' 2>&1
}

out="$(drop_mid_command 3)"; rc=$?
echo "$out" | sed 's/^/  | /'
[ "$rc" -eq 0 ] && grep -q RERUN_OK <<<"$out" && [ "$(grep -c 'trying again' <<<"$out")" -eq 2 ]
check "two failed logins are retried and the command reruns" $?

out="$(drop_mid_command 2)"; rc=$?
echo "$out" | sed 's/^/  | /'
[ "$rc" -ne 0 ] && grep -q 'cannot reconnect .* after 2 logins' <<<"$out" && ! grep -q RERUN_OK <<<"$out"
check "gives up after DVM_RECONNECT_TRIES logins" $?

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
