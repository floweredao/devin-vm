# devin-vm

[English](README.md) | 한국어

맥 빌드, 테스트, iOS 시뮬레이터 UI 테스트를 내 맥 대신 **Devin Cloud macOS VM**에서 돌려요.
명령 하나로 프로젝트를 VM에 복사하고, 거기서 실행하고, 출력을 실시간으로 보여 주고, 종료 코드를 그대로 돌려줘요.
내 맥은 느려지지 않고, UI 테스트가 마우스를 뺏어 가지도 않아요.

- `macrun <폴더> '<명령>'` - 프로젝트를 VM에 올려 명령을 실행하고 출력·로그·종료 코드를 받아 와요. 평소에는 이것만 쓰면 돼요.
- `dvm` - `macrun`이 쓰는 아래 단계 도구예요. VM 세션 만들기·깨우기·재우기·지우기, `push`·`run`·`pull`, 셸 열기를 해요.

VM은 Devin Cloud 세션이에요(Apple silicon, Xcode, iOS 시뮬레이터, Homebrew, Node/Python/Rust). `dvm`은 Devin 에이전트에게 "아무것도 하지 말고 기다려"라는 프롬프트로 세션을 만들어요. 그래서 VM은 SSH로만 써요.

## 필요한 것

- macOS와 `git`, `curl`, `rsync`, `ssh`, `perl`, `/usr/bin/python3`(Xcode Command Line Tools), 그리고 `jq`(`brew install jq`).
- **Devin Cloud와 Devin API**가 들어 있는 요금제의 Devin 계정. 2026년 10월 기준 [devin.ai/pricing](https://devin.ai/pricing)에는 클라우드 세션과 API가 Pro부터 들어 있고 Free에는 없어요. 그래서 Free 요금제에서는 `dvm`과 `macrun`이 동작하지 않아요.
- 로그인한 Devin CLI:

  ```sh
  brew install --cask devin-cli      # 또는: curl -fsSL https://cli.devin.ai/install.sh | bash
  devin auth login
  ```

  `dvm`은 CLI 로그인으로 API를 불러요. API가 그 로그인을 받지 않으면 app.devin.ai(Settings > Devin API)에서 개인 토큰을 만들고 `export DEVIN_API_KEY=cog_...`를 해 두세요.

## 설치

```sh
git clone https://github.com/floweredao/devin-vm.git && ./devin-vm/install.sh
```

`install.sh`는 `dvm`과 `macrun`을 `~/.local/bin`에 링크하고(다른 곳은 `--prefix DIR`), 빠진 도구가 있으면 알려 줘요. 심볼릭 링크가 아닌 파일이 이미 있으면 `--force` 없이는 덮어쓰지 않아요.

## 빠른 시작 (5분 정도)

```sh
dvm doctor                        # CLI, 로그인, API, 현재 세션 확인
dvm up --mode swe-2-medium        # VM 세션을 만들고 SSH가 될 때까지 기다려요(처음엔 몇 분)
macrun ~/code/MyApp 'swift test'  # MyApp을 VM에 복사하고 거기서 테스트를 돌려요
```

`macrun`은 실행 중 출력을 그대로 보여 주고, 로그를 `~/Library/Logs/mac-offload/macrun/`에 남기고, 명령의 종료 코드로 끝나요. 그래서 스크립트나 에이전트 작업에서 로컬 명령처럼 쓸 수 있어요.

세션은 하나 만들어서 계속 다시 쓰세요. 그날 일이 끝나면 `dvm sleep`(디스크는 남아요). VM을 지우려면 `dvm down`.

## 자주 쓰는 명령

빌드(VM에서는 코드 서명 없이):

```sh
macrun ~/code/MyApp 'xcodebuild build -scheme MyApp -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO'
```

iOS 시뮬레이터에서 단위 테스트, 결과 묶음 남기기:

```sh
macrun ~/code/MyApp 'xcodebuild test -scheme MyApp -destination "platform=iOS Simulator,name=iPhone 17" -resultBundlePath build/Test.xcresult'
```

시뮬레이터 UI 테스트(XCUITest). 내 화면이 아니라 VM의 시뮬레이터에서 돌아요:

```sh
macrun ~/code/MyApp 'xcodebuild test -scheme MyAppUITests -destination "platform=iOS Simulator,name=iPhone 17" -resultBundlePath build/UI.xcresult'
```

결과 가져오기(로그, 스크린샷, `.xcresult`). `macrun`은 프로젝트를 VM의 `~/work/macrun/<이름>-<해시>`에 둬요. 정확한 이름은 `dvm run -- ls work/macrun`으로 봐요:

```sh
dvm pull work/macrun/MyApp-1a2b3c4d/build/UI.xcresult ./dvm-artifacts/
```

조금 고친 뒤 다시 올리지 않고 실행하기(VM에 마지막 사본이 남아 있어요):

```sh
macrun --no-sync ~/code/MyApp 'swift test --filter LoginTests'
```

그 밖의 명령:

| 명령 | 하는 일 |
| --- | --- |
| `macrun --status` | 세션 상태, 사용량, URL |
| `dvm run -- <명령>` | VM 홈 폴더에서 명령 실행 |
| `dvm push [폴더] [원격]` / `dvm pull <원격> [로컬]` | 실행 없이 파일만 복사 |
| `dvm forward 3000` | VM 포트를 localhost로 연결(계속 떠 있어요) |
| `dvm shell` | VM 대화형 셸 |
| `dvm use <세션 id 또는 URL>` | 웹에서 만든 세션 쓰기 |
| `dvm help` | `dvm` 명령 전체 |

## 올라가는 파일

`macrun`은 폴더를 그대로 올리지 않고 걸러 낸 사본을 올려요.

- git이 추적하거나 무시하지 않는 파일만 올려요(git 저장소가 아니면 모든 파일).
- 절대 안 올리는 것: `.git`, `node_modules`, `build`, `.build`, `DerivedData`, `target`, `data`, `.env`와 `.env.*`(`.env.example`, `.env.sample`, `.env.template`은 올려요), `Local.xcconfig`, `*.p12`, `*.p8`, `*.key`, `*.pem`, `*.mobileprovision`, 키체인, 이름에 `credentials`가 들어간 파일, 추적되지 않는 `.omo`/`.senpi` 에이전트 폴더.
- 빌드 스크립트에서 `git rev-parse`와 `git status`가 되도록, 사본에는 지금 `HEAD` 커밋 하나짜리 `.git`을 넣어요. 추적 중인 파일이 비밀값으로 빠졌으면 git 정보는 아예 보내지 않아요. 끄려면 `MACRUN_GIT=0`.

그래도 코드는 내 맥을 떠나 Cognition 클라우드로 가요. 올리면 안 되는 코드에는 쓰지 마세요.

## 동작 방식

1. `dvm up`이 macOS 플랫폼에 "기다리고 아무것도 하지 마" 프롬프트로 Devin Cloud 세션을 만들어요.
2. 로그인할 때 한 번만 `devin ssh`를 써요. 그 로그인이 OpenSSH ControlMaster가 되어서, 그 뒤의 `ssh`와 `rsync`는 그 연결을 다시 써요. 그래서 1초쯤이면 붙어요.
3. `macrun`이 걸러 낸 사본을 만들고, `~/work/macrun/<이름>-<해시>`로 `rsync`하고, 로그인 `zsh`에서 명령을 돌리고, 출력을 로컬 로그에도 남겨요.
4. `macrun`은 VM의 Xcode 중 내 맥과 Swift 버전이 같은 것을 골라요. 직접 고르려면 `MACRUN_DEVELOPER_DIR=/Applications/Xcode-X.app/Contents/Developer`, VM 기본값을 쓰려면 `none`.

## 잠들기, 깨우기, 비용

- **VM은 Devin 에이전트가 마지막으로 답한 뒤 약 5분이 지나면 잠들어요. 명령이 도는 중이어도 그래요.** 돌던 프로세스는 멈추고 디스크는 남아요. `dvm`이 다시 로그인해서 VM을 깨우고(30~70초) 끊긴 명령을 한 번 다시 돌려요. 그래서 명령은 두 번 돌려도 안전해야 해요.
- 긴 실행에서는 `macrun`이 VM을 깨워 둬요. 4분이 지나면, 그 뒤로 4분마다 `dvm wake`로 에이전트에게 "." 메시지를 보내요. 이건 SWE-2 세션(`dvm up --mode swe-2-medium`)에서만 돼요. 다른 모드에서는 `dvm wake`가 경고만 남겨요. `macrun` 여러 개가 같이 돌아도 한 세션에는 4분에 한 번만 보내요. 기록은 `~/Library/Logs/mac-offload/macrun/wake.log`. 끄려면 `DVM_WAKE_AFTER=0`.
- **비용:** 세션은 Devin 사용량에 잡혀요. VM 깨우기와 깨우기 메시지는 에이전트 활동이라 사용량을 쓸 수 있어요. 세션 안에서 에이전트와 대화하지 말고, 쉴 때는 `dvm sleep`을 하고, 사용량은 `macrun --status`나 app.devin.ai에서 확인하세요.

## 문제 해결

| 증상 | 해결 |
| --- | --- |
| `dvm doctor`에 `api FAILED` | `devin auth login`을 다시 하거나 `DEVIN_API_KEY`에 `cog_` 토큰을 넣어요. 요금제에 API가 없을 수도 있어요(필요한 것 참고). |
| `no current session` | `dvm up --mode swe-2-medium`, 이미 있는 세션이면 `dvm use <세션 id 또는 URL>`. |
| `SSH did not answer` / 시작에서 멈춤 | VM이 깨어나는 중이에요. `dvm wait` 후 다시 해요. 상태는 `dvm status`. |
| `connection ... failed (the session probably went to sleep); reconnecting` | 정상이에요. 명령 중에 VM이 잠들어서 `dvm`이 다시 돌렸어요. 긴 명령은 SWE-2 세션에서 돌려야 `macrun`이 깨워 둘 수 있어요. |
| `wake: ... is a normal session; not sending` | SWE-2 세션이 아니에요. `dvm up --mode swe-2-medium`으로 새로 만드세요. 새 세션은 비어 있어서 다음 `macrun`이 전부 다시 올려요. |
| `macrun: no git metadata sent; N tracked file(s) are excluded` | 추적 중인 파일이 비밀값처럼 보여요(`.env`, `*.p12` 등). 실행은 되고 `.git`만 빠져요. |
| Docker가 필요한 명령이 아주 느림 | VM에 중첩 가상화가 없어서 Docker가 에뮬레이션으로 돌아요. |
| `not a directory` | 프로젝트 폴더를 먼저, 명령은 따옴표로 묶은 한 덩어리로 넘겨요. |

## 한계

- 실기기, 내 인증서로 하는 코드 서명, 실제와 같은 성능 측정은 안 돼요.
- 로그인된 내 브라우저, 로컬 GUI 자동화, 올려도 된다고 정하지 않은 파일이 필요한 일은 내 맥에서 하세요.
- `macrun`은 macOS 도구(`lockf`, `tar --no-mac-metadata`)를 써서 맥에서 돌아요. `dvm`은 `bash`, `curl`, `jq`, `rsync`, Devin CLI가 있으면 돼요.

## 설정

셸에서 정하거나, `macrun`이 읽는 `~/.config/mac-offload/devin.env`(또는 `$MAC_OFFLOAD_CONFIG`)에 적어요. 이 파일에서 `dvm`이 읽는 값(`DEVIN_*`, `DVM_SESSION`, `DVM_STATE_DIR`, `DVM_RECONNECT_TRIES`)은 `export 이름=값`으로 적어요.

| 변수 | 기본값 | 뜻 |
| --- | --- | --- |
| `DEVIN_API_KEY` | CLI 로그인 | API 토큰(`cog_...`) |
| `DEVIN_ORG_ID` | `/v3/self`에서 | Devin 조직 id |
| `DVM_SESSION` | `.state/current` | 현재 세션 대신 쓸 세션 |
| `DVM_STATE_DIR` | `<저장소>/.state` | `dvm`이 현재 세션과 SSH 소켓을 두는 곳 |
| `DVM` | `macrun` 옆의 `bin/dvm` | `macrun`이 쓸 `dvm` |
| `DVM_WAKE_AFTER` / `DVM_WAKE_EVERY` | `240` / `240` | 첫 깨우기까지, 깨우기 사이의 초. `0`이면 꺼요 |
| `DVM_RECONNECT_TRIES` | `3` | VM이 깨어날 때 로그인을 몇 번 시도할지 |
| `MACRUN_GIT` | `1` | `0`이면 git 정보를 보내지 않아요 |
| `MACRUN_DEVELOPER_DIR` | `auto` | VM의 Xcode: `auto`, `none`, 또는 경로 |
| `MACRUN_LOG_DIR` | `~/Library/Logs/mac-offload/macrun` | 실행 로그 |

## 테스트

```sh
tests/macrun-test.sh          # 오프라인, dvm은 가짜
tests/mode-wake-test.sh       # 오프라인, API는 가짜
tests/reconnect-retry-live.sh # 실제 세션 필요
```

## AI 에이전트용

[`SKILL.md`](SKILL.md)는 같은 흐름을 적은 에이전트 스킬이에요. 이 폴더를 에이전트의 skills 폴더에 링크해서 쓰면 돼요.
