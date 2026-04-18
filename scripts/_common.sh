#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later

# Shared helpers for the Ahwa YunoHost package. Sourced by every
# install/remove/upgrade/backup/restore script.

# Read the pinned Bun version from the repo's canonical .bun-version
# file (also consumed by the Dockerfile build-arg). Single source of
# truth so YNH installs and Docker builds stay in lockstep — bumping
# the file in one PR updates every deployment path.
read_bun_version() {
    local install_dir="$1"
    local f="$install_dir/src/.bun-version"
    if [ ! -f "$f" ]; then
        ynh_die --message="missing $f — repo is out of sync with this packaging"
    fi
    tr -d '[:space:]' < "$f"
}

# Install Bun into the per-app install_dir. Vendoring Bun per-app keeps
# YNH backup/restore self-contained and avoids depending on a system
# Bun that an admin might upgrade or remove behind our back.
install_bun() {
    local install_dir="$1"
    local version
    version="$(read_bun_version "$install_dir")"
    export BUN_INSTALL="$install_dir/.bun"
    # The Bun installer reads $HOME to update shell rc files. YNH scripts
    # run with `set -u`, and HOME isn't set in the install context, so the
    # installer trips on "HOME: unbound variable". Pin HOME to the install
    # dir — Bun's rc-file edits land in $install_dir/.bashrc which we don't
    # care about anyway.
    export HOME="$install_dir"
    mkdir -p "$BUN_INSTALL"
    curl -fsSL "https://bun.sh/install" | bash -s "bun-v${version}"
}

# Path to the bun binary inside an install_dir.
bun_bin() {
    local install_dir="$1"
    echo "$install_dir/.bun/bin/bun"
}

# Run the vendored bun as the app user, with cwd at $install_dir/src.
# Replaces three-line pushd/run/popd dances at every call site:
#
#     bun_app "install --frozen-lockfile"
#     bun_app "run build"
#
# The first arg is the install_dir; remaining args are passed through
# to bun verbatim. ynh_exec_as_app drops privileges to the system user
# YNH provisioned via [resources.system_user] in the manifest.
bun_app() {
    local install_dir="$1"
    shift
    pushd "$install_dir/src" >/dev/null || ynh_die --message="cannot enter $install_dir/src"
    ynh_exec_as_app "$install_dir/.bun/bin/bun" "$@"
    popd >/dev/null || true
}
