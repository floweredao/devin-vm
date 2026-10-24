---
name: devin-vm-windows
description: On a Windows PC, offload Mac-only work (Xcode/Swift builds, iOS Simulator runs and UI tests, Mac test suites) to a Devin Cloud macOS VM with dvm and macrun, run through WSL. Use when the user on Windows asks to build, test, or QA an iOS or Mac app, or to run anything on the Devin VM.
---

# devin-vm on Windows

`dvm` and `macrun` drive a Devin Cloud macOS VM (Apple silicon, Xcode, iOS simulators,
Homebrew, Node/Python/Rust) as a remote build and QA machine. On Windows they run only inside
WSL 2 (Ubuntu): they need bash, rsync, and OpenSSH connection sharing (ControlMaster), which
PowerShell, cmd, and Git Bash do not have. The full workflow, recipes, and limits are in
`SKILL.md` at the root of the devin-vm clone in WSL, outside this folder; print it with:

```powershell
wsl -e bash -lc "type -P dvm | xargs readlink -f | xargs dirname | xargs -I{} cat {}/../SKILL.md"
```

This file covers what is different on Windows.

## Running commands

- If your shell is already the WSL Ubuntu shell (`uname -s` prints `Linux`), run `dvm` and
  `macrun` directly.
- From PowerShell or cmd, wrap every call in a WSL login shell so `~/.local/bin` is on PATH:

  ```powershell
  wsl -e bash -lc "dvm doctor"
  wsl -e bash -lc "macrun ~/code/MyApp 'swift test'"
  ```

  Quote the whole bash command in double quotes and the macrun command in single quotes.
  The exit code of `wsl` is the command's exit code.
- If WSL picks the wrong distribution, add `-d Ubuntu` after `wsl`.

## Paths

- Prefer projects in the WSL home (`~/code/MyApp`); they are much faster than Windows drives.
- A Windows path must be converted before passing it: `C:\Users\me\code\MyApp` is
  `/mnt/c/Users/me/code/MyApp` (`wsl -e wslpath -u 'C:\Users\me\code\MyApp'` prints it).
- Pulled artifacts land in WSL paths. To open one in Windows, pull into `/mnt/c/...`, or give
  the user the `\\wsl$\Ubuntu\home\<user>\...` path.
- macrun logs: `~/.local/state/mac-offload/logs/macrun/` (wake log: `wake.log` there).

## Setup check

1. `wsl -e bash -lc "command -v dvm macrun devin"` prints three paths. If not, the user has to
   finish the setup in the README section
   [Windows (WSL)](https://github.com/floweredao/devin-vm#windows-wsl): `wsl --install -d Ubuntu`,
   the apt packages, `curl -fsSL https://cli.devin.ai/install.sh | bash`, a clone of devin-vm in
   the WSL home, and `./install.sh`.
2. `wsl -e bash -lc "dvm doctor"` shows CLI, auth, API access, and the current session.
   `devin auth login` is interactive and only the user can run it.

## Differences from the Mac version

- No local Xcode, so `macrun` cannot pick the VM's Xcode by local Swift version; it uses the VM
  default. Set `MACRUN_DEVELOPER_DIR=/Applications/Xcode-X.app/Contents/Developer` to choose.
- `dvm shell` and `dvm forward PORT` work from the WSL shell. A forwarded port is reachable from
  Windows at `localhost:PORT` while the default WSL networking forwards localhost.
- Everything else (the upload filter that leaves secrets behind, waking SWE-2 sessions during
  long runs, reconnecting after the VM sleeps, quota rules) is the same as on a Mac.
