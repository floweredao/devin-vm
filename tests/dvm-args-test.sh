#!/bin/bash
# Offline check of dvm's argument parsing and error handling. curl, devin, rsync, ssh-keygen and
# ssh-keyscan are stubs on PATH that only record their calls, so nothing leaves this machine.
# The remote-quoting cases source dvm's functions with with_reconnect replaced by a recorder and
# run the recorded remote command through a stub zsh (bash) in a scratch home directory.
# shellcheck disable=SC2016,SC2088,SC2319 # literal stub scripts and remote ~ paths; check reads $? of the test before it
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="${TMPDIR:-/tmp}"
T="$(mktemp -d "${tmp%/}/dvm-args.XXXXXX")" # macOS TMPDIR ends in /, and a // would not match pwd
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state" "$T/bin" "$T/home"
sid=stubsession0000000000000000000000
cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "$STUB_LOG"
# dvm passes the Authorization header on stdin (-H @-), out of ps; record it apart.
for arg in "$@"; do [ "$arg" = @- ] && cat >> "$STUB_LOG.stdin"; done
printf '{}\n'
EOF
for tool in devin rsync ssh-keyscan; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >> "$STUB_LOG"\nexit 1\n' "$tool" > "$T/bin/$tool"
done
printf '#!/bin/bash\nexit 0\n' > "$T/bin/ssh-keygen"
printf '#!/bin/bash\nexec bash -c "$2"\n' > "$T/bin/zsh"
chmod +x "$T/bin/"*
export HOME="$T/home" DVM_STATE_DIR="$T/state" PATH="$T/bin:$PATH" STUB_LOG="$T/calls" DEVIN_API_KEY=stub
unset DVM_SESSION DEVIN_ORG_ID
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
reset() { # [with-session] [with-org]
  rm -f "$T/state/current" "$T/state/org_id" "$STUB_LOG.stdin"; : > "$STUB_LOG"
  [ "${1:-}" = with-session ] && printf '%s' "$sid" > "$T/state/current"
  [ "${2:-}" = with-org ] && printf 'org-stub' > "$T/state/org_id"
  return 0
}
dvm() { out="$("$ROOT/bin/dvm" "$@" 2>&1)"; rc=$?; }

# ---------- argument parsing ----------

reset with-session with-org
dvm bogus
[ "$rc" -eq 2 ] && grep -q '^dvm - drive a Devin Cloud macOS VM' <<<"$out" && [ ! -s "$STUB_LOG" ]
check "an unknown subcommand prints usage and exits 2" $?

dvm help
[ "$rc" -eq 0 ] && grep -q 'dvm up \[--repo owner/repo\]' <<<"$out"
check "help exits 0 with the usage" $?

dvm up --bogus
[ "$rc" -eq 1 ] && grep -q "up: unknown argument '--bogus'" <<<"$out" && [ ! -s "$STUB_LOG" ]
check "up rejects an unknown option before any API call" $?

dvm use https://app.devin.ai/sessions/devin-abc123/
[ "$rc" -eq 0 ] && [ "$(cat "$T/state/current")" = abc123 ]
check "use takes a session URL and stores the bare id" $?

dvm use one two
[ "$rc" -eq 1 ] && grep -q 'use: expected one session id or URL' <<<"$out"
check "use rejects two arguments" $?

out="$(DVM_SESSION=https://app.devin.ai/sessions/xyz789 "$ROOT/bin/dvm" current 2>&1)"
[ "$out" = xyz789 ]
check "DVM_SESSION overrides the current session and accepts a URL" $?

reset with-session with-org
dvm run
[ "$rc" -eq 1 ] && grep -q 'run: missing command' <<<"$out" && [ ! -s "$STUB_LOG" ]
check "run without a command fails before connecting" $?

dvm push a b c
[ "$rc" -eq 1 ] && grep -q 'push: too many arguments' <<<"$out" && [ ! -s "$STUB_LOG" ]
check "push rejects a third directory" $?

dvm pull
[ "$rc" -eq 1 ] && grep -q 'pull: missing REMOTE_PATH' <<<"$out" && [ ! -s "$STUB_LOG" ]
check "pull without a path fails" $?

dvm forward
[ "$rc" -eq 1 ] && grep -q 'forward: missing PORT' <<<"$out" && [ ! -s "$STUB_LOG" ]
check "forward without a port fails" $?

# Without devin, jq and curl on PATH (a fresh machine), help, use and current still work, and
# the other subcommands name the missing tool.
mkdir -p "$T/minbin"
for c in bash dirname readlink cat sed head mkdir; do ln -sf "$(command -v "$c")" "$T/minbin/$c"; done
bare() { out="$(PATH="$T/minbin" "$T/minbin/bash" "$ROOT/bin/dvm" "$@" 2>&1)"; rc=$?; }
reset
for args in help --help; do
  bare $args
  [ "$rc" -eq 0 ] && grep -q '^dvm - drive a Devin Cloud macOS VM' <<<"$out"
  check "'dvm $args' prints the usage without devin, jq and curl installed" $?
