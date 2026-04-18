#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Wraps tests/sso-e2e.sh with the permission flip the test needs.
# SSOwat only intercepts when 'visitors' is NOT a member of the app's
# main permission, so we flip ahwa.main visitors -> all_users for the
# duration of the test, then restore visitors regardless of outcome.
#
# Usage:
#   tests/run-sso-test.sh <ssh-cmd> <app-id> <app-url> <ynh-user> <ynh-password>
#
# <ssh-cmd> is the verbatim ssh prefix used to reach the YNH host
# (e.g. "ssh -tt vps"); use "" to run the yunohost commands locally.

set -euo pipefail

if [ $# -ne 5 ]; then
    echo "usage: $0 <ssh-cmd> <app-id> <app-url> <ynh-user> <ynh-password>" >&2
    exit 64
fi

SSH_CMD="$1"
APP="$2"
APP_URL="$3"
USER="$4"
PASS="$5"

run_remote() {
    if [ -n "$SSH_CMD" ]; then
        # shellcheck disable=SC2086 # $SSH_CMD intentionally word-splits
        $SSH_CMD "$1"
    else
        bash -c "$1"
    fi
}

restore_visitors() {
    run_remote "sudo yunohost user permission remove ${APP}.main all_users; sudo yunohost user permission add ${APP}.main visitors" >/dev/null 2>&1 || true
}
trap restore_visitors EXIT

run_remote "sudo yunohost user permission remove ${APP}.main visitors"
run_remote "sudo yunohost user permission add ${APP}.main all_users"

# The script's exit code becomes our exit code; trap restores perms either way.
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "${HERE}/sso-e2e.sh" "$APP_URL" "$USER" "$PASS"
