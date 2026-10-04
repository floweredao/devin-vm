---
name: devin-vm
description: Offload heavy local work (Xcode/Swift builds, iOS Simulator runs, test suites, headless browser QA) to a Devin Cloud macOS VM over SSH with the dvm wrapper. Use when the user asks to run builds, tests, or QA on the Devin VM, or when the local Mac is overloaded.
---

# devin-vm

`dvm` drives a Devin Cloud macOS VM (Apple silicon, Xcode 26 + 27 RC, iOS 26/27 simulators,
Chrome, Homebrew, Node/Python/Rust) as a remote build and QA machine. The VM belongs to a
Devin session; `dvm` creates that session with a "do nothing, wait" prompt so the Devin agent
stays idle and the VM is used only through SSH.

Binary: `/Users/o3-peter/Documents/omo/devin-vm/bin/dvm` (below, `dvm`).

## Prerequisites

- `devin` CLI installed and logged in (`devin auth login`). Check with `dvm doctor`.
- API access for creating sessions: the CLI login token (`windsurf_api_key` in
  `~/.local/share/devin/credentials.toml`) is accepted by the v3 API, so no extra key is needed.
  If `dvm doctor` reports `api FAILED`, the user must run `devin auth login` again or create a
  `cog_` PAT (app.devin.ai > Settings > Devin API) and export `DEVIN_API_KEY`. Without API access, create the Mac session in the web app or with
  `devin --cloud` + `/platform`, then `dvm use <session-id-or-url>`.

## Workflow

1. `dvm doctor` - confirm CLI, auth, API, and whether a current session exists.
2. `dvm up` - only when there is no usable current session. Creates a macOS session, stores it
   as current, and waits for SSH. Reuse the current session across tasks instead of creating
   new ones. `dvm up --mode swe-2-medium` creates it in SWE-2 mode, which `dvm wake` needs.
3. `dvm push [LOCAL_DIR] [REMOTE_DIR]` - rsync the project (default remote `~/work/<name>`;
   excludes node_modules, .build, DerivedData, build, .DS_Store). Push again after local edits.
4. `dvm run --cd work/<name> -- <command...>` - runs in a login zsh; the exit code is the
   command's. Keep each run self-contained: build, test, and write artifacts in one call.
5. `dvm pull <remote-path> [local-dest]` - bring back logs, screenshots, xcresult bundles.
6. `dvm sleep` when the work is done for now (disk kept, processes stop);
   `dvm down` only when the user wants the VM gone.

`dvm forward PORT` forwards a VM port to localhost and blocks; run it as a background session.
`dvm shell` is interactive and only for the user.

## Recipes

iOS build and unit tests on the simulator:

```bash
dvm push ~/code/MyApp
dvm run --cd work/MyApp -- xcodebuild -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath build/Test.xcresult test
dvm pull work/MyApp/build/Test.xcresult ./dvm-artifacts/
```

Simulator launch + screenshot:

```bash
dvm run -- 'xcrun simctl boot "iPhone 17" || true'
dvm run --cd work/MyApp -- xcrun simctl install booted build/MyApp.app
dvm run -- xcrun simctl launch booted com.example.MyApp
dvm run -- xcrun simctl io booted screenshot /Users/devin/shot.png
dvm pull shot.png ./dvm-artifacts/
```

Web QA fully on the VM (dev server + headless browser in one run):

```bash
dvm push ~/code/web
dvm run --cd work/web -- 'npm ci && (npm run dev >/tmp/dev.log 2>&1 &) && npx playwright test'
dvm pull work/web/playwright-report ./dvm-artifacts/
```

Pass a single quoted string when the command needs shell operators (`&&`, `|`, `&`, redirects);
otherwise pass arguments directly.

## Limits

- Devin suspends the session when its agent is idle, and SSH work does not count as activity:
  the VM can go to sleep in the middle of a command. Running processes (builds, dev servers,
  simulators) stop; disk contents survive. `dvm` then logs in again (which wakes the VM, about
  30-70 s; up to `DVM_RECONNECT_TRIES`=3 logins, 15 s apart) and retries the interrupted
  command once, so keep commands safe to re-run.
- `dvm wake` keeps a `swe-2-*` session awake for about 30 minutes by sending the agent a "."
  message (an SSH login wakes it only for a few minutes). For any other mode it only warns.
  Use it for long commands (macrun does: once after 4 minutes, then every 25).
- The first connection adds the `ssh.devin.ai` host key to `~/.ssh/known_hosts`.
- Transport: `devin ssh` is used only to log in; commands and rsync reuse that login through an
  OpenSSH ControlMaster under `.state/`, so connections after the first take about a second.
- No nested virtualization: Docker runs under QEMU emulation, roughly 15-25x slower.
- No physical devices; performance profiling is not representative.
- Keep on the local Mac: Aside/signed-in browser work, local computer-use GUI automation, and
  anything needing local-only services or files the user has not approved for upload.
- Code and any secrets pushed leave the machine for Cognition's cloud. Do not push `.env` files
  or credentials unless the user asked.
- Usage: the session counts against the user's Devin quota (mostly agent activity; VM time is a
  small fraction). Never message the Devin agent in the session beyond `dvm wake`; that spends
  quota.
