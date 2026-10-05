# atobar-init

The onboarding script for [atobar-flow](https://cp.karar.asia/onboarding). This repository holds nothing else.

Run it as a GitHub **admin** of the repository you want atobar-flow to work on, inside a clone of that repository:

```bash
curl -fsSL https://raw.githubusercontent.com/arsenyspb/atobar-init/main/onboard.sh | bash
```

Prefer to read it before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/arsenyspb/atobar-init/main/onboard.sh
less onboard.sh
bash onboard.sh
```

## Before you run it

1. Install the [atobar-flow-agent GitHub App](https://github.com/apps/atobar-flow-agent/installations/new) on the repository (*Only select repositories*).
2. Sign in to the [Control Panel](https://cp.karar.asia), click **Add to atobar-flow** for the repository, open it and click **Generate token**. Keep the page open; the token is shown once.
3. Have `git`, `curl` and the [GitHub CLI](https://cli.github.com) installed, signed in with `gh auth login -s repo,workflow`.

## What it does

| Stage | Action | Changes |
|---|---|---|
| Checks | Detects `owner/repo` from the clone, checks you are an admin and the Control Panel is reachable | nothing |
| 1. GitHub App | Asks you to confirm the App is installed, or opens its install page | nothing |
| 2. Token | Reads the tenant token at a hidden prompt, confirms with the Control Panel that it belongs to this repository, saves it as the `ATOBAR_TENANT_TOKEN` Actions secret | repository secret |
| 3. Trigger | Downloads `.github/workflows/flow-trigger.yml` from the Control Panel and opens a pull request adding it (branch `atobar/onboard`). In an empty repository it pushes the first commit (README + trigger) instead | branch + PR, or first commit |
| 4. Evaluation spec | Opens an issue labelled `flow:onboard` with the evaluation spec template | label + issue |
| 5. Next steps | Prints what happens until atobar-flow handles the repository end to end | nothing |

Each mutating step asks first. Re-running is safe: finished stages are skipped. The token is never printed, written to disk or passed on a command line.

### Empty repositories

A repository with no commits can be onboarded to have atobar-flow build it from zero. There is no base branch to open a pull request against, so stage 3 pushes the first commit to the default branch with a README and the trigger workflow. The evaluation spec issue then gets a **Build from zero** section: describe the language, layout and first user-visible milestone there. If the clone has local commits that were never pushed, the script stops and asks you to push them first.

The stages after this script (spec review, metrics workflow, shadow calibration, activation) are described in the [onboarding guide](https://cp.karar.asia/onboarding).

## Options

| Variable | Default | Purpose |
|---|---|---|
| `ATOBAR_CP_URL` | `https://cp.karar.asia` | Control Panel |
| `ATOBAR_APP_SLUG` | `atobar-flow-agent` | GitHub App |
| `ATOBAR_REPO` | from `gh repo view` | `owner/name` to onboard |
| `ATOBAR_ROTATE=1` | off | Replace an existing `ATOBAR_TENANT_TOKEN` |
| `ATOBAR_YES=1` | off | Answer yes to every question |
| `ATOBAR_TOKEN_FILE` | prompt | Read the token from a file (for unattended runs) |

## Development

```bash
shellcheck onboard.sh tests/test_onboard.sh
bash tests/test_onboard.sh
```

The tests stub `gh` and `curl`; they never touch GitHub or the Control Panel.
