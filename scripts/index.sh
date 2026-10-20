#!/bin/bash
# Indexes /dn/out/repo/ (all architectures in one directory, as published):
# registers every package, removes superseded ones and merges the
# <arch>-sources.new files of fresh builds into <arch>-sources. With
# DN_SIGNING_KEY (RSA private key, PEM) it signs the repository and every
# package without a .sig2: xbps only installs from remote repositories that
# are signed with a key it trusts.
set -euo pipefail
. /dn/repo/scripts/common.sh
cd "$DN_OUT/repo"

# Fresh builds replace an index entry of the same version (local rebuilds)
fresh=()
for new in *-sources.new; do
    [ -e "$new" ] || continue
    arch="${new%-sources.new}"
    while read -r p _ pkgver; do
        for n in $(published_names "$p"); do
            f="$n-${pkgver#"$p"-}.$arch.xbps"
            [ -e "$f" ] && fresh+=("$PWD/$f")
        done
    done < "$new"
    old="${new%.new}"
    touch "$old"
    awk 'NR == FNR { fresh[$1] = 1; print; next } !($1 in fresh)' "$new" "$old" |
        sort > "$old.tmp"
    mv "$old.tmp" "$old"
    rm -- "$new"
done

for arch in $(ls ./*.xbps 2>/dev/null | sed 's/.*\.\([^.]*\)\.xbps$/\1/' | sort -u); do
    # Without -f the newest version of each package wins
    XBPS_TARGET_ARCH="$arch" xbps-rindex -a "$PWD"/*."$arch".xbps
    for f in "${fresh[@]}"; do
        if [[ "$f" == *".$arch.xbps" ]]; then
            XBPS_TARGET_ARCH="$arch" xbps-rindex -f -a "$f"
        fi
    done
    XBPS_TARGET_ARCH="$arch" xbps-rindex -r "$PWD"
    if [ -n "${DN_SIGNING_KEY:-}" ]; then
        XBPS_TARGET_ARCH="$arch" xbps-rindex --signedby DroidNative \
            --privkey "$DN_SIGNING_KEY" -s "$PWD" >/dev/null
        unsigned=()
        for f in "$PWD"/*."$arch".xbps; do
            # Fresh builds may reuse a name (local rebuilds): sign them again
            if [ ! -e "$f.sig2" ] || printf '%s\n' "${fresh[@]}" | grep -qxF "$f"; then
                unsigned+=("$f")
            fi
        done
        if [ ${#unsigned[@]} -gt 0 ]; then
            XBPS_TARGET_ARCH="$arch" xbps-rindex --privkey "$DN_SIGNING_KEY" -S "${unsigned[@]}" >/dev/null
        fi
    fi
    echo "$arch: $(ls ./*."$arch".xbps | wc -l) packages"
done
