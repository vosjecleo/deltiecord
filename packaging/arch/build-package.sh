#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
destination="$repo_root/dist"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
flutter_bin="${FLUTTER_BIN:-flutter}"

command -v makepkg >/dev/null || {
  echo 'Arch packaging requires makepkg from the pacman package.' >&2
  exit 1
}
flutter_path="$(command -v "$flutter_bin")" || {
  echo "Flutter executable not found: $flutter_bin" >&2
  exit 1
}
export PATH="$(dirname "$flutter_path"):$PATH"
mkdir -p "$destination" "$work/packages" "$work/build"
(
  cd "$repo_root/packaging/arch"
  PKGDEST="$work/packages" BUILDDIR="$work/build" \
    makepkg --cleanbuild --clean --nodeps --force
)
find "$work/packages" -maxdepth 1 -type f -name '*.pkg.tar.zst' \
  -exec cp -v -- '{}' "$destination/" \;
