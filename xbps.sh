#!/usr/bin/env bash
# Runs the package build in Docker (docker/, scripts/). Output: out/repo/,
# an xbps repository for all architectures in one directory.
#
# Usage: ./xbps.sh build [-a arch] [-c] [pkg...]  build (default: all of arch)
#        ./xbps.sh build -p -a arch                build what out/plan-<arch> says
#        ./xbps.sh plan <arch>                     write out/plan-<arch>
#        ./xbps.sh index                           index out/repo
#        ./xbps.sh check <arch> [repo]             dry-run install check
#        ./xbps.sh keygen <dir>                    signing key + trusted key file
# Env:   VOID_PACKAGES_REF  void-packages commit or branch (default master)
#        DN_APP_SRC         DroidNativeApp checkout for the droidnative-tools
#                           sources (default: latest guest-tools/ on GitHub)
#        DN_SIGNING_KEY     private key (PEM): index signs the repository
#        DN_PUBLISHED_URL, DN_FORCE (plan), GITHUB_TOKEN (GitHub API)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="droidnative/xbps-builder:latest"
OUT="$ROOT/out"

image() {
    local ref="${VOID_PACKAGES_REF:-master}"
    # Branch names become a commit, so the layer cache never goes stale
    if ! [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
        ref="$(git ls-remote https://github.com/void-linux/void-packages.git "refs/heads/$ref" | cut -f1)"
        [ -n "$ref" ] || { echo "unknown void-packages branch" >&2; exit 1; }
    fi
    docker build -q --build-arg VOID_PACKAGES_REF="$ref" -t "$IMAGE" "$ROOT/docker" >/dev/null
}

run() {
    local mounts=(-v "$ROOT:/dn/repo:ro" -v "$OUT:/dn/out")
    [ -n "${DN_APP_SRC:-}" ] && mounts+=(-v "$(cd "$DN_APP_SRC" && pwd):/dn/app:ro")
    local key=""
    if [ -n "${DN_SIGNING_KEY:-}" ]; then
        mounts+=(-v "$(realpath "$DN_SIGNING_KEY"):/dn/signing.pem:ro")
        key=/dn/signing.pem
    fi
    mkdir -p "$OUT/repo"
    docker run --rm --privileged --network host \
        -e DN_CLEAN="${DN_CLEAN:-}" -e DN_FORCE="${DN_FORCE:-}" \
        -e DN_PUBLISHED_URL="${DN_PUBLISHED_URL:-}" -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
        -e DN_SIGNING_KEY="$key" \
        -v dn-xbps-masterdir:/home/builder/void-packages/masterdir \
        -v dn-xbps-hostdir:/home/builder/void-packages/hostdir \
        "${mounts[@]}" "$IMAGE" "$@"
}

# RSA key pair for signing (xbps-signing.pem, keep it secret) and the file
# xbps keeps for a trusted key (<fingerprint>.plist; the app installs it into
# /var/db/xbps/keys). The fingerprint is the MD5 one of ssh-keygen.
keygen() {
    local dir="$1" key pub fp
    mkdir -p "$dir"
    key="$dir/xbps-signing.pem"
    if [ ! -e "$key" ]; then
        (umask 077; openssl genrsa -out "$key" 4096 2>/dev/null)
    fi
    pub="$(openssl rsa -in "$key" -pubout 2>/dev/null)"
    fp="$(ssh-keygen -l -E md5 -f <(ssh-keygen -i -m PKCS8 -f <(echo "$pub")) |
        awk '{ print $2 }' | sed 's/^MD5://')"
    cat > "$dir/$fp.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>public-key</key>
	<data>$(echo "$pub" | base64 -w0)</data>
	<key>public-key-size</key>
	<integer>4096</integer>
	<key>signature-by</key>
	<string>DroidNative</string>
</dict>
</plist>
PLIST
    echo "private key: $key"
    echo "trusted key: $dir/$fp.plist"
}

cmd="${1:-}"; shift || true
case "$cmd" in
    build)
        arch=aarch64 plan=()
        while getopts "a:cp" opt; do
            case "$opt" in
                a) arch="$OPTARG" ;;
                c) export DN_CLEAN=1 ;;
                p) plan=(-p) ;;
                *) exit 2 ;;
            esac
        done
        shift $((OPTIND - 1))
        image
        run build "${plan[@]}" "$arch" "$@"
        [ ${#plan[@]} -gt 0 ] || run index
        ;;
    plan) image; run plan "$@" ;;
    index) image; run index ;;
    check) image; run check "$@" ;;
    keygen) [ $# -eq 1 ] || exit 2; keygen "$1" ;;
    *) sed -n 's/^# \{0,1\}//; 2,/^set /p' "$0" | sed '$d' >&2; exit 2 ;;
esac
