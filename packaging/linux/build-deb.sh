#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$repo_root/pubspec.yaml")"
dist="$repo_root/dist"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
root="$work/root"

"$repo_root/packaging/linux/build-appdir.sh" "$root"
unlink "$root/usr/bin/deltiecord"
install -m 0755 "$repo_root/packaging/linux/deltiecord-launcher" \
  "$root/usr/bin/deltiecord"
install -d "$root/DEBIAN"
cat >"$root/DEBIAN/control" <<EOF
Package: deltiecord
Version: $version
Section: net
Priority: optional
Architecture: amd64
Maintainer: Deltiecord contributors
Depends: libc6, libgtk-3-0 | libgtk-3-0t64, libsecret-1-0, libpulse0, libasound2, libv4l-0, libmpv2 | libmpv1, libpipewire-0.3-0, xdg-desktop-portal
Recommends: xdg-desktop-portal-gtk | xdg-desktop-portal-kde | xdg-desktop-portal-gnome
Description: Compact Matrix desktop client
 Deltiecord is a dense, old-school desktop client for Matrix.
EOF
install -d "$dist"
output="$dist/deltiecord_${version}_amd64.deb"
if command -v dpkg-deb >/dev/null; then
  fakeroot dpkg-deb --build --root-owner-group "$root" "$output"
else
  (cd "$root" && fakeroot tar --owner=0 --group=0 -czf "$work/data.tar.gz" --exclude=DEBIAN .)
  (cd "$root/DEBIAN" && fakeroot tar --owner=0 --group=0 -czf "$work/control.tar.gz" .)
  printf '2.0\n' >"$work/debian-binary"
  (cd "$work" && ar r "$output" debian-binary control.tar.gz data.tar.gz)
fi
echo "$output"
