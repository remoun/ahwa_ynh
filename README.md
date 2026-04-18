<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Ahwa for YunoHost

[Read this in French / Lire en français](./README_fr.md)

YunoHost packaging for [Ahwa](https://github.com/remoun/ahwa) — private
AI deliberation rooms. Convene a small council of AI personas to think
through a dilemma that doesn't fit a one-shot answer.

This repo holds the YNH packaging only. The application code lives in
the upstream repo at <https://github.com/remoun/ahwa>; the install
script clones from there at install time.

## Install

Until this package lands in the official YunoHost catalog, install
directly from the GitHub URL:

```bash
sudo yunohost app install https://github.com/remoun/ahwa_ynh
```

## What you'll need

- One LLM provider key, set after install via the YNH webadmin or by
  editing `/var/www/ahwa/.env`. See the
  [self-hosting guide](https://github.com/remoun/ahwa/blob/main/docs/self-host.md#llm-providers)
  for the full env var table.
- Roughly 300 MB disk + 256 MB RAM at runtime. Build (during install)
  needs ~1 GB RAM transiently.

## Working on the package

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the local iteration loop
(linter, live VPS install, package_check).

## Upstream

- App: <https://github.com/remoun/ahwa>
- Issues that aren't YNH-specific: <https://github.com/remoun/ahwa/issues>
- Issues with this packaging: <https://github.com/remoun/ahwa_ynh/issues>

License: AGPL-3.0-or-later (matches the upstream).
