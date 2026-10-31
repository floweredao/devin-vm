#!/bin/bash
# Every environment variable bin/dvm, bin/macrun and libexec/ssh read must be in the Configuration table of
# both READMEs and in devin.env.example.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fail=0
vars="$(grep -ohE '\$\{(DEVIN|DVM|MACRUN|MAC_OFFLOAD)_?[A-Z_]*:-' "$ROOT/bin/dvm" "$ROOT/bin/macrun" "$ROOT/libexec/ssh" | sed -E 's/^\$\{//; s/:-$//' | sort -u)"
# Set by the tools for their own child processes, not by users.
vars="$(printf '%s\n' $vars | grep -vxE 'MACRUN_LOCKED|MACRUN_WAKE_FOR|DVM_CONTROL_PATH')"
[ -n "$vars" ] || { echo "FAIL found no variables in bin/ and libexec/"; exit 1; }
for v in $vars; do
  for doc in README.md README-ko.md; do
    if ! grep -qE "^\| \`$v\`|^\| [^|]*\`$v\`" "$ROOT/$doc"; then
      echo "FAIL $v is not in the Configuration table of $doc"; fail=1
    fi
  done
done
# The example lists the settings a user would change; test-only knobs are left out.
for v in $vars; do
  case "$v" in DVM_WAKE_TICK|MACRUN_STAGE_ONLY|MAC_OFFLOAD_LIB|MAC_OFFLOAD_CONFIG|MACRUN_WAKE_LOG|DVM_ACTIVE_WINDOW) continue ;; esac
  grep -qE "^# export $v=" "$ROOT/devin.env.example" || { echo "FAIL $v is not in devin.env.example"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "PASS every variable is documented ($(echo $vars | wc -w | tr -d ' ') variables)"
exit "$fail"
