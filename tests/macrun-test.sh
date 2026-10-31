#!/bin/bash
# Offline check of macrun: dvm is a stub on $DVM, so nothing leaves this machine.
set -u
BASE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/macrun-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
PASS=0
FAIL=0
case_result() {
  if [ "$2" -eq 0 ]; then echo "PASS $1"; PASS=$((PASS + 1))
  else echo "FAIL $1"; FAIL=$((FAIL + 1)); fi
}
mkdir -p "$ROOT/bin" "$ROOT/state" "$ROOT/cache" "$ROOT/log" "$ROOT/home"
STUB="$ROOT/bin/dvm"
CALLS="$ROOT/calls"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$DVM_CALLS"
case "$1" in
  status) printf 'status   running\nusage    1.5\nurl      secret-url\n'; exit "${STUB_STATUS_RC:-0}" ;;
  current) echo stubsession0000000000 ;;
  wake)
    if [ "${STUB_WAKE_MODE:-swe-2-medium}" = normal ]; then echo 'dvm: wake: stub is a normal session; not sending' >&2
    else echo 'woke stubsession0000000000 (swe-2-medium)'; fi ;;
  run)
    [ "$2" = "--cd" ] || exit 0
    sleep "${STUB_RUN_SLEEP:-0}"
    if [ -n "${STUB_FIRST_RC_FILE:-}" ] && [ ! -e "$STUB_FIRST_RC_FILE" ]; then : > "$STUB_FIRST_RC_FILE"; exit 255; fi
    exit "${STUB_RUN_RC:-0}" ;;
esac
STUB_EOF
chmod +x "$STUB"
export HOME="$ROOT/home" DVM="$STUB" DVM_CALLS="$CALLS" DVM_ACTIVE_WINDOW=10800
export MACRUN_STATE_DIR="$ROOT/state" MACRUN_CACHE_DIR="$ROOT/cache" MACRUN_LOG_DIR="$ROOT/log"
MACRUN="${MACRUN:-$BASE/bin/macrun}"
export MAC_OFFLOAD_LIB="$ROOT/no-vendor-lib"
REPO="$ROOT/repo"
mkdir -p "$REPO/src" "$REPO/.omo" "$REPO/build"
cd "$REPO" || exit 1
git init -q
printf '*.log\n' > .gitignore
printf 'pkg\n' > Package.swift
printf 'source\n' > src/a.swift
printf 'secret\n' > .env
printf 'secret\n' > .omo/x
printf 'secret\n' > Local.xcconfig
printf 'secret\n' > a.p12
printf 'generated\n' > build/x
printf 'ignored\n' > ignored.log
printf 'new\n' > new.swift
git add .gitignore Package.swift src/a.swift .env .omo/x Local.xcconfig a.p12 build/x
git -c user.name=test -c user.email=test@example.invalid commit -qm init
printf 'session state\n' > .omo/untracked-state

