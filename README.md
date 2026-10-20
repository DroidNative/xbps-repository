# DroidNative xbps repository

Void Linux packages DroidNative installs into its guest: Turnip for Adreno
on KGSL, Mesa with the Zink/kopper patch, the Flatpak GL extension, gl4es
and `droidnative-tools`. Void is rolling, so a GitHub workflow keeps the
published repository installable against Void's current one.

Repository URL (what DroidNative's `DN_XBPS_REPO` points at):
`https://github.com/DroidNative/xbps-repository/releases/download/current`

## Layout

- `packages.conf`: packages, architectures and published subpackages.
- `srcpkgs/`: DroidNative's own templates. `droidnative-tools` takes its
  sources from `guest-tools/` of DroidNativeApp (latest commit on `main`
  that changed it).
- `overlays/<pkg>/`: changes to a Void package (currently `mesa`), applied
  to Void's template at build time: `patches/` is added, `template.append`
  appended, and the revision raised by `revision_offset` so this build
  supersedes Void's.
- `scripts/`: run inside the build container (`prepare`, `plan`, `build`,
  `index`, `check`).

## Automatic builds

`.github/workflows/build.yml` runs every 6 hours, on pushes and manually.
`scripts/plan.sh` rebuilds a package when it is not published, when its
prepared sources changed (overlays follow Void's template, so a Mesa update
in Void counts) or when a dry-run install against Void finds unresolved
libraries. A rebuild of a published version gets the next revision. Results
go to the release `current` (`<arch>-repodata`, packages, `<arch>-sources`).

## Signing

xbps installs only from signed remote repositories, and DroidNative ships
the trusted key because xbps cannot ask about a new one without a
terminal. One-time setup:

```
./xbps.sh keygen keys/        # keys/xbps-signing.pem + keys/<fingerprint>.plist
```

- Store the content of `xbps-signing.pem` as the repository secret
  `XBPS_SIGNING_KEY` (Settings, Secrets and variables, Actions), then
  delete the file (`keys/` is ignored by git).
- Copy `<fingerprint>.plist` to DroidNativeApp's
  `app/src/main/assets/xbps-keys/` and commit it there.

## Building locally

Needs Docker (the container runs privileged, for xbps-src's chroot).

```
./xbps.sh build -a aarch64             # all aarch64 packages -> out/repo/
DN_APP_SRC=../DroidNativeApp ./xbps.sh build -a x86_64 droidnative-tools
./xbps.sh check aarch64                # dry-run install against Void
```

`-c` cleans a package's build directories first (after a failed build).
To try a local build on a phone, sign it (`DN_SIGNING_KEY=<pem>`, a key
of your own from `keygen` works), serve it with
`python3 -m http.server -d out/repo 8000` plus
`adb reverse tcp:8000 tcp:8000`, and build the app with
`DN_XBPS_REPO=http://127.0.0.1:8000 DN_XBPS_KEY=<fingerprint>.plist`.
