#!/bin/bash
# Dry-run install of every published package of <arch> into an empty root,
# from <repo> (default /dn/out/repo) and Void's current repository.
# Usage: check.sh <arch> [repo]
set -euo pipefail
. /dn/repo/scripts/common.sh
arch="$1"
repo="${2:-/dn/out/repo}"
if out="$(check_install "$arch" "$repo")"; then
    names=""
    for p in $(pkgs_for_arch "$arch"); do names="$names $(published_names "$p")"; done
    for n in $names; do grep -E "^$n-[^-]+_[0-9]+ " <<<"$out" || true; done
    echo "$arch: $(wc -l <<<"$out") packages resolve"
else
    echo "$out"
    exit 1
fi