mkdir -p "$REPO/vendor/inner" && git -C "$REPO/vendor/inner" init -q && printf 'secret\n' > "$REPO/vendor/inner/.env" && printf 'x\n' > "$REPO/vendor/inner/code.swift"
printf 'kc\n' > "$REPO/login.keychain-db"
MACRUN_STAGE_ONLY=1 "$MACRUN" "$REPO" true > "$ROOT/stage.out" 2>&1
stage_path="$(sed -n 's/^staged [0-9]* files at //p' "$ROOT/stage.out")"
actual="$(cd "$stage_path" && find . -type f -print | LC_ALL=C sort)"
expected="$(printf './.gitignore\n./.omo/x\n./Package.swift\n./new.swift\n./src/a.swift')"
[ ! -e "$stage_path/vendor" ] && [ ! -e "$stage_path/login.keychain-db" ]; case_result "nested untracked repo and keychain-db are not staged" $?
[ "$actual" = "$expected" ]; case_result "stage keeps tracked .omo, drops untracked .omo, secrets, build, ignored" $?
case_result "stage count reports five" "$(grep -q '^staged 5 files at ' "$ROOT/stage.out"; echo $?)"
MACRUN_SKIP_UNTRACKED= MACRUN_STAGE_ONLY=1 "$MACRUN" "$REPO" true > "$ROOT/skip-none.out" 2>&1
none_path="$(sed -n 's/^staged [0-9]* files at //p' "$ROOT/skip-none.out")"
[ -f "$none_path/.omo/untracked-state" ] && grep -q '^staged 6 files at ' "$ROOT/skip-none.out"
case_result "MACRUN_SKIP_UNTRACKED= (empty) uploads untracked .omo files too" $?
mkdir -p "$REPO/.cache-x" && printf 'x\n' > "$REPO/.cache-x/y"
MACRUN_SKIP_UNTRACKED='.cache-x' MACRUN_STAGE_ONLY=1 "$MACRUN" "$REPO" true > "$ROOT/skip-own.out" 2>&1
own_path="$(sed -n 's/^staged [0-9]* files at //p' "$ROOT/skip-own.out")"
[ ! -e "$own_path/.cache-x" ] && [ -f "$own_path/.omo/untracked-state" ]
case_result "MACRUN_SKIP_UNTRACKED replaces the default list" $?
rm -rf "$REPO/.cache-x"
[ ! -e "$stage_path/.git" ] && grep -q 'no git metadata sent; 4 tracked file' "$ROOT/stage.out"
case_result "tracked secrets keep git metadata out of the copy" $?

CLEAN="$ROOT/clean repo"
mkdir -p "$CLEAN/src" "$CLEAN/.omo"
git -C "$CLEAN" init -q
printf '*.log\n' > "$CLEAN/.gitignore"
printf 'one\n' > "$CLEAN/src/a.swift"
printf 'readme\n' > "$CLEAN/README.md"
printf 'KEY=\n' > "$CLEAN/.env.example"
printf 'test\n' > "$CLEAN/src/AccountCredentialSnapshotTests.swift"
git -C "$CLEAN" add .gitignore src/a.swift README.md .env.example src/AccountCredentialSnapshotTests.swift
git -C "$CLEAN" -c user.name=test -c user.email=test@example.invalid commit -qm init
git -C "$CLEAN" remote add origin https://token@example.invalid/repo.git
printf 'two\n' > "$CLEAN/src/a.swift"
printf 'new\n' > "$CLEAN/new.swift"
printf 'state\n' > "$CLEAN/.omo/state"
printf 'log\n' > "$CLEAN/x.log"
printf 'secret\n' > "$CLEAN/gcp-credentials.json"
printf 'secret\n' > "$CLEAN/credentials.toml"
printf 'secret\n' > "$CLEAN/.env.local"
MACRUN_STAGE_ONLY=1 "$MACRUN" "$CLEAN" true > "$ROOT/clean.out" 2>&1
clean_stage="$(sed -n 's/^staged [0-9]* files at //p' "$ROOT/clean.out")"
[ "$(git -C "$clean_stage" rev-parse HEAD)" = "$(git -C "$CLEAN" rev-parse HEAD)" ]
case_result "clean repo copy has the same git HEAD" $?
[ -f "$clean_stage/.env.example" ] && [ -f "$clean_stage/src/AccountCredentialSnapshotTests.swift" ] && [ ! -e "$clean_stage/gcp-credentials.json" ] && [ ! -e "$clean_stage/credentials.toml" ] && [ ! -e "$clean_stage/.env.local" ]
case_result "env templates and credential-named sources stay, credential files and .env.local go" $?
[ "$(git -C "$clean_stage" status --porcelain)" = "$(printf ' M src/a.swift\n?? new.swift')" ]
case_result "copy git status shows the uncommitted edit and the untracked file" $?
[ "$(git -C "$clean_stage" ls-files)" = "$(git -C "$CLEAN" ls-files)" ] && [ -z "$(git -C "$clean_stage" remote)" ] && [ "$(git -C "$clean_stage" rev-list --count HEAD)" -eq 1 ]
case_result "copy git has the tracked list, one commit and no remote" $?
MACRUN_GIT=0 MACRUN_STAGE_ONLY=1 "$MACRUN" "$CLEAN" true > /dev/null 2>&1
[ ! -e "$clean_stage/.git" ]
case_result "MACRUN_GIT=0 sends no git metadata" $?

