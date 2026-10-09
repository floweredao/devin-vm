# devin-vm

English | [한국어](README-ko.md)

Run your Mac builds, tests, and iOS Simulator UI tests on a **Devin Cloud macOS VM** instead of your own Mac.
One command copies your project to the VM, runs it there, streams the output back, and returns the exit code.
Your Mac stays cool, and UI tests never take over your mouse.

- `macrun <dir> '<command>'` - sync a project to the VM, run a command there, and get the output, log, and exit code back. This is what you use day to day.
- `dvm` - the lower-level tool that `macrun` uses: create, wake, sleep, and delete the VM session; `push`, `run`, `pull`; open a shell.

The VM is a Devin Cloud session (Apple silicon, Xcode, iOS simulators, Homebrew, Node/Python/Rust). `dvm` creates the session with a prompt that tells the Devin agent to do nothing and wait, so the VM is used only over SSH.

## Requirements

- macOS with `git`, `curl`, `rsync`, `ssh`, `perl`, and `/usr/bin/python3` (Xcode Command Line Tools), plus `jq` (`brew install jq`).
- A Devin account on a plan that includes **Devin Cloud and the Devin API**. As of October 2026, [devin.ai/pricing](https://devin.ai/pricing) lists cloud sessions and API access from the Pro plan and not on Free, so `dvm` and `macrun` will not work on the Free plan.
- The Devin CLI, logged in:

  ```sh
  brew install --cask devin-cli      # or: curl -fsSL https://cli.devin.ai/install.sh | bash
  devin auth login
  ```

  `dvm` reuses the CLI login for API calls. If your login is not accepted by the API, create a personal token in app.devin.ai (Settings > Devin API) and `export DEVIN_API_KEY=cog_...`.

## Install

```sh
git clone https://github.com/floweredao/devin-vm.git && ./devin-vm/install.sh
```

`install.sh` links `dvm` and `macrun` into `~/.local/bin` (choose another directory with `--prefix DIR`) and lists anything that is missing. It never overwrites an existing file that is not a symlink unless you pass `--force`.

## Quick start (about 5 minutes)

```sh
dvm doctor                        # CLI, login, API access, current session
dvm up --mode swe-2-medium        # create the VM session and wait for SSH (a few minutes the first time)
macrun ~/code/MyApp 'swift test'  # copy MyApp to the VM, run the tests there
```

`macrun` prints the command's output as it runs, writes a log to `~/Library/Logs/mac-offload/macrun/`, and exits with the command's exit code, so you can use it in scripts and agent workflows just like a local command.

Make one session and keep reusing it. When you are done for the day: `dvm sleep` (keeps the disk). To delete the VM: `dvm down`.

## Common commands

Build (no code signing on the VM):

```sh
macrun ~/code/MyApp 'xcodebuild build -scheme MyApp -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO'
```

Unit tests on an iOS simulator, keeping the result bundle:

```sh
macrun ~/code/MyApp 'xcodebuild test -scheme MyApp -destination "platform=iOS Simulator,name=iPhone 17" -resultBundlePath build/Test.xcresult'
```

Simulator UI tests (XCUITest), which run on the VM's simulator and not on your screen:

```sh
macrun ~/code/MyApp 'xcodebuild test -scheme MyAppUITests -destination "platform=iOS Simulator,name=iPhone 17" -resultBundlePath build/UI.xcresult'
```

Get results back (logs, screenshots, `.xcresult`). `macrun` puts each project at `~/work/macrun/<name>-<hash>` on the VM; `dvm run -- ls work/macrun` shows the exact name:

```sh
dvm pull work/macrun/MyApp-1a2b3c4d/build/UI.xcresult ./dvm-artifacts/
```

Run again after a small change without re-uploading (the VM keeps the last copy):

```sh
macrun --no-sync ~/code/MyApp 'swift test --filter LoginTests'
```

Other useful commands:

| Command | What it does |
| --- | --- |
| `macrun --status` | session status, usage, and URL |
| `dvm run -- <cmd>` | run a command in the VM's home directory |
| `dvm push [dir] [remote]` / `dvm pull <remote> [local]` | copy files without running anything |
| `dvm forward 3000` | forward a VM port to localhost (blocks) |
| `dvm shell` | interactive shell on the VM |
| `dvm use <session-id-or-url>` | use a session you created in the web app |
| `dvm help` | every `dvm` command |

## What gets uploaded

`macrun` uploads a cleaned copy, not your folder as-is:

- Only files that git tracks or does not ignore (or every file if the folder is not a git repo).
- Never: `.git`, `node_modules`, `build`, `.build`, `DerivedData`, `target`, `data`, `.env` and `.env.*` (except `.env.example`, `.env.sample`, `.env.template`), `Local.xcconfig`, `*.p12`, `*.p8`, `*.key`, `*.pem`, `*.mobileprovision`, keychains, files named like `credentials`, and untracked `.omo`/`.senpi` agent folders.
- The copy gets a one-commit `.git` at your current `HEAD` so `git rev-parse` and `git status` work in build scripts. If a tracked file was excluded as a secret, no git data is sent at all. Turn this off with `MACRUN_GIT=0`.

Your code still leaves your machine for Cognition's cloud. Do not use this for code you are not allowed to upload.

## How it works

1. `dvm up` creates a Devin Cloud session on the macOS platform with a "wait and do nothing" prompt.
2. `devin ssh` is used once to log in. That login becomes an OpenSSH ControlMaster, so every later `ssh` and `rsync` reuses it and takes about a second.
3. `macrun` stages the cleaned copy, `rsync`s it to `~/work/macrun/<name>-<hash>`, runs the command in a login `zsh`, and tees the output into a local log.
4. `macrun` picks the VM's Xcode whose Swift version matches your local one. Set `MACRUN_DEVELOPER_DIR=/Applications/Xcode-X.app/Contents/Developer` to choose, or `none` to keep the VM default.

## Sleep, wake, and cost

- **The VM goes to sleep about 5 minutes after the Devin agent last replied, even while your command is running.** Running processes stop; the disk is kept. `dvm` logs in again (which wakes the VM in about 30-70 seconds) and reruns the interrupted command once, so keep commands safe to run twice.
- For long runs, `macrun` keeps the VM awake: after 4 minutes, and every 4 minutes after that, it runs `dvm wake`, which sends the agent a "." message. This works only in SWE-2 sessions (`dvm up --mode swe-2-medium`). For other modes, `dvm wake` only prints a warning. Several `macrun`s at once send at most one wake per session every 4 minutes. Logs go to `~/Library/Logs/mac-offload/macrun/wake.log`. Set `DVM_WAKE_AFTER=0` to turn it off.
- **Cost:** the session counts against your Devin usage. Waking the VM and each wake message are agent activity, so they can use quota. Do not chat with the agent in the session, `dvm sleep` when you stop, and check usage with `macrun --status` or in app.devin.ai.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `dvm doctor` shows `api FAILED` | Run `devin auth login` again, or set `DEVIN_API_KEY` to a `cog_` token. Your plan may not include the API (see Requirements). |
| `no current session` | `dvm up --mode swe-2-medium`, or `dvm use <session-id-or-url>` for an existing one. |
| `SSH did not answer` / commands hang at the start | The VM is waking up; `dvm wait` and try again. `dvm status` shows the session state. |
| `connection ... failed (the session probably went to sleep); reconnecting` | Normal: the VM slept mid-command and `dvm` reran it. For long commands, use a SWE-2 session so `macrun` can keep it awake. |
| `wake: ... is a normal session; not sending` | The session is not SWE-2. Create a new one with `dvm up --mode swe-2-medium`; it starts empty, so the next `macrun` uploads everything again. |
| `macrun: no git metadata sent; N tracked file(s) are excluded` | A tracked file looks like a secret (`.env`, `*.p12`, ...). The run still works; only `.git` is left out. |
| A command that needs Docker is very slow | The VM has no nested virtualization; Docker runs under emulation. |
| `not a directory` | Pass the project folder first, then the command as one quoted string. |

## Limits

- No physical devices, code signing with your certificates, or representative performance profiling.
- Keep work on your own Mac when it needs your signed-in browser, local GUI automation, or files you have not approved for upload.
- `macrun` uses macOS tools (`lockf`, `tar --no-mac-metadata`), so it runs on a Mac. `dvm` needs `bash`, `curl`, `jq`, `rsync`, and the Devin CLI.

## Configuration

Set these in your shell, or in `~/.config/mac-offload/devin.env` (or `$MAC_OFFLOAD_CONFIG`), which `macrun` sources. In that file, write `export NAME=value` for the variables `dvm` reads (`DEVIN_*`, `DVM_SESSION`, `DVM_STATE_DIR`, `DVM_RECONNECT_TRIES`):

| Variable | Default | Meaning |
| --- | --- | --- |
| `DEVIN_API_KEY` | CLI login | API token (`cog_...`) |
| `DEVIN_ORG_ID` | from `/v3/self` | Devin organization id |
| `DVM_SESSION` | `.state/current` | session to use instead of the current one |
| `DVM_STATE_DIR` | `<repo>/.state` | where `dvm` keeps the current session and SSH socket |
| `DVM` | `bin/dvm` next to `macrun` | `dvm` binary for `macrun` |
| `DVM_WAKE_AFTER` / `DVM_WAKE_EVERY` | `240` / `240` | seconds before the first wake and between wakes; `0` turns it off |
| `DVM_RECONNECT_TRIES` | `3` | logins to try when the VM is waking |
| `MACRUN_GIT` | `1` | `0` sends no git metadata |
| `MACRUN_DEVELOPER_DIR` | `auto` | Xcode on the VM: `auto`, `none`, or a path |
| `MACRUN_LOG_DIR` | `~/Library/Logs/mac-offload/macrun` | run logs |

## Tests

```sh
tests/macrun-test.sh          # offline, dvm is stubbed
tests/mode-wake-test.sh       # offline, the API is stubbed
tests/reconnect-retry-live.sh # live: needs a current session
```

## For AI agents

[`SKILL.md`](SKILL.md) is an agent skill describing the same workflow. Link this folder into your agent's skills directory to use it.
