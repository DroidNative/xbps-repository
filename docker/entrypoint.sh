#!/bin/bash
# Runs inside the build container: entrypoint.sh <command> [args...]
# runs scripts/<command>.sh of the repository mounted at /dn/repo.
set -euo pipefail
cmd="$1"; shift
[ -x "/dn/repo/scripts/$cmd.sh" ] || { echo "unknown command: $cmd" >&2; exit 2; }
exec "/dn/repo/scripts/$cmd.sh" "$@"