UNTRACKED="$ROOT/untracked-secret"
mkdir -p "$UNTRACKED"
git -C "$UNTRACKED" init -q
printf 'secret\n' > "$UNTRACKED/.env"
printf 'x\n' > "$UNTRACKED/a.swift"
git -C "$UNTRACKED" add .env a.swift
git -C "$UNTRACKED" -c user.name=test -c user.email=test@example.invalid commit -qm init
git -C "$UNTRACKED" rm -q --cached .env
printf '.env\n' > "$UNTRACKED/.gitignore"
MACRUN_STAGE_ONLY=1 "$MACRUN" "$UNTRACKED" true > "$ROOT/untracked.out" 2>&1
untracked_stage="$(sed -n 's/^staged [0-9]* files at //p' "$ROOT/untracked.out")"
[ -n "$untracked_stage" ] && [ ! -e "$untracked_stage/.env" ] && [ ! -e "$untracked_stage/.git" ] && grep -q 'no git metadata sent; 1 tracked file' "$ROOT/untracked.out"
case_result "a secret still in HEAD but no longer in the index keeps git metadata out" $?

: > "$CALLS"
STUB_RUN_RC=3 "$MACRUN" "$REPO" 'echo run' > "$ROOT/run.out" 2>&1
run_rc=$?
[ "$run_rc" -eq 3 ]; case_result "run returns stub exit code" $?
grep -q '^push ' "$CALLS" && grep -q '^run --cd work/macrun/' "$CALLS"
case_result "push precedes run with remote cd" $?
: > "$CALLS"
STUB_FIRST_RC_FILE="$ROOT/first-run-done" "$MACRUN" "$REPO" 'echo run' > "$ROOT/retry.out" 2>&1
retry_rc=$?
[ "$retry_rc" -eq 255 ] && [ "$(grep -c '^run --cd work/macrun/' "$CALLS")" -eq 1 ]
case_result "a dvm connection failure is returned as is (dvm itself retries)" $?
: > "$CALLS"
cat > "$ROOT/bin/nopush-dvm" <<'NOPUSH_EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$DVM_CALLS"
case "$1" in push) exit 1 ;; esac
NOPUSH_EOF
chmod +x "$ROOT/bin/nopush-dvm"
DVM="$ROOT/bin/nopush-dvm" "$MACRUN" "$REPO" 'echo run' > "$ROOT/nopush.out" 2>&1
nopush_rc=$?
[ "$nopush_rc" -eq 1 ] && grep -q '^push ' "$CALLS" && ! grep -q '^run --cd' "$CALLS"
case_result "a failed push stops before the run and returns its code" $?

