#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
cd "$repo_root"
rm -rf dist
mkdir -p dist
"$flutter_bin" build linux --release
packaging/linux/build-deb.sh
packaging/linux/build-appimage.sh
if command -v makepkg >/dev/null; then
  packaging/arch/build-package.sh
else
  echo 'Skipping Arch package: makepkg is unavailable on this host.' >&2
fi
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
commit="$(git rev-parse HEAD)"
{
  echo "Deltiecord $version"
  echo "Git commit: $commit"
  echo "Built: $(date --iso-8601=seconds)"
  echo "Architecture: x86_64"
} >dist/BUILD-INFO.txt
cp packaging/README.md dist/README.txt
(
  cd dist
  find . -maxdepth 1 -type f \( -name '*.deb' -o -name '*.AppImage' -o -name '*.pkg.tar.zst' \) \
    -printf '%f\n' | sort | xargs -r sha256sum -- >SHA256SUMS
)
