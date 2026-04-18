#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# End-to-end SSO assertion: confirms SSOwat → nginx → Ahwa header
# forwarding works against an installed instance.
#
# Usage:
#   tests/sso-e2e.sh <app-url> <ynh-user> <ynh-password>
#
# Example:
#   tests/sso-e2e.sh https://ahwa-test.remoun.dev/ alice secret123
#
# Exits 0 on PASS, 1 on FAIL. Designed to run from the Mac (against
# the live VPS install) or from CI (against the same).

set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: $0 <app-url> <ynh-user> <ynh-password>" >&2
    exit 64
fi

APP_URL="${1%/}"   # strip trailing slash
USER="$2"
PASS="$3"

# Derive the YNH portal origin from the app URL.
PORTAL="$(echo "$APP_URL" | awk -F/ '{print $1"//"$3}')"

cookie_jar="$(mktemp)"
trap 'rm -f "$cookie_jar"' EXIT

# 1. Login via the YunoHost portal API. SSOwat sets a session cookie
#    that nginx subsequently translates into the Auth-User header
#    when the cookie hits any reverse-proxied app.
login_status=$(curl -sS -o /dev/null -w '%{http_code}' \
    -c "$cookie_jar" \
    -H 'Content-Type: application/json' \
    --data "{\"credentials\":\"${USER}:${PASS}\"}" \
    -X POST \
    "${PORTAL}/yunohost/portalapi/login")

if [ "$login_status" != "200" ]; then
    echo "FAIL: portal login returned HTTP $login_status (expected 200)" >&2
    exit 1
fi

# 2. Hit /api/me with the session cookie. Expect a JSON body whose
#    external_id matches the YNH login.
me_response=$(curl -sS -b "$cookie_jar" "${APP_URL}/api/me")

# Parse external_id without jq dependency (pure POSIX shell).
external_id=$(printf '%s' "$me_response" \
    | sed -n 's/.*"external_id":"\([^"]*\)".*/\1/p')

if [ "$external_id" != "$USER" ]; then
    echo "FAIL: expected external_id='${USER}', got: ${me_response}" >&2
    exit 1
fi

echo "PASS: SSO header forwarding intact (external_id=${external_id})"
