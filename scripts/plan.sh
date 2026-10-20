#!/bin/bash
# Decides what to (re)build for <arch> and writes /dn/out/plan-<arch>, one
# "<package> <revision>" per line (empty: nothing to do). A package is
# rebuilt when it is not published yet, when its prepared sources differ from
# the published build (<arch>-sources), when DN_FORCE is set, or when the
# install check against the published repository and Void's current one
# finds unresolved libraries in it (one it links to got a new soname).
# A rebuild of an already published version gets the next revision, so
# installed copies update.
#
# Env: DN_PUBLISHED_URL  published repository (empty: nothing published)
#      DN_FORCE          rebuild everything
set -euo pipefail
. /dn/repo/scripts/common.sh
arch="$1"
pub="${DN_PUBLISHED_URL:-}"

/dn/repo/scripts/prepare.sh

sources="$(mktemp)"
if [ -n "$pub" ]; then
    curl -fsSL -o "$sources" "$pub/$arch-sources" || : > "$sources"
fi

declare -A why
pkgs="$(pkgs_for_arch "$arch")"
for p in $pkgs; do
    line="$(awk -v p="$p" '$1 == p' "$sources")"
    if [ -n "${DN_FORCE:-}" ]; then
        why[$p]="forced"
    elif [ -z "$line" ]; then
        why[$p]="not published"
    elif [ "$(awk '{ print $2 }' <<<"$line")" != "$(src_hash "$p")" ]; then
        why[$p]="sources changed"
    fi
done

if [ -s "$sources" ]; then
    if out="$(check_install "$arch" "$pub")"; then
        echo "$arch: install check passed"
    else
        echo "$out" | tail -20
        broken="$(sed -n 's/^\([^ ]*\): broken, unresolvable shlib.*/\1/p' <<<"$out" | sort -u)"
        hit=0
        for pkgver in $broken; do
            name="${pkgver%-*}"
            for p in $pkgs; do
                if [[ " $(published_names "$p") " == *" $name "* ]]; then
                    why[$p]="${why[$p]:-unresolved libraries}"
                    hit=1
                fi
            done
        done
        # Not caused by one of ours (Void itself mid-update, for example):
        # a rebuild would not help, so only report it
        if [ "$hit" = 0 ]; then
            echo "::warning::$arch: install check failed, not because of a DroidNative package"
        fi
    fi
fi

plan="$DN_OUT/plan-$arch"
: > "$plan"
for p in $pkgs; do
    [ -n "${why[$p]:-}" ] || continue
    ver="$(tmpl_var "$p" version)"
    rev="$(tmpl_var "$p" revision)"
    pubver="$(awk -v p="$p" '$1 == p { print $3 }' "$sources")"
    if [ "${pubver%_*}" = "$p-$ver" ] && [ "${pubver##*_}" -ge "$rev" ]; then
        rev=$((${pubver##*_} + 1))
    fi
    echo "$p $rev" >> "$plan"
    echo "$arch: $p-${ver}_$rev (${why[$p]})"
done
[ -s "$plan" ] || echo "$arch: up to date"