# The dvm-vendor.sh hook runs only when MAC_OFFLOAD_LIB names its folder, not from a default path.
INST="$ROOT/inst"
mkdir -p "$INST/bin" "$INST/share/mac-offload/lib" "$ROOT/hook-lib"
cp "$MACRUN" "$INST/bin/macrun"
hook='dvm_vendor_sync() { : > "$HOOK_MARK"; }'
printf '%s\n' "$hook" > "$INST/share/mac-offload/lib/dvm-vendor.sh"
printf '%s\n' "$hook" > "$ROOT/hook-lib/dvm-vendor.sh"
env -u MAC_OFFLOAD_LIB HOOK_MARK="$ROOT/hook-default" "$INST/bin/macrun" "$REPO" 'echo run' > /dev/null 2>&1
[ ! -e "$ROOT/hook-default" ]; case_result "without MAC_OFFLOAD_LIB no hook is sourced from a default path" $?
MAC_OFFLOAD_LIB="$ROOT/hook-lib" HOOK_MARK="$ROOT/hook-set" "$MACRUN" "$REPO" 'echo run' > /dev/null 2>&1
[ -e "$ROOT/hook-set" ]; case_result "MAC_OFFLOAD_LIB set sources its dvm-vendor.sh and calls dvm_vendor_sync" $?
until_value="$(cat "$ROOT/state/devin-active-until")"
now="$(date +%s)"
[ "$until_value" -ge $((now + 10795)) ] && [ "$until_value" -le $((now + 10805)) ]
case_result "active window set near three hours" $?

WAKE_LOG="$ROOT/log/wake.log"
wake_calls() { grep -c '^wake$' "$CALLS"; }
fresh_wake() { : > "$CALLS"; rm -f "$WAKE_LOG" "$ROOT"/state/dvm-wake-*; }
export DVM_WAKE_TICK=0.317
fresh_wake
DVM_WAKE_AFTER=2 "$MACRUN" --no-sync "$REPO" 'echo short' > /dev/null 2>&1
[ "$(wake_calls)" -eq 0 ] && [ ! -e "$WAKE_LOG" ]
case_result "a run shorter than DVM_WAKE_AFTER sends no wake" $?

fresh_wake
DVM_WAKE_AFTER=1 DVM_WAKE_EVERY=30 STUB_RUN_SLEEP=5 "$MACRUN" --no-sync "$REPO" 'echo long' > "$ROOT/wake1.out" 2>&1
[ "$(wake_calls)" -eq 1 ] && grep -q 'session=stubsession0000000000 action=sent' "$WAKE_LOG" &&
  [ -s "$ROOT/state/dvm-wake-stubsession0000000000" ] && grep -q 'macrun: wake stubsession0000000000: sent' "$ROOT/wake1.out"
case_result "a run past DVM_WAKE_AFTER sends one wake and stamps the session" $?
! pgrep -f "sleep $DVM_WAKE_TICK" >/dev/null && ! pgrep -f -- "$MACRUN --wake-tick" >/dev/null
case_result "no timer process is left after the run" $?

fresh_wake
DVM_WAKE_AFTER=1 DVM_WAKE_EVERY=2 STUB_RUN_SLEEP=8 "$MACRUN" --no-sync "$REPO" 'echo longer' > /dev/null 2>&1
n="$(wake_calls)"
[ "$n" -ge 2 ] && [ "$n" -le 5 ]
case_result "wakes repeat every DVM_WAKE_EVERY seconds ($n in 8 s)" $?

fresh_wake
OTHER="$ROOT/other"
mkdir -p "$OTHER" && printf 'x\n' > "$OTHER/a.swift"
DVM_WAKE_AFTER=1 DVM_WAKE_EVERY=30 STUB_RUN_SLEEP=5 "$MACRUN" --no-sync "$REPO" 'echo a' > /dev/null 2>&1 &
first=$!
DVM_WAKE_AFTER=1 DVM_WAKE_EVERY=30 STUB_RUN_SLEEP=5 "$MACRUN" --no-sync "$OTHER" 'echo b' > /dev/null 2>&1
wait "$first"
[ "$(wake_calls)" -eq 1 ] && [ "$(grep -c 'action=sent' "$WAKE_LOG")" -eq 1 ] && [ "$(grep -c 'action=skip' "$WAKE_LOG")" -eq 1 ]
case_result "two macruns at once send one wake to the session" $?

fresh_wake
STUB_WAKE_MODE=normal DVM_WAKE_AFTER=1 DVM_WAKE_EVERY=30 STUB_RUN_SLEEP=4 "$MACRUN" --no-sync "$REPO" 'echo n' > /dev/null 2>&1
[ "$(wake_calls)" -eq 1 ] && grep -q 'action=not-swe2' "$WAKE_LOG"
case_result "a non-swe2 session is asked once per DVM_WAKE_EVERY and logged" $?

