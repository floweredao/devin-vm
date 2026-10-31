#!/bin/bash
# Offline check of install.sh: it links into a scratch --prefix, and the tools it looks for are
# stubs on PATH that never run, so nothing outside the scratch directory changes.
# shellcheck disable=SC2319 # check reads $? of the test before it
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/dvm-install.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
for tool in devin jq curl rsync ssh git perl python3 script flock; do
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/$tool"
done
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
pass=0 fail=0
check() { if [ "$2" -eq 0 ]; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
install() { out="$("$ROOT/install.sh" "$@" 2>&1)"; rc=$?; }

install --bogus
[ "$rc" -eq 2 ] && grep -q "unknown argument '--bogus'" <<<"$out"
check "an unknown argument exits 2" $?

install --prefix
[ "$rc" -eq 2 ] && [ "$out" = "install.sh: --prefix needs a value" ]
check "--prefix without a value exits 2 and says so" $?

install --help
[ "$rc" -eq 0 ] && grep -q 'Usage: ./install.sh \[--prefix DIR\] \[--force\]$' <<<"$out"
check "--help prints the usage line" $?

P="$T/prefix"
install --prefix "$P"
[ "$rc" -eq 0 ] && [ "$(readlink "$P/dvm")" = "$ROOT/bin/dvm" ] && [ "$(readlink "$P/macrun")" = "$ROOT/bin/macrun" ]
check "--prefix links dvm and macrun and exits 0 when nothing is missing" $?

rm -f "$P/dvm" && printf 'mine\n' > "$P/dvm"
install --prefix "$P"
[ "$(cat "$P/dvm")" = mine ] && [ ! -L "$P/dvm" ] && grep -q "^skip   $P/dvm exists" <<<"$out"
check "an existing file is kept without --force" $?

install --prefix "$P" --force
[ "$(readlink "$P/dvm")" = "$ROOT/bin/dvm" ]
check "--force replaces it with the link" $?

rm "$T/bin/devin"
PATH="$T/bin:/usr/bin:/bin" install --prefix "$P"
if PATH=/usr/bin:/bin command -v devin >/dev/null 2>&1; then
  echo "SKIP a missing tool makes install.sh exit 1 (a real devin is installed)"
else
  [ "$rc" -eq 1 ] && grep -q '^MISSING devin$' <<<"$out"
  check "a missing tool makes install.sh exit 1" $?
fi

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
