# Contributing

Bug reports and pull requests are welcome. Please open an issue first for larger changes.

## Layout

- `bin/dvm` - session management and remote execution (bash, `set -euo pipefail`).
- `bin/macrun` - stages a cleaned copy of a project and runs a command on the VM through `dvm`.
- `libexec/ssh` - put first on `PATH` while `devin ssh` logs in, so the login becomes an OpenSSH ControlMaster.
- `install.sh` - links the tools into a bin directory and lists missing dependencies.
- `SKILL.md`, `windows/SKILL.md` - agent skills; keep them in step with the READMEs.
- `tests/` - one shell script per area.

## Tests

Every `tests/*-test.sh` script is offline: `devin`, `curl`, `ssh`, `ssh-keyscan` and `ssh-keygen` are stubs, and nothing is sent to Devin. Run them all before you open a pull request:

```sh
for t in tests/*-test.sh; do bash "$t" || echo "FAILED $t"; done
```

CI runs the same loop on macOS (`.github/workflows/tests.yml`). `tests/reconnect-retry-live.sh` needs a real session and is run by hand.

A bug fix comes with a test that fails without the fix. New behavior gets a case in the script for that area, or a new `tests/<area>-test.sh`.

## Style

- Keep both tools working on macOS (BSD tools, bash 3.2 for `install.sh` and `macrun`) and on Linux, including WSL.
- New settings are environment variables with a default. Add each one to the Configuration table in `README.md` and `README-ko.md` and to `devin.env.example`; `tests/docs-config-test.sh` checks this.
- Change `README.md` and `README-ko.md` together.
