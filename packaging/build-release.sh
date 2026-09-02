#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
# flutter_vodozemac 0.7.1's release link can discard the Dart DL shim as
# otherwise-unreferenced code. Retaining linked code is required for AOT E2EE.
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C link-dead-code"
cd "$repo_root"
rm -rf dist
mkdir -p dist
"$flutter_bin" build linux --release
packaging/linux/verify-release.sh
packaging/linux/build-deb.sh
packaging/linux/build-appimage.sh
command -v makepkg >/dev/null || {
  echo 'makepkg is required for the complete release artifact set.' >&2
  exit 1
}
packaging/arch/build-package.sh
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
release_id="$(sed -n 's/^version: \([^[:space:]]*\).*/\1/p' pubspec.yaml)"
if [[ -f "dist/deltiecord_${release_id}_amd64.deb" ]]; then
  mv "dist/deltiecord_${release_id}_amd64.deb" "dist/deltiecord-${release_id}-linux-debian-amd64.deb"
fi
if [[ -f "dist/Deltiecord-${version}-x86_64.AppImage" ]]; then
  mv "dist/Deltiecord-${version}-x86_64.AppImage" "dist/deltiecord-${release_id}-linux-appimage-x86_64.AppImage"
fi
mapfile -t packages < <(find dist -maxdepth 1 -type f -name '*.pkg.tar.zst' -print)
if [[ "${#packages[@]}" -ne 1 ]]; then
  printf 'Expected exactly one Arch package, found %s\n' "${#packages[@]}" >&2
  exit 1
fi
mv -- "${packages[0]}" "dist/deltiecord-${release_id}-linux-arch-x86_64.pkg.tar.zst"

for artifact in \
  "dist/deltiecord-${release_id}-linux-debian-amd64.deb" \
  "dist/deltiecord-${release_id}-linux-appimage-x86_64.AppImage" \
  "dist/deltiecord-${release_id}-linux-arch-x86_64.pkg.tar.zst"; do
  [[ -f "$artifact" ]] || {
    printf 'Missing required release artifact: %s\n' "$artifact" >&2
    exit 1
  }
done
commit="$(git rev-parse HEAD)"
{
  echo "Deltiecord $release_id"
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
