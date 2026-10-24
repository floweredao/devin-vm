#!/bin/bash
# Offline security checks of dvm and macrun. curl, devin, ssh-keygen and ssh-keyscan are stubs on
# PATH and macrun gets a stub dvm, so nothing leaves this machine; keys and tokens are synthetic.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/dvm-sec.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state" "$T/bin" "$T/home"
sid=stubsession0000000000000000000000
token=cog_synthetic_token_0000
# The stub curl writes its argv (what ps shows) to $STUB_LOG and any header it reads from stdin
# (-H @-) to $STUB_LOG.stdin.
cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "$STUB_LOG"
for arg in "$@"; do [ "$arg" = @- ] && cat >> "$STUB_LOG.stdin"; done
printf '{"session_id":"stubsession","devin_mode":"normal"}\n'
EOF
cat > "$T/bin/devin" <<'EOF'
#!/bin/bash
printf 'devin %s\n' "$*" >> "$STUB_LOG"
exit 1
EOF
# ssh-keyscan answers with a different synthetic key on each call, as a gateway that is being
# impersonated for only some connections would; ssh-keygen -F says the host is unknown and
# -l prints "FP-<key>" for each key in the file.
cat > "$T/bin/ssh-keyscan" <<'EOF'
#!/bin/bash
n="$(cat "$STUB_LOG.scans" 2>/dev/null || echo 0)"; echo $((n + 1)) > "$STUB_LOG.scans"
printf '%s ssh-ed25519 AAAAsyntheticKey%s\n' "${@: -1}" "$n"
EOF
cat > "$T/bin/ssh-keygen" <<'EOF'
#!/bin/bash
case "$1" in
  -F) exit 1 ;;
  -lf) awk '{print "256 FP-" $3 " " $1 " (ED25519)"}' "$2" ;;
esac
EOF
chmod +x "$T/bin/"*
export HOME="$T/home" DVM_STATE_DIR="$T/state" PATH="$T/bin:$PATH" STUB_LOG="$T/calls" DEVIN_API_KEY="$token"
unset DVM_SESSION DEVIN_ORG_ID DVM_SSH_GATEWAY
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
reset() { rm -f "$T/calls"* "$T/home/.ssh/known_hosts"; printf '%s' "$sid" > "$T/state/current"; printf 'org-stub' > "$T/state/org_id"; }

# ---------- the API token stays out of argv ----------

reset
"$ROOT/bin/dvm" status >/dev/null 2>&1
grep -q '^curl .*/v3/organizations/org-stub/sessions/' "$STUB_LOG" && ! grep -q "$token" "$STUB_LOG"
check "the API token is not in curl's argv (visible in ps)" $?
[ "$(cat "$STUB_LOG.stdin" 2>/dev/null)" = "Authorization: Bearer $token" ] && grep -q 'Accept: application/json' "$STUB_LOG"
check "curl still gets the Authorization header, on stdin" $?

reset
printf '[auth]\napi_key = "cog_synthetic_cli_0000"\n' > "$T/credentials.toml"
env -u DEVIN_API_KEY DEVIN_CREDENTIALS_FILE="$T/credentials.toml" "$ROOT/bin/dvm" status >/dev/null 2>&1
! grep -q cog_synthetic_cli_0000 "$STUB_LOG" && grep -q 'Bearer cog_synthetic_cli_0000$' "$STUB_LOG.stdin"
check "the CLI login token is not in curl's argv either" $?

# ---------- session ids ----------

reset
out="$("$ROOT/bin/dvm" use 'abc -Jevil.example' 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'not a session id' <<<"$out" && [ "$(cat "$T/state/current")" = "$sid" ]
check "use rejects an id that would split into extra ssh options and keeps the current one" $?

reset
out="$(DVM_SESSION='abc -oProxyJump=x' "$ROOT/bin/dvm" wake 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'not a session id' <<<"$out" && [ ! -e "$STUB_LOG" ]
check "a DVM_SESSION with a space stops wake before any API call" $?

# run passes "$(session)" straight to remote_ssh, where die in the substitution does not stop
# dvm, so only check that the id never reaches devin ssh.
reset
out="$(DVM_SESSION='abc -oProxyJump=x' "$ROOT/bin/dvm" run -- true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'not a session id' <<<"$out" && ! grep -q ProxyJump "$STUB_LOG" 2>/dev/null
check "a DVM_SESSION with a space never reaches devin ssh" $?

reset
"$ROOT/bin/dvm" use https://app.devin.ai/sessions/devin-0123abcdef_x-9/ >/dev/null 2>&1
[ "$(cat "$T/state/current")" = 0123abcdef_x-9 ]
check "use still takes a session URL" $?

# ---------- gateway host key ----------

reset
out="$("$ROOT/bin/dvm" run -- true 2>&1)"
stored="$(awk '{print $3}' "$T/home/.ssh/known_hosts" 2>/dev/null)"
[ "$(grep -c . "$T/home/.ssh/known_hosts" 2>/dev/null)" = 1 ] && grep -q "added ssh.devin.ai host key: FP-$stored$" <<<"$out"
check "the fingerprint shown is the one of the key written to known_hosts ($stored)" $?

# ---------- macrun secret filter on case-insensitive file systems ----------

cat > "$T/bin/stub-dvm" <<'EOF'
#!/bin/bash
EOF
chmod +x "$T/bin/stub-dvm"
P="$T/proj"
mkdir -p "$P/sub"
git -C "$P" init -q
printf 'code\n' > "$P/a.swift"
printf 'KEY=\n' > "$P/.Env.Example"
for f in .ENV sub/.Env.Local LOCAL.XCCONFIG Server.PEM dist.P12 AuthKey.P8 app.KEY Dev.MobileProvision login.Keychain-db; do
  printf 'secret\n' > "$P/$f"
done
git -C "$P" add a.swift .Env.Example
git -C "$P" -c user.name=test -c user.email=test@example.invalid commit -qm init
run_stage() { DVM="$T/bin/stub-dvm" MACRUN_STATE_DIR="$T/mstate" MACRUN_CACHE_DIR="$T/cache" MACRUN_LOG_DIR="$T/log" \
  MAC_OFFLOAD_LIB="$T/no-lib" MACRUN_STAGE_ONLY=1 "$ROOT/bin/macrun" "$1" true 2>&1; }
out="$(run_stage "$P")"
stage="$(sed -n 's/^staged [0-9]* files at //p' <<<"$out")"
actual="$(cd "$stage" 2>/dev/null && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort)"
[ -n "$stage" ] && [ "$actual" = "$(printf './.Env.Example\n./a.swift')" ]
check "upper-case variants of .env, .env.*, Local.xcconfig, keys and keychains are not staged" $?

git -C "$P" add -f .ENV
git -C "$P" -c user.name=test -c user.email=test@example.invalid commit -qm env
out="$(run_stage "$P")"
stage="$(sed -n 's/^staged [0-9]* files at //p' <<<"$out")"
[ -n "$stage" ] && [ ! -e "$stage/.ENV" ] && [ ! -e "$stage/.git" ] && grep -q 'no git metadata sent; 1 tracked file' <<<"$out"
check "a tracked .ENV keeps git metadata (which would carry it) out of the copy" $?

bash -n "$ROOT/bin/dvm" "$ROOT/bin/macrun" "$0"
check "bash syntax checks pass" $?
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
