# SPDX-License-Identifier: AGPL-3.0-or-later
#
# YunoHost packaging dev loop. See docs/yunohost-dev.md.
#
# Required env vars:
#   AHWA_YNH_DOMAIN  - the test domain (e.g. ahwa-test.example.com)
#
# Optional:
#   AHWA_YNH_HOST    - SSH alias for the VPS (default: vps)
#   AHWA_YNH_PATH    - install path (default: /)
#   AHWA_YNH_APP     - app id on the YNH instance (default: ahwa)

AHWA_YNH_HOST ?= vps
AHWA_YNH_PATH ?= /
AHWA_YNH_APP  ?= ahwa

REMOTE_DIR := /tmp/ahwa-ynh-pkg
# -tt forces TTY allocation. yunohost CLI prompts for confirmation
# in some paths and refuses to run otherwise ("Not a tty, can't do
# interactive prompts"). --force on app install handles most cases
# but not all (e.g., domain warnings).
SSH := ssh -tt $(AHWA_YNH_HOST)

# Cache lives outside the repo so the linter doesn't recurse into its
# own source (would trigger false positives on linter-internal
# placeholder strings) and so nothing extra needs to be gitignored.
LINTER_DIR := $(HOME)/.cache/ahwa-yunohost-linter
LINTER     := $(LINTER_DIR)/package_linter.py

.PHONY: help lint deploy install upgrade remove logs status snapshot restore-snapshot domain-list sso-test

help:
	@echo "Targets:"
	@echo "  lint              run package_linter (no remote calls)"
	@echo "  deploy            rsync + install-or-upgrade on the VPS"
	@echo "  install           rsync + fresh install (removes first if exists)"
	@echo "  upgrade           rsync + in-place upgrade"
	@echo "  remove            uninstall the app from the VPS"
	@echo "  logs              tail systemd journal for the app"
	@echo "  status            yunohost app info"
	@echo "  snapshot          create a YNH backup of the app"
	@echo "  restore-snapshot  restore from latest snapshot"
	@echo "  domain-list       list domains on the VPS"
	@echo "  sso-test          run end-to-end SSO check against the VPS install"
	@echo "                    (requires AHWA_TEST_USER + AHWA_TEST_PASSWORD)"

# --- Layer 1: lint -----------------------------------------------------

$(LINTER):
	@mkdir -p $(LINTER_DIR)
	@git clone --depth 1 https://github.com/YunoHost/package_linter.git $(LINTER_DIR)
	@python3 -m venv $(LINTER_DIR)/.venv
	@$(LINTER_DIR)/.venv/bin/pip install -q -r $(LINTER_DIR)/requirements.txt

lint: $(LINTER)
	@if [ ! -f manifest.toml ]; then \
	  echo "lint: skipped (no manifest.toml yet — write it first, then rerun)"; \
	  exit 0; \
	fi; \
	OUT=$$($(LINTER_DIR)/.venv/bin/python3 $(LINTER) . 2>&1); \
	echo "$$OUT"; \
	NON_CATALOG=$$(echo "$$OUT" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "^\s*✘[^✘]" | wc -l); \
	if [ "$$NON_CATALOG" -gt 0 ]; then \
	  echo "lint: $$NON_CATALOG non-catalog critical issue(s) — see above"; \
	  exit 1; \
	fi; \
	echo "lint: ok (catalog-membership warning is expected until we submit)"

# --- Layer 2: deploy to VPS --------------------------------------------

require-domain:
	@test -n "$(AHWA_YNH_DOMAIN)" || \
	  (echo "AHWA_YNH_DOMAIN is required (e.g. export AHWA_YNH_DOMAIN=ahwa-test.example.com)"; exit 1)

rsync-package:
	@rsync -az --delete \
	  --exclude='.cache' \
	  --exclude='Makefile' \
	  ./ $(AHWA_YNH_HOST):$(REMOTE_DIR)/

deploy: require-domain rsync-package
	@# Use plain ssh (no -tt) for the existence probe so it doesn't taint the loop.
	@if ssh $(AHWA_YNH_HOST) 'sudo yunohost app info $(AHWA_YNH_APP) >/dev/null 2>&1'; then \
	  $(MAKE) upgrade; \
	else \
	  $(SSH) 'sudo yunohost app install $(REMOTE_DIR) \
	    --force \
	    --label "Ahwa (test)" \
	    --args "domain=$(AHWA_YNH_DOMAIN)&path=$(AHWA_YNH_PATH)&init_main_permission=visitors"'; \
	fi

install: require-domain rsync-package
	@$(SSH) 'sudo yunohost app remove $(AHWA_YNH_APP) 2>/dev/null; \
	  sudo yunohost app install $(REMOTE_DIR) \
	    --label "Ahwa (test)" \
	    --args "domain=$(AHWA_YNH_DOMAIN)&path=$(AHWA_YNH_PATH)&init_main_permission=visitors"'

upgrade: rsync-package
	@$(SSH) 'sudo yunohost app upgrade $(AHWA_YNH_APP) -f $(REMOTE_DIR) --force'

remove:
	@$(SSH) 'sudo yunohost app remove $(AHWA_YNH_APP)'

logs:
	@$(SSH) 'sudo journalctl -u $(AHWA_YNH_APP) -n 80 --no-pager'

status:
	@$(SSH) 'sudo yunohost app info $(AHWA_YNH_APP)'

snapshot:
	@$(SSH) 'sudo yunohost backup create --apps $(AHWA_YNH_APP) --name $(AHWA_YNH_APP)-snapshot'

restore-snapshot:
	@$(SSH) 'sudo yunohost backup restore $(AHWA_YNH_APP)-snapshot --apps $(AHWA_YNH_APP) --force'

domain-list:
	@$(SSH) 'sudo yunohost domain list'

# --- SSO end-to-end ----------------------------------------------------
#
# Flips the ahwa.main permission from visitors → all_users for the
# duration of the test (otherwise SSOwat doesn't intercept and external_id
# is always null), runs tests/sso-e2e.sh, then restores visitors.

sso-test: require-domain
	@test -n "$(AHWA_TEST_USER)"     || (echo "AHWA_TEST_USER is required";     exit 1)
	@test -n "$(AHWA_TEST_PASSWORD)" || (echo "AHWA_TEST_PASSWORD is required"; exit 1)
	@$(SSH) 'sudo yunohost user permission update $(AHWA_YNH_APP).main --remove visitors --add all_users'
	@bash tests/sso-e2e.sh \
	  "https://$(AHWA_YNH_DOMAIN)$(AHWA_YNH_PATH)" \
	  "$(AHWA_TEST_USER)" \
	  "$(AHWA_TEST_PASSWORD)"; \
	  rc=$$?; \
	  $(SSH) 'sudo yunohost user permission update $(AHWA_YNH_APP).main --add visitors --remove all_users' >/dev/null; \
	  exit $$rc
