#!/bin/bash
# Offline check of `dvm up --mode` and `dvm wake`: curl and devin are stubs on PATH, so no
# session is created and no message is sent. The stub records each API call as
# "METHOD URL BODY" and answers a session GET with $STUB_MODE as its devin_mode.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/dvm-mode.XXXXXX)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state" "$T/bin"
printf 'stubsession0000000000000000000000' > "$T/state/current"
printf 'org-stub' > "$T/state/org_id"
printf '#!/bin/bash\nexit 1\n' > "$T/bin/devin"
cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
method="" url="" body=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    --data) body="$2"; shift 2 ;;
    -H) shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s %s %s\n' "$method" "$url" "$(tr '\n' ' ' <<<"$body")" >> "$STUB_LOG"
case "$method $url" in
  "GET "*/sessions/*) printf '{"session_id":"stubsession","devin_mode":"%s"}\n' "$STUB_MODE" ;;
  *) printf '{}\n' ;;
esac
EOF
chmod +x "$T/bin/devin" "$T/bin/curl"
export DVM_STATE_DIR="$T/state" PATH="$T/bin:$PATH" STUB_LOG="$T/calls" DEVIN_API_KEY=stub
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
create_body() { sed -n 's#^POST [^ ]*/organizations/org-stub/sessions ##p' "$STUB_LOG" | tail -1; }

# The stub answers the create call with {}, so up stops there instead of waiting for SSH.
: > "$STUB_LOG"
"$ROOT/bin/dvm" up --title t >/dev/null 2>&1
body="$(create_body)"
[ "$(jq -r 'has("devin_mode")' <<<"$body")" = false ] && [ "$(jq -r .platform <<<"$body")" = macos ]
check "up without --mode sends no devin_mode" $?

: > "$STUB_LOG"
"$ROOT/bin/dvm" up --mode swe-2-medium --title t >/dev/null 2>&1
body="$(create_body)"
[ "$(jq -r .devin_mode <<<"$body")" = swe-2-medium ] && [ "$(jq -r .title <<<"$body")" = t ] && [ "$(jq -r .platform <<<"$body")" = macos ]
check "up --mode swe-2-medium sends devin_mode" $?

: > "$STUB_LOG"
out="$(STUB_MODE=swe-2-medium "$ROOT/bin/dvm" wake 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^woke stubsession0000000000000000000000 (swe-2-medium)$' <<<"$out" &&
  [ "$(grep -c '^POST .*/organizations/org-stub/sessions/stubsession0000000000000000000000/messages {"message":"."} $' "$STUB_LOG")" -eq 1 ] &&
  [ "$(wc -l < "$STUB_LOG")" -eq 2 ]
check "wake sends one '.' message to a swe-2 session" $?

: > "$STUB_LOG"
out="$(STUB_MODE=normal "$ROOT/bin/dvm" wake 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q 'is a normal session; not sending' <<<"$out" && ! grep -q '^POST' "$STUB_LOG"
check "wake only warns for a normal session" $?

: > "$STUB_LOG"
out="$(STUB_MODE=swe-2-high "$ROOT/bin/dvm" status 2>&1)"
grep -q '^mode     swe-2-high$' <<<"$out"
check "status shows the session mode" $?

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
