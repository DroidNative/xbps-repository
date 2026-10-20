#!/bin/bash
# Builds packages for <arch> with xbps-src and copies the results to
# /dn/out/repo/: the main package and its subpackages from packages.conf,
# plus <arch>-sources.new ("<package> <source hash> <pkgver>").
#
# Usage: build.sh <arch> [pkg...]     default: all packages of <arch>
#        build.sh -p <arch>           packages and revisions of plan-<arch>
# Env:   DN_CLEAN  clean each package's build directories first
set -euo pipefail
. /dn/repo/scripts/common.sh

use_plan=0
[ "${1:-}" = -p ] && { use_plan=1; shift; }
arch="$1"; shift

/dn/repo/scripts/prepare.sh

declare -A revs
if [ "$use_plan" = 1 ]; then
    while read -r p r; do revs[$p]="$r"; done < "$DN_OUT/plan-$arch"
else
    for p in ${@:-$(pkgs_for_arch "$arch")}; do revs[$p]=""; done
fi
[ ${#revs[@]} -gt 0 ] || { echo "$arch: nothing to build"; exit 0; }

# The masterdir lives on a volume: bootstrap once, then keep it in step with
# the void-packages checkout of this image
if [ ! -e masterdir/.xbps_chroot_init ]; then
    ./xbps-src -m masterdir binary-bootstrap
else
    ./xbps-src -m masterdir bootstrap-update
fi

# The image is x86_64: build natively for it, cross-compile everything else
cross=(-a "$arch")
[ "$arch" = x86_64 ] && cross=()

mkdir -p "$DN_OUT/repo"
newsrc="$DN_OUT/repo/$arch-sources.new"
: > "$newsrc"
for p in "${!revs[@]}"; do
    hash="$(src_hash "$p")"   # before the revision change
    [ -n "${revs[$p]}" ] && sed -i "s/^revision=.*/revision=${revs[$p]}/" "srcpkgs/$p/template"
    pkgver="$p-$(tmpl_var "$p" version)_$(tmpl_var "$p" revision)"
    [ -n "${DN_CLEAN:-}" ] && ./xbps-src -m masterdir "${cross[@]}" clean "$p"
    ./xbps-src -m masterdir "${cross[@]}" -f pkg "$p"
    for n in $(published_names "$p"); do
        cp "hostdir/binpkgs/$n-${pkgver#"$p"-}.$arch.xbps" "$DN_OUT/repo/"
    done
    echo "$p $hash $pkgver" >> "$newsrc"
    echo "$arch: built $pkgver"
done
