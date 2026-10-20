#!/bin/bash
# Puts DroidNative's templates into the void-packages checkout: srcpkgs/* as
# they are, overlays/* applied on top of Void's template of the same name,
# and the droidnative-tools sources from DroidNativeApp (guest-tools/ of the
# latest commit that changed it, or of the checkout mounted at /dn/app).
set -euo pipefail
. /dn/repo/scripts/common.sh

APP_REPO="${DN_APP_REPO:-DroidNative/DroidNativeApp}"
APP_BRANCH="${DN_APP_BRANCH:-main}"
APP_PATH="${DN_APP_PATH:-guest-tools}"

for t in "$DN_REPO"/srcpkgs/*/; do
    name="$(basename "$t")"
    mkdir -p "srcpkgs/$name"
    cp -r "$t/." "srcpkgs/$name/"
done

for o in "$DN_REPO"/overlays/*/; do
    name="$(basename "$o")"
    tmpl="srcpkgs/$name/template"
    [ -f "$tmpl" ] || { echo "overlay $name: Void has no such package" >&2; exit 1; }
    offset="$(sed -n 's/^revision_offset=//p' "$o/overlay.conf")"
    rev="$(tmpl_var "$name" revision)"
    sed -i "s/^revision=.*/revision=$((rev + offset))/" "$tmpl"
    if [ -d "$o/patches" ]; then
        mkdir -p "srcpkgs/$name/patches"
        cp "$o"/patches/* "srcpkgs/$name/patches/"
    fi
    { printf '\n# DroidNative overlay (xbps-repository/overlays/%s)\n' "$name"
      cat "$o/template.append"; } >> "$tmpl"
done

# droidnative-tools sources
files=srcpkgs/droidnative-tools/files
mkdir -p "$files"
if [ -d /dn/app/guest-tools ]; then
    cp /dn/app/guest-tools/* "$files/"
    echo "droidnative-tools: sources from the local checkout" >&2
else
    auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    api="https://api.github.com/repos/$APP_REPO"
    commit="$(curl -fsSL "${auth[@]}" "$api/commits?sha=$APP_BRANCH&path=$APP_PATH&per_page=1" |
        grep -o -m1 '"sha": *"[0-9a-f]\{40\}"' | grep -o '[0-9a-f]\{40\}' || true)"
    [ -n "$commit" ] || { echo "no $APP_PATH/ in $APP_REPO@$APP_BRANCH" >&2; exit 1; }
    listing="$(curl -fsSL "${auth[@]}" "$api/contents/$APP_PATH?ref=$commit")"
    if grep -q '"type": *"dir"' <<<"$listing"; then
        echo "$APP_PATH/ has subdirectories, prepare.sh only copies files" >&2; exit 1
    fi
    for url in $(grep -o '"download_url": *"[^"]*"' <<<"$listing" | cut -d'"' -f4); do
        curl -fsSL -o "$files/${url##*/}" "$url"
    done
    echo "droidnative-tools: sources from $APP_REPO@${commit:0:12}" >&2
fi
