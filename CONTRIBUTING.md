<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Contributing to ahwa_ynh

This is the iteration loop for the YunoHost package. End users get
[the README](./README.md); upstream app code lives at
[remoun/ahwa](https://github.com/remoun/ahwa).

## Layers

Three layers, fastest first:

1. **Lint (seconds, runs on Mac).** `make lint` runs
   [package_linter](https://github.com/YunoHost/package_linter)
   against this repo. Pure Python, no Linux required.
2. **Live install on a VPS (sub-minute, runs on Mac).** `make deploy`
   rsyncs to a YunoHost VPS over SSH and triggers
   `yunohost app install` (or `app upgrade`). Hit the test URL,
   confirm a fresh table can be created.
3. **CI (minutes, runs in GitHub Actions).** Lint runs on every PR.
   Full [package_check](https://github.com/YunoHost/package_check)
   runs on `workflow_dispatch` against the self-hosted runner.

## One-time setup

### Passwordless sudo for `yunohost`

The deploy loop runs `sudo yunohost ...` over SSH; prompting for a
password every iteration breaks the loop. Add a per-command NOPASSWD
rule scoped to your deploy user:

```bash
echo '<your-user> ALL=(root) NOPASSWD: /usr/bin/yunohost' | \
  sudo EDITOR='tee' visudo -f /etc/sudoers.d/yunohost-cmnd
sudo -k && sudo -n yunohost --version && echo OK
```

If the second command still prompts, your YNH account inherits a
broader rule from the LDAP `admins` role that wins via evaluation
order. The fix is documented in
[the M2 launch post](https://remoun.dev/posts/ahwa-m2). Short
version: `sudo -ll` shows the source as `LDAP Role: admins`; a
dedicated non-LDAP service user with the per-command rule above
sidesteps it cleanly.

### Test domain

Pick or create a subdomain like `ahwa-test.<your-domain>`:

```bash
ssh vps sudo yunohost domain list
ssh vps sudo yunohost domain add ahwa-test.<your-domain>
export AHWA_YNH_DOMAIN=ahwa-test.<your-domain>
export AHWA_YNH_PATH=/
```

Or pass them on each `make` invocation. The Makefile reads both.

## The loop

```bash
make lint            # ~1s
make deploy          # ~30-90s (first install slower)
make logs            # tail recent journal entries
```

Snapshot/restore lets you roll back partway through a broken install
without a full reinstall:

```bash
make snapshot
# ... iterate ...
make restore-snapshot
make remove          # nuke and start fresh
```

## SSO end-to-end check

`package_check` exercises install/remove/upgrade/backup/restore but
its `tests.toml` schema has no hook for custom assertions, so the
SSO header-forwarding check (SSOwat → nginx → Ahwa `Auth-User` →
`/api/me`) runs as a separate job. From the Mac:

```bash
export AHWA_TEST_USER=<a YNH login>
export AHWA_TEST_PASSWORD=<their password>
make sso-test
```

`make sso-test` flips the `ahwa.main` permission from
`visitors` → `all_users` for the duration of the test (otherwise
SSOwat doesn't intercept and `external_id` is always null), runs
[`tests/sso-e2e.sh`](./tests/sso-e2e.sh), then restores `visitors`.

The same script runs in CI via [`.github/workflows/sso-e2e.yml`](./.github/workflows/sso-e2e.yml)
on `workflow_dispatch` and on pushes that touch the install/upgrade
scripts or systemd/nginx config. Required repo secrets:
`AHWA_TEST_USER`, `AHWA_TEST_PASSWORD`, `AHWA_TEST_URL`.

## Why not LXC / package_check locally on macOS?

`package_check` uses LXC/Incus for container snapshots, which
doesn't run natively on macOS. Local iteration uses the live VPS
instead — faster feedback, real SSO/nginx integration.

## Layer 3: `package_check` (full lifecycle)

`package_check` exercises install, remove, upgrade, backup, and
restore — each in an isolated LXC container on a fresh YunoHost.
It's the source of truth for catalog quality level, and the only
thing that catches behavioral bugs lint can't (e.g., a systemd unit
that starts cleanly but blocks writes to data_dir).

Two ways to run it.

### A) Ad hoc on the VPS

Fastest for one-off checks. The VPS user must be in the
`incus-admin` group (`sudo usermod -aG incus-admin <user>`).

```bash
# One-time:
ssh vps 'git clone https://github.com/YunoHost/package_check ~/package_check'
ssh vps 'sudo ~/package_check/package_check.sh --install-dependencies'

# Each run:
make rsync-package
ssh vps '~/package_check/package_check.sh /tmp/ahwa-ynh-pkg'
```

### B) GitHub Actions self-hosted runner on the VPS

For exercising install+remove+upgrade+backup+restore in CI, via the
`package-check` job in `.github/workflows/package-check.yml`. The
job is `runs-on: [self-hosted, package-check]` (custom label,
scoped to this job only) and triggered by `workflow_dispatch` so it
queues only when explicitly requested.

#### One-time setup on the VPS

The runner runs as a dedicated `gha-runner` system user — narrow
sudo scope and no LDAP entanglement.

```bash
# 1. Create the service user and grant only the sudo it needs:
sudo useradd -r -m -d /var/lib/gha-runner -s /bin/bash gha-runner
sudo usermod -aG incus-admin gha-runner   # required for package_check
echo 'gha-runner ALL=(root) NOPASSWD: /usr/bin/yunohost' | \
  sudo EDITOR='tee' visudo -f /etc/sudoers.d/yunohost-cmnd

# 2. Get a registration token (single-use, expires in 1 hour) from:
#    https://github.com/remoun/ahwa_ynh/settings/actions/runners/new
#    Click "New self-hosted runner" → Linux x64 → copy the token

# 3. Install the runner as gha-runner:
sudo runuser -u gha-runner -- bash -c '
  cd ~ && mkdir -p actions-runner && cd actions-runner
  LATEST=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | \
    grep tag_name | cut -d"\"" -f4 | tr -d v)
  curl -O -L "https://github.com/actions/runner/releases/download/v${LATEST}/actions-runner-linux-x64-${LATEST}.tar.gz"
  tar xzf "actions-runner-linux-x64-${LATEST}.tar.gz"
  ./config.sh \
    --url https://github.com/remoun/ahwa_ynh \
    --token <TOKEN_FROM_STEP_2> \
    --labels package-check \
    --name vps-package-check \
    --unattended
'

# 4. Install the systemd service (must run from the runner dir):
( cd /var/lib/gha-runner/actions-runner && sudo ./svc.sh install gha-runner )
sudo ./svc.sh start
sudo ./svc.sh status   # confirm "active (running)"
```

#### Triggering a run

```bash
gh workflow run package-check.yml -f dist=bookworm -f ynh_branch=stable
gh run watch
```

Or via the Actions UI: `Actions → YunoHost package check → Run workflow`.

Results upload as a `package-check-results` artifact (results.json,
summary.png). Quality level ≥ 6 is the catalog-acceptance bar.

#### Operational notes

- **LXC + existing YNH services**: package_check spawns full YNH
  LXC containers. They're isolated from your live YNH services but
  consume RAM/CPU during the run — expect 30–60 minutes per full
  run on a modest VPS.
- **Trust boundary**: a self-hosted runner accepts code from the
  repo's PRs. Don't merge from untrusted forks without review —
  the `gha-runner` user can call `sudo yunohost` with no password.
  For a personal repo that's fine; for outside contributors, add a
  workflow-level approval gate via `environments` → required
  reviewers.
- **Stopping**: `sudo ~gha-runner/actions-runner/svc.sh stop && sudo
~gha-runner/actions-runner/svc.sh uninstall`, then
  `sudo runuser -u gha-runner -- ~/actions-runner/config.sh remove --token <REMOVAL_TOKEN>`.

#### Why `workflow_dispatch` only?

If we triggered on every PR, runs would queue forever when the
runner service is offline. Manual trigger respects that the runner
is opt-in infrastructure.