done
bare use abc123
[ "$rc" -eq 0 ] && [ "$(cat "$T/state/current")" = abc123 ]
check "use works without devin, jq and curl installed" $?
bare current
[ "$rc" -eq 0 ] && [ "$out" = abc123 ]
check "current works without devin, jq and curl installed" $?
bare status
[ "$rc" -eq 1 ] && grep -q "'devin' is required but not installed" <<<"$out"
check "status still names the missing devin CLI" $?

# ---------- failures that must stop dvm before it calls out ----------

for args in "status" "run -- true" "forward 3000" "shell"; do
  reset "" with-org
  # shellcheck disable=SC2086 # word splitting of $args is intended
  dvm $args
  [ "$rc" -ne 0 ] && grep -q 'no current session' <<<"$out" && [ ! -s "$STUB_LOG" ]
  check "'$args' without a session stops before calling curl or devin" $?
done

reset with-session with-org
out="$(env -u DEVIN_API_KEY DEVIN_CREDENTIALS_FILE="$T/none" "$ROOT/bin/dvm" wake 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'no API credential' <<<"$out" && [ ! -s "$STUB_LOG" ]
check "no credential stops before an unauthenticated API call" $?

reset with-session with-org
printf '[auth]\napi_key = "cog_synthetic_test_value"\n' > "$T/credentials.toml"
env -u DEVIN_API_KEY DEVIN_CREDENTIALS_FILE="$T/credentials.toml" "$ROOT/bin/dvm" status >/dev/null 2>&1
grep -qx 'Authorization: Bearer cog_synthetic_test_value' "$STUB_LOG.stdin"
check "the CLI login token is read from credentials.toml" $?

# The stub answers /v3/self with {}, so the org id cannot be resolved.
for args in "status" "up" "sleep" "down"; do
  reset with-session
  # shellcheck disable=SC2086
  dvm $args
  [ "$rc" -ne 0 ] && grep -q 'could not resolve org id' <<<"$out" && ! grep -q '/organizations//' "$STUB_LOG"
  check "'$args' without an org id makes no /organizations// call" $?
done
[ "$(cat "$T/state/current" 2>/dev/null)" = "$sid" ]
check "down without an org id keeps the current session" $?

# ---------- remote command quoting ----------

lib="$T/lib/bin/dvm"
mkdir -p "$(dirname "$lib")"
[ "$(tail -1 "$ROOT/bin/dvm")" = 'main "$@"' ] && sed '$d' "$ROOT/bin/dvm" > "$lib"
check "dvm ends with main \"\$@\" (needed to source its functions)" $?
recorded() { # FUNCTION ARGS... -> runs a dvm function, writes each with_reconnect call's last argument to $T/rec.N
  rm -f "$T"/rec.*
  bash -c 'source "$1"; shift
    n=0; with_reconnect() { n=$((n + 1)); printf "%s" "${@: -1}" > "$REC.$n"; }
    session() { echo stubsession; }
    "$@"' _ "$lib" "$@" >/dev/null 2>&1
}
remote() { (cd "$HOME" && bash -c "$1") 2>&1; } # what the VM's login shell does with the command

space_dir="work/macrun/My Project-1a2b3c4d"
mkdir -p "$HOME/$space_dir"
REC="$T/rec" recorded cmd_run --cd "$space_dir" -- pwd
[ "$(remote "$(cat "$T/rec.1")")" = "$HOME/$space_dir" ]
check "run --cd works with a directory that has a space" $?

REC="$T/rec" recorded cmd_run --cd "~/$space_dir" -- pwd
[ "$(remote "$(cat "$T/rec.1")")" = "$HOME/$space_dir" ]
check "run --cd keeps a leading ~/ expanding on the VM" $?

REC="$T/rec" recorded cmd_run -- pwd
[ "$(remote "$(cat "$T/rec.1")")" = "$HOME" ]
check "run without --cd runs in the home directory" $?

REC="$T/rec" recorded cmd_run -- echo "a b" "c'd"
[ "$(remote "$(cat "$T/rec.1")")" = "a b c'd" ]
check "run keeps each argument intact" $?

mkdir -p "$T/src/Another Project"
REC="$T/rec" recorded cmd_push "$T/src/Another Project"
remote "$(cat "$T/rec.1")" >/dev/null
[ -d "$HOME/work/Another Project" ] && [ ! -e "$HOME/work/Another" ] && [ ! -e "$HOME/Project" ]
check "push creates one remote directory for a name with a space" $?

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
