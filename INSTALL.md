# Installing Deltiecord

Deltiecord 0.9.17 build 60 is a beta release for x86-64 Windows and Linux.
Download official builds from the [Deltiecord releases page](https://deltie.net/cord)
or the [GitHub release](https://github.com/vosjecleo/deltiecord/releases/tag/v0.9.17-b60).

Before installing a downloaded build, verify it against the included
`SHA256SUMS` file:

```sh
sha256sum -c SHA256SUMS
```

## Windows

### Installer

Download `Deltiecord-0.9.17-windows-x64-setup.exe`, run it, and follow the
installer. A normal per-user installation does not require administrator
privileges. The installer creates a Start Menu entry and can optionally create
a desktop shortcut.

Windows may warn about an unrecognized application because this beta is not yet
code-signed. Only continue if the filename and SHA-256 checksum match the
official release.

Upgrading or uninstalling Deltiecord does not delete Matrix sessions or other
per-user application data.

### Portable build

Download `Deltiecord-0.9.17-windows-x64-portable.zip`, extract the entire
archive, and run `deltiecord.exe` from the extracted directory. Do not move only
the executable: its accompanying DLLs, plugins, data, and assets are required.

Native Windows behavior still needs broader testing on physical Windows 10 and
11 systems. Please report platform-specific notification, secure-storage,
clipboard, drag-and-drop, audio/video device, screen-sharing, and media-playback
issues.

## Debian, Ubuntu, and Linux Mint

Download `deltiecord_0.9.17_amd64.deb`, open a terminal in its directory, and
install it with APT:

```sh
sudo apt install ./deltiecord_0.9.17_amd64.deb
```

APT installs the package and its declared runtime dependencies. Launch it from
the desktop application menu or run:

```sh
deltiecord
```

Remove the application with:

```sh
sudo apt remove deltiecord
```

Removing the package does not delete per-user Matrix sessions or application
data.

## Arch Linux

Download `deltiecord-0.9.17-1-x86_64.pkg.tar.zst` and install it with pacman:

```sh
sudo pacman -U ./deltiecord-0.9.17-1-x86_64.pkg.tar.zst
```

Launch Deltiecord from the application menu or run `deltiecord`. Remove the
package with `sudo pacman -R deltiecord`; user data remains untouched.

## AppImage

The AppImage is useful on other current x86-64 Linux distributions. Download
`Deltiecord-0.9.17-x86_64.AppImage`, make it executable, and launch it:

```sh
chmod +x Deltiecord-0.9.17-x86_64.AppImage
./Deltiecord-0.9.17-x86_64.AppImage
```

The AppImage contains the Flutter application but deliberately relies on some
ABI-sensitive desktop libraries from the host. It requires a reasonably current
GTK 3 Linux system, a working desktop Secret Service for session and E2EE-key
storage, and PulseAudio or PipeWire-Pulse for audio.

On Wayland, screen sharing requires PipeWire, `xdg-desktop-portal`, and a portal
backend for the desktop environment, such as `xdg-desktop-portal-gtk` or
`xdg-desktop-portal-kde`.

## Application data

Deltiecord stores runtime data in the operating system's normal per-user
application-data and secure-storage locations. Package upgrades and ordinary
uninstallation do not remove that data. Never copy or publish those directories:
they can contain Matrix session and encryption state.

If persisted login or E2EE storage does not work on Linux, first confirm that a
Secret Service provider such as GNOME Keyring or KWallet is installed, unlocked,
and available to the desktop session.

## Building from source

The authoritative project version is in `pubspec.yaml`. Release CI currently
pins Flutter 3.44.9 and Rust 1.97.1. Using those versions is recommended when
reproducing an official build.

Clone the repository and fetch Dart dependencies:

```sh
git clone https://github.com/vosjecleo/deltiecord.git
cd deltiecord
flutter pub get
```

Before packaging a change, run the same basic validation used by CI:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
```

### Linux source build

Linux builds require a C/C++ toolchain, CMake, Ninja, pkg-config, Rust, and the
development packages for GTK 3, libsecret, PulseAudio, ALSA, libv4l, libmpv,
and PipeWire. Debian 12 package names and the exact CI setup are documented in
[the Linux workflow](.github/workflows/linux.yml).

For a local development build:

```sh
flutter run -d linux
```

For reproducible release packages, use the packaging entry point instead of
calling `flutter build` directly:

```sh
FLUTTER_BIN="$(command -v flutter)" packaging/build-release.sh
```

It builds a Linux release, validates required native libraries, and writes the
Debian package, AppImage, checksums, and build metadata to `dist/`. On an Arch
host with `makepkg`, it also produces the native Arch package. The release
scripts apply the Rust FFI retention flag required by the current E2EE stack and
verify downloaded AppImage tooling against pinned SHA-256 hashes.

The official AppImage and Debian package are built in Debian 12 to retain a
glibc 2.36 baseline. Building them on a newer rolling distribution may produce
binaries that cannot run on Debian 12.

More packaging details are in [packaging/README.md](packaging/README.md).

### Windows source build

Install Flutter 3.44.9, Git, Rust 1.97.1, and Visual Studio with the **Desktop
development with C++** workload. Then run in PowerShell:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
flutter build windows --release
```

The complete runnable directory is written to
`build\windows\x64\runner\Release`. The executable is not standalone. Inno
Setup 6 can build the per-user installer using
`packaging\windows\deltiecord.iss`; the exact automated process is in
[the Windows workflow](.github/workflows/windows.yml).

Further Windows notes are available in [docs/WINDOWS.md](docs/WINDOWS.md).

## Getting help

Check [KNOWN_ISSUES.md](KNOWN_ISSUES.md) before reporting a problem. Useful bug
reports include the operating system and desktop environment, Deltiecord build,
homeserver implementation, whether the room is encrypted, and clear steps that
reproduce the issue. Do not include access tokens, recovery keys, decrypted
messages, encryption keys, or private media URLs in a report.
