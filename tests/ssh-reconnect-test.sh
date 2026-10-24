#!/bin/bash
# Offline check of libexec/ssh and dvm's reconnect path. dvm and libexec/ssh are copied with
# /usr/bin/ssh pointed at a stub; the stub, devin, curl and ssh-keygen are on PATH, HOME is fake,
# and nothing leaves this machine. The stub ssh plays both ends: a login through libexec/ssh
# (ControlMaster=auto) creates a plain file at the ControlPath as the "master", -O check/exit
# look at that file, and a command over the master (ControlMaster=no) follows $STUB_DIR/plan,
# one line per command: ok, exit N, drop (master dies, 255), refuse (master stays, every new
# session is refused, 255) or hang (until SIGINT, then 255 like ssh). A probe "true" is never
# planned. $STUB_DIR/login-fails makes that many logins fail; $STUB_DIR/hostkey makes every
# login fail with ssh's changed-host-key error.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/dvmssh.XXXXXX)" # short: the control socket path must fit in 104 bytes
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/dvm/bin" "$T/dvm/libexec" "$T/bin" "$T/home/.ssh" "$T/stub" "$T/state"
sed "s#/usr/bin/ssh#$T/bin/ssh#g" "$ROOT/bin/dvm" > "$T/dvm/bin/dvm"
sed "s#/usr/bin/ssh#$T/bin/ssh#g" "$ROOT/libexec/ssh" > "$T/dvm/libexec/ssh"
cat > "$T/bin/ssh" <<'EOF'
#!/bin/bash
if [ -n "${STUB_ARGV:-}" ]; then printf '[%s]' "$@" > "$STUB_ARGV"; echo >> "$STUB_ARGV"; exit "${STUB_RC:-0}"; fi
cp="" master="" persist="" op=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) case "$2" in # ssh keeps the first value given for an option
          ControlPath=*) [ -n "$cp" ] || cp="${2#ControlPath=}" ;;
          ControlMaster=*) [ -n "$master" ] || master="${2#ControlMaster=}" ;;
          ControlPersist=*) [ -n "$persist" ] || persist="${2#ControlPersist=}" ;;
        esac; shift 2 ;;
    -O) op="$2"; shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
host="$1"; shift
# ssh expands %-tokens in ControlPath: %% is a literal %, any other unknown token is fatal.
rest="${cp//%%/}"
if [[ "$rest" == *%* ]]; then echo "vdollar_percent_expand: unknown key ${rest#*%}" >&2; exit 255; fi
cp="${cp//%%/%}"
case "$op" in
  check) [ -e "$cp" ] && exit 0; echo "Control socket connect($cp): No such file or directory" >&2; exit 255 ;;
  exit) echo "master-exit" >> "$STUB_LOG"; rm -f "$cp" "$STUB_DIR/refusing"; exit 0 ;;
esac
if [ "$master" = auto ]; then
  echo "login $host $* persist=$persist cp=$cp" >> "$STUB_LOG"
  if [ -e "$STUB_DIR/hostkey" ]; then
    printf '%s\n' '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' \
      '@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @' \
      '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' \
      "Host key for ${host#*@} has changed and you have requested strict checking." \
      'Host key verification failed.' >&2
    exit 255
  fi
  n="$(cat "$STUB_DIR/login-fails" 2>/dev/null || echo 0)"
  if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$STUB_DIR/login-fails"; echo "Connection closed by gateway" >&2; exit 255; fi
  # The master binds "<ControlPath>.<16 random chars>" first; macOS allows 104 bytes in sun_path.
  if [ $((${#cp} + 17)) -ge 104 ]; then
    echo "unix_listener: path \"$cp.XXXXXXXXXXXXXXXX\" too long for Unix domain socket" >&2
  else
    : > "$cp"
  fi
  exit 0
fi
[ -e "$cp" ] || { echo "Control socket connect($cp): No such file or directory" >&2; exit 255; }
[ -e "$STUB_DIR/refusing" ] && { echo "Session open refused by peer" >&2; exit 255; }
[ "$*" = true ] && exit 0
echo "run $*" >> "$STUB_LOG"
step="$(head -1 "$STUB_DIR/plan" 2>/dev/null)"
tail -n +2 "$STUB_DIR/plan" > "$STUB_DIR/plan.next" 2>/dev/null; mv "$STUB_DIR/plan.next" "$STUB_DIR/plan"
case "$step" in
  drop) rm -f "$cp"; echo "Connection to ${host#*@} closed by remote host." >&2; exit 255 ;;
  refuse) : > "$STUB_DIR/refusing"; echo "Session open refused by peer" >&2; exit 255 ;;
  hang) trap 'echo "Exiting on signal: Interrupt" >&2; exit 255' INT
        : > "$STUB_DIR/hanging"; while :; do sleep 0.1; done ;;
  exit\ *) exit "${step#exit }" ;;
  *) echo "remote ok"; exit 0 ;;
