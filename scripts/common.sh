# Shared helpers of the container scripts (sourced; cwd is the void-packages
# checkout). /dn/repo is this repository, /dn/out the output directory.
DN_REPO=/dn/repo
DN_OUT=/dn/out
VOID_MIRROR="${VOID_MIRROR:-https://repo-default.voidlinux.org}"

# packages.conf without comments and blank lines
conf() { grep -v -E '^[[:space:]]*(#|$)' "$DN_REPO/packages.conf"; }

pkgs_for_arch() {
    conf | awk -v a="$1" '{ n = split($2, x, ","); for (i = 1; i <= n; i++) if (x[i] == a) print $1 }'
}

subpkgs_of() {
    conf | awk -v p="$1" '$1 == p && $3 != "" { gsub(",", " ", $3); print $3 }'
}

# Main package and published subpackages
published_names() { echo "$1" $(subpkgs_of "$1"); }

# Literal assignment from a template (version=, revision=)
tmpl_var() { sed -n "s/^$2=//p" "srcpkgs/$1/template" | head -1; }

# Content hash of a prepared package directory (decides about rebuilds)
src_hash() {
    (cd "srcpkgs/$1" && find . -type f | LC_ALL=C sort | xargs -d '\n' sha256sum) |
        sha256sum | cut -d' ' -f1
}

# Void's repository for an architecture (glibc)
void_repo() {
    case "$1" in
        aarch64) echo "$VOID_MIRROR/current/aarch64" ;;
        *) echo "$VOID_MIRROR/current" ;;
    esac
}

# xbps-install -n of every published package of <arch> into an empty root,
# with <repo> (URL or directory) before Void's repository, as on the phone.
# Prints the transaction or the error; the status is xbps-install's.
check_install() {
    local arch="$1" repo="$2" root pkgs="" p
    root="$(mktemp -d)"
    mkdir -p "$root/var/db/xbps/keys"
    cp /var/db/xbps/keys/* "$root/var/db/xbps/keys/"
    for p in $(pkgs_for_arch "$arch"); do pkgs="$pkgs $(published_names "$p")"; done
    local r=(-r "$root" -R "$repo" -R "$(void_repo "$arch")")
    # Accepts the signing key of <repo>: xbps asks for it on stdin
    yes | XBPS_ARCH="$arch" xbps-install -S "${r[@]}" >/dev/null 2>&1 || true
    XBPS_ARCH="$arch" xbps-install -n "${r[@]}" $pkgs 2>&1
}