fresh_wake
DVM_WAKE_AFTER=0 STUB_RUN_SLEEP=3 "$MACRUN" --no-sync "$REPO" 'echo off' > /dev/null 2>&1
[ "$(wake_calls)" -eq 0 ]
case_result "DVM_WAKE_AFTER=0 turns the timer off" $?

fresh_wake
DVM_WAKE_AFTER=1 DVM_WAKE_EVERY=0 STUB_RUN_SLEEP=3 "$MACRUN" --no-sync "$REPO" 'echo off' > /dev/null 2>&1
[ "$(wake_calls)" -eq 0 ]
case_result "DVM_WAKE_EVERY=0 turns the timer off" $?

fresh_wake
DVM_WAKE_AFTER=30 STUB_RUN_SLEEP=20 "$MACRUN" --no-sync "$REPO" 'echo killed' > /dev/null 2>&1 &
locker=$!
for _ in $(seq 50); do pgrep -f "sleep $DVM_WAKE_TICK" >/dev/null && pgrep -f "$STUB run --cd" >/dev/null && break; sleep 0.1; done
kill -9 $(pgrep -P "$locker")
stub_pid="$(pgrep -f "$STUB run --cd")"
pkill -P "$stub_pid"; kill "$stub_pid" 2>/dev/null
wait "$locker" 2>/dev/null
for _ in $(seq 30); do pgrep -f "sleep $DVM_WAKE_TICK" >/dev/null || break; sleep 0.1; done
! pgrep -f "sleep $DVM_WAKE_TICK" >/dev/null
case_result "the timer ends by itself when macrun is killed" $?
unset DVM_WAKE_TICK

out="$("$MACRUN" --status 2>&1)"; status_rc=$?
[ "$status_rc" -eq 0 ] && grep -q '^status   running$' <<<"$out" && grep -q '^active-until [0-9]*$' <<<"$out"
case_result "--status shows the session and the active window" $?
out="$(STUB_STATUS_RC=1 "$MACRUN" --status 2>&1)"; status_rc=$?
[ "$status_rc" -eq 1 ] && grep -q '^active-until [0-9]*$' <<<"$out"
case_result "--status returns dvm status's failure and still shows the window" $?

UNTIL="$ROOT/state/devin-active-until"
printf '5\n' > "$UNTIL"
"$MACRUN" --awake 2h >/dev/null 2>&1; awake_rc=$?
now="$(date +%s)"
[ "$awake_rc" -eq 0 ] && [ "$(cat "$UNTIL")" -ge $((now + 7195)) ] && [ "$(cat "$UNTIL")" -le $((now + 7205)) ]
case_result "--awake 2h keeps the VM awake for two hours" $?
"$MACRUN" --awake 0 >/dev/null 2>&1; awake_rc=$?
[ "$awake_rc" -eq 0 ] && [ "$(cat "$UNTIL")" = 0 ]
case_result "--awake 0 clears the window" $?
bad_ok=0
for bad in '' 5 h m fooh 1xm -5m 1.5h; do
  printf '99\n' > "$UNTIL"
  out="$("$MACRUN" --awake "$bad" 2>&1)"; awake_rc=$?
  { [ "$awake_rc" -eq 2 ] && [ "$(cat "$UNTIL")" = 99 ] && grep -q 'macrun: --awake takes' <<<"$out"; } ||
    { echo "  --awake '$bad' returned $awake_rc, window $(cat "$UNTIL"): $out"; bad_ok=1; }
done
case_result "--awake rejects a malformed duration with exit 2, names the forms it takes, and keeps the window" "$bad_ok"

bash -n "$MACRUN" "$0"
case_result "bash syntax checks pass" $?
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