esac
EOF
cat > "$T/bin/devin" <<'EOF'
#!/bin/bash
[ "$1" = ssh ] || exit 1
echo "devin ssh $2" >> "$STUB_LOG"
exec ssh "devin-$2@ssh.devin.ai" "${@:3}"
EOF
printf '#!/bin/bash\necho "{}"\n' > "$T/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/ssh-keygen" # the gateway host key is known
printf '#!/bin/bash\necho keyscan >> "$STUB_LOG"; exit 1\n' > "$T/bin/ssh-keyscan"
chmod +x "$T/dvm/bin/dvm" "$T/dvm/libexec/ssh" "$T/bin/"*
sid=stubsession0000000000000000000000
DVM="$T/dvm/bin/dvm"
export HOME="$T/home" PATH="$T/bin:$PATH" STUB_LOG="$T/log" STUB_DIR="$T/stub" DEVIN_API_KEY=stub \
  DVM_SESSION="$sid" DVM_STATE_DIR="$T/state" DVM_RECONNECT_PAUSE=0
unset DVM_RECONNECT_TRIES DVM_CONTROL_PATH DVM_CONTROL_PERSIST DVM_SSH_GATEWAY
CM="$T/state/cm-${sid:0:16}"
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); return 1; fi; }
count() { grep -c "$1" "$STUB_LOG"; }
fresh() { # PLAN_LINES... -> no master, empty log, the given plan
  rm -f "$CM" "$STUB_DIR"/*; : > "$STUB_LOG"
  printf '%s\n' "$@" > "$STUB_DIR/plan"
}
open() { fresh "$@"; : > "$CM"; } # same, with a master already open
show() { echo "$out" | sed 's/^/  | /'; sed 's/^/  log: /' "$STUB_LOG"; }

# --- libexec/ssh ---
STUB_ARGV="$T/argv" DVM_CONTROL_PATH="$T/state/cm-x" STUB_RC=7 "$T/dvm/libexec/ssh" -T 'devin-a@h' 'echo "a b"' c; rc=$?
[ "$rc" -eq 7 ] && [ "$(cat "$T/argv")" = "[-o][ControlMaster=auto][-o][ControlPath=$T/state/cm-x][-o][ControlPersist=1800][-o][ServerAliveInterval=30][-T][devin-a@h][echo \"a b\"][c]" ]
check "libexec/ssh adds the master options before the arguments and keeps ssh's exit code" $?
STUB_ARGV="$T/argv" DVM_CONTROL_PATH="$T/state/cm-x" DVM_CONTROL_PERSIST=60 "$T/dvm/libexec/ssh" h true
grep -q '\[ControlPersist=60\]' "$T/argv"
check "libexec/ssh takes ControlPersist from DVM_CONTROL_PERSIST" $?
STUB_ARGV="$T/argv" STUB_RC=3 "$T/dvm/libexec/ssh" -p 22 'h' 'x y'; rc=$?
[ "$rc" -eq 3 ] && [ "$(cat "$T/argv")" = "[-p][22][h][x y]" ]
check "libexec/ssh without DVM_CONTROL_PATH passes the arguments unchanged" $?

# --- normal runs ---
fresh ok ok
out="$("$DVM" run -- echo hi 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q 'remote ok' <<<"$out" && [ "$(count '^devin ssh')" -eq 1 ] &&
  grep -q "^login devin-$sid@ssh.devin.ai true persist=1800 cp=$CM$" "$STUB_LOG" &&
  "$DVM" run -- echo again >/dev/null 2>&1 && [ "$(count '^devin ssh')" -eq 1 ] && [ "$(count '^run ')" -eq 2 ] &&
  ! grep -q keyscan "$STUB_LOG"
check "run logs in once through libexec/ssh and reuses the master" $? || show

open "exit 3"
out="$("$DVM" run -- false 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(count '^run ')" -eq 1 ] && [ "$(count '^devin ssh')" -eq 0 ] && [ -e "$CM" ] && ! grep -q reconnect <<<"$out"
check "a failing command's exit code comes back and nothing is retried" $? || show

open "exit 255"
out="$("$DVM" run -- 'perl -e die' 2>&1)"; rc=$?
[ "$rc" -eq 255 ] && [ "$(count '^run ')" -eq 1 ] && [ "$(count '^devin ssh')" -eq 0 ] && [ "$(count master-exit)" -eq 0 ] && [ -e "$CM" ]
check "a command that exits 255 itself over a working master is not rerun" $? || show

# --- connection lost ---
open drop "exit 4"
out="$("$DVM" run -- make 2>&1)"; rc=$?
[ "$rc" -eq 4 ] && [ "$(count '^run ')" -eq 2 ] && [ "$(count '^devin ssh')" -eq 1 ] && grep -q 'reconnecting and retrying once' <<<"$out"
check "ssh dying mid-command logs in again, reruns, and returns the rerun's exit code" $? || show

open refuse ok
out="$("$DVM" run -- make 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(count '^run ')" -eq 2 ] && [ "$(count master-exit)" -eq 1 ] && [ "$(count '^devin ssh')" -eq 1 ]
check "a master whose sessions are refused is closed, reopened, and the command reruns" $? || show

open drop drop
out="$("$DVM" run -- make 2>&1)"; rc=$?
[ "$rc" -eq 255 ] && [ "$(count '^run ')" -eq 2 ] && [ "$(count '^devin ssh')" -eq 1 ]
check "the command is retried only once" $? || show

open drop ok; echo 2 > "$STUB_DIR/login-fails"
out="$("$DVM" run -- make 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(count '^devin ssh')" -eq 3 ] && [ "$(grep -c 'trying again in 0s' <<<"$out")" -eq 2 ] && [ "$(count '^run ')" -eq 2 ]
check "logins that fail while the session wakes are retried (default 3 tries)" $? || show

open drop ok; echo 5 > "$STUB_DIR/login-fails"
out="$(DVM_RECONNECT_TRIES=2 "$DVM" run -- make 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q "cannot reconnect to $sid after 2 logins" <<<"$out" && [ "$(count '^devin ssh')" -eq 2 ] && [ "$(count '^run ')" -eq 1 ]
check "gives up after DVM_RECONNECT_TRIES logins without rerunning" $? || show

# --- Ctrl-C: ssh exits 255 on SIGINT just as on a dropped connection ---
open hang ok
perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' "$DVM" run -- 'sleep 100' > "$T/out" 2>&1 &
pid=$!
for _ in $(seq 1 100); do [ -e "$STUB_DIR/hanging" ] && break; sleep 0.1; done
kill -INT -- -"$pid"
wait "$pid"; rc=$?
out="$(cat "$T/out")"
[ "$rc" -eq 130 ] && [ "$(count '^run ')" -eq 1 ] && [ "$(count '^devin ssh')" -eq 0 ] && [ "$(count master-exit)" -eq 0 ] && [ -e "$CM" ]
check "Ctrl-C stops dvm instead of reconnecting and rerunning (rc=$rc)" $? || show

# --- host key ---
fresh ok; : > "$STUB_DIR/hostkey"
out="$("$DVM" run -- true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'host key of ssh.devin.ai' <<<"$out" && grep -q 'ssh-keygen -R ssh.devin.ai' <<<"$out"
check "a changed gateway host key is reported as such" $? || show

open drop ok
: > "$STUB_DIR/hostkey" # the master is open; only the reconnect logs in
out="$("$DVM" run -- make 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'host key of ssh.devin.ai' <<<"$out" && [ "$(count '^devin ssh')" -eq 1 ] && [ "$(count '^run ')" -eq 1 ]
check "a changed host key during reconnect stops after one login" $? || show

# --- control socket paths ---
long="$T/$(printf 'd%.0s' $(seq 1 90))"
fresh ok
out="$(DVM_STATE_DIR="$long" "$DVM" run -- true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'too long' <<<"$out" && grep -q DVM_STATE_DIR <<<"$out" && [ "$(count '^devin ssh')" -eq 0 ]
check "a control socket path ssh cannot bind is refused before logging in" $? || show

pct="$T/s%b"
fresh ok
out="$(DVM_STATE_DIR="$pct" "$DVM" run -- true 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -e "$pct/cm-${sid:0:16}" ] && [ "$(count '^run ')" -eq 1 ]
check "a state dir with % in its name works (ssh expands % in ControlPath)" $? || show

fresh ok
out="$(DVM_STATE_DIR="$T/s p" "$DVM" run -- true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'must not contain spaces' <<<"$out" && [ ! -s "$STUB_LOG" ]
check "a state dir with a space is refused before any ssh" $? || show

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
