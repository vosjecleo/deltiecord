# Linux release packaging

## Automated publication

After committing a clean, versioned release on `main`, run:

```sh
packaging/publish-release.sh --channel latest
```

Use `stable` or `both` to select the deltie.net channel. `--clear-stable`
removes all stable-channel entries without deleting historical artifacts;
`--install-host` installs the verified Debian package locally. The script runs
the full preflight, pushes `main` and the
version tag to GitHub and the Deltie mirror, waits for the existing GitHub
Actions platform builds, verifies the exact nine-artifact checksum set, then
stages and atomically publishes it to deltie.net. This removes the repeated
manual download/upload work; the platform compilation time still belongs to
CI. `--skip-preflight` exists for a retry only after the same commit has already
passed the complete local preflight.

Run `FLUTTER_BIN=/path/to/flutter packaging/build-release.sh` from the
repository root. GIF search uses Deltiecord's HTTPS proxy; the GIPHY key exists
only on that server and is never compiled into release binaries.
The script creates the Debian package, AppImage, checksums, and build metadata in
`dist/`. On Arch hosts with `makepkg`, it also creates a native
`.pkg.tar.zst`. Generated artifacts and downloaded packaging tools are
intentionally ignored by Git.

Use the release script rather than invoking `flutter build` directly. It also
applies the release-only Rust FFI retention flag required by the current
flutter_vodozemac dependency.

Install the Debian package with `sudo apt install ./dist/deltiecord-0.9.27+92-linux-debian-amd64.deb`.
The package removes only application files when uninstalled; Matrix/session data
remains in the user's normal XDG application-data and Secret Service stores.

Run the AppImage with `chmod +x dist/deltiecord-0.9.27+92-linux-appimage-x86_64.AppImage` followed by
`./dist/deltiecord-0.9.27+92-linux-appimage-x86_64.AppImage`. A working desktop Secret Service is
required for persisted login and E2EE keys. Audio requires a reachable PulseAudio
or PipeWire-Pulse service. Wayland screen sharing requires PipeWire,
`xdg-desktop-portal`, and a working desktop portal backend such as
`xdg-desktop-portal-gtk` or `xdg-desktop-portal-kde`. The AppImage is assembled
with linuxdeploy. Official x86_64 artifacts are built inside Debian 12 so native
plugins retain a glibc 2.36 baseline; building them directly on a newer rolling
distribution produces packages that may not start on Debian.

The Debian 12 build environment needs Flutter plus `clang`, `cmake`, `make`, `ninja`,
`pkg-config`, `fakeroot`, `patchelf`, and the development packages for GTK 3,
libsecret, PulseAudio, ALSA, libv4l, libmpv, and PipeWire. `appstreamcli validate
packaging/linux/net.deltie.deltiecord.metainfo.xml` validates the desktop
metadata before packaging.

Flutter 3.44.9, rustup 1.29.0, and Rust 1.97.1 are pinned in CI. Downloaded
Flutter/rustup/AppImage executables are verified against committed SHA-256
values before execution. Cargokit's `stable` toolchain name is locally aliased
to the pinned Rust toolchain so a build cannot silently advance to a new Rust
release.

The Arch recipe is in `packaging/arch/PKGBUILD` and intentionally builds from the
local checkout so it can be used for test packages before a public source release.
Run `FLUTTER_BIN=/path/to/flutter packaging/arch/build-package.sh` through a
shell whose `PATH` contains that Flutter SDK to create the package in `dist/`.
