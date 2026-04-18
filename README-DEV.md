<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# YunoHost packaging dev loop

This is the iteration loop for working on `packaging/yunohost/`. It's
not a guide for end users — they get [self-host.md](./self-host.md).

## Layers

Three layers, fastest first:

1. **Lint (seconds, runs on Mac).** `make lint` runs
   [package_linter](https://github.com/YunoHost/package_linter)
   against `packaging/yunohost/`. Pure Python, no Linux required.
2. **Live install on the VPS (sub-minute, runs on Mac).**
   `make deploy` rsyncs `packaging/yunohost/` to the VPS over SSH and
   triggers `yunohost app install` (or `app upgrade`). Hit the test
   URL, confirm a fresh table can be created.
3. **CI (minutes, runs in GitHub Actions).** Lint runs on every PR
   touching `packaging/yunohost/**`. Full
   [package_check](https://github.com/YunoHost/package_check)
   integration test added once the install script exists.

## One-time setup

### Passwordless sudo for `yunohost`

The deploy loop runs `sudo yunohost ...` over SSH. Sudo prompting
for a password every iteration breaks the loop. Add a NOPASSWD
rule.

**Gotcha — YNH sources sudo rules from LDAP, not just files.** The
YNH `admins` LDAP role grants `(root) ALL` (without NOPASSWD), and
LDAP rules are evaluated AFTER files. So no amount of fiddling with
`/etc/sudoers.d/` or `/etc/sudoers` itself will override it via
last-match-wins. `sudo -ll` will reveal the rule's source as
`LDAP Role: admins`. Files-only `grep` won't find it.

The fix that actually works is a per-user `Defaults` line that
disables authentication regardless of which rule (file or LDAP)
matches:

```bash
echo 'Defaults:<your-user> !authenticate' | sudo EDITOR='tee -a' visudo
sudo -k                            # clear cached timestamp first
sudo -n true && echo OK            # confirm before relying on it
```

`Defaults:user` lines apply globally for the named user, so they
override the LDAP role's authentication requirement without removing
the role itself.

### Test domain

Pick or create a subdomain like `ahwa-test.<your-domain>`. List
existing domains:

```bash
ssh vps sudo yunohost domain list
```

Add a new one if needed (point the DNS A record at the VPS first):

```bash
ssh vps sudo yunohost domain add ahwa-test.<your-domain>
```

Set it as the deploy target:

```bash
export AHWA_YNH_DOMAIN=ahwa-test.<your-domain>
export AHWA_YNH_PATH=/
```

Or pass them on each Make invocation. The Makefile reads both.

## The loop

```bash
# Edit packaging/yunohost/scripts/install (or whatever)
make -C packaging/yunohost lint        # ~1s
make -C packaging/yunohost deploy      # ~30-90s (first install slower)
make -C packaging/yunohost logs        # tail recent journal entries
```

If the install fails partway, snapshot/restore lets you roll back to
a clean state without a full reinstall:

```bash
make -C packaging/yunohost snapshot    # before risky changes
# ... iterate ...
make -C packaging/yunohost restore-snapshot
```

To start fresh:

```bash
make -C packaging/yunohost remove
```

## Why not LXC / package_check locally on macOS?

`package_check` uses LXC/Incus for container snapshots, which doesn't
run natively on macOS. Local iteration uses the live VPS install
instead — faster feedback, real SSO/nginx integration.

## Layer 3: `package_check` (full lifecycle)

`package_check` exercises install, remove, upgrade, backup, and
restore — each in an isolated LXC container on a fresh YunoHost.
It's the source of truth for catalog quality level, and the only
thing that catches behavioral bugs lint can't (e.g., a systemd unit
that starts cleanly but blocks writes to data_dir).

Two ways to run it.

### A) Ad hoc on the VPS

Fastest for one-off checks. The VPS has the lxd group already.

```bash
# One-time:
ssh vps 'git clone https://github.com/YunoHost/package_check ~/package_check'
ssh vps 'sudo ~/package_check/package_check.sh --install-dependencies'

# Each run:
make -C packaging/yunohost rsync-package
ssh vps '~/package_check/package_check.sh /tmp/ahwa-ynh-pkg'
```

### B) GitHub Actions self-hosted runner on the VPS

For exercising install+remove+upgrade+backup+restore in CI, via the
`package-check` job in `.github/workflows/yunohost.yml`. The job is
`runs-on: [self-hosted, package-check]` (custom label, scoped to
this job only) and triggered by `workflow_dispatch` so it queues
only when explicitly requested.

#### One-time setup on the VPS

```bash
# 1. Get a registration token (single-use, expires in 1 hour) from:
#    https://github.com/remoun/ahwa/settings/actions/runners/new
#    Click "New self-hosted runner" → Linux x64 → copy the token

# 2. On the VPS:
mkdir -p ~/actions-runner && cd ~/actions-runner
LATEST=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep tag_name | cut -d'"' -f4 | tr -d v)
curl -O -L "https://github.com/actions/runner/releases/download/v${LATEST}/actions-runner-linux-x64-${LATEST}.tar.gz"
tar xzf "actions-runner-linux-x64-${LATEST}.tar.gz"

# 3. Register with the package-check label so only that job uses this runner:
./config.sh \
  --url https://github.com/remoun/ahwa \
  --token <TOKEN_FROM_STEP_1> \
  --labels package-check \
  --name vps-package-check \
  --unattended

# 4. Install as a systemd service so it survives reboots:
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status   # confirm "active (running)"
```

#### Triggering a run

```bash
# From the Mac:
gh workflow run yunohost.yml -f dist=bookworm -f ynh_branch=stable
gh run watch          # follow the live log
```

Or via the Actions UI: `Actions → YunoHost → Run workflow`.

Results upload as a `package-check-results` artifact (results.json

- summary.png). Quality level ≥ 6 is the bar for catalog
  acceptance.

#### Operational notes

- **LXC + existing YNH services**: package_check spawns full YNH
  LXC containers. They're isolated from your live YNH services,
  but they DO consume RAM/CPU during the run. Expect 30-60 minutes
  per full run on a modest VPS.
- **Trust boundary**: a self-hosted runner accepts code from the
  repo's PRs. Don't merge code from untrusted forks before
  reviewing — the runner has root-equivalent access on the VPS via
  the actions-runner service user. For a personal repo this is
  fine; if you ever invite contributors, add a workflow-level
  approval gate (`environments` → required reviewers).
- **Stopping**: `sudo ~/actions-runner/svc.sh stop && sudo
~/actions-runner/svc.sh uninstall && cd ~/actions-runner &&
./config.sh remove --token <REMOVAL_TOKEN>`.

#### Why `workflow_dispatch` only?

If we triggered on every PR, runs would queue forever when the
runner service is offline. Manual trigger respects that the runner
is opt-in infrastructure.
