#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$repo_root/pubspec.yaml")"
tools_dir="$repo_root/packaging/.tools"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
appdir="$work/Deltiecord.AppDir"
linuxdeploy="$tools_dir/linuxdeploy-x86_64.AppImage"
plugin="$tools_dir/linuxdeploy-plugin-appimage-x86_64.AppImage"
runtime="$tools_dir/appimage-runtime-x86_64"
mkdir -p "$tools_dir" "$repo_root/dist"

# Release tooling is pinned to immutable upstream tags and verified before it is
# ever made executable. Updating a tool requires reviewing the release and
# changing both its tag and checksum here.
linuxdeploy_url="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage"
linuxdeploy_sha256="c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d"
plugin_url="https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/1-alpha-20250213-1/linuxdeploy-plugin-appimage-x86_64.AppImage"
plugin_sha256="992d502a248e14ab185448ddf6f6e7d25558cb84d4623c354c3af350c25fccb3"
runtime_url="https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64"
runtime_sha256="2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"

ensure_tool() {
  local destination="$1" url="$2" expected="$3" temporary="${1}.download"
  if test -f "$destination" && echo "$expected  $destination" | sha256sum --check --status; then
    chmod 0755 "$destination"
    return
  fi
  rm -f "$temporary"
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$url" -o "$temporary"
  echo "$expected  $temporary" | sha256sum --check --status || {
    rm -f "$temporary"
    echo "Refusing unverified release tool: $url" >&2
    exit 1
  }
  chmod 0755 "$temporary"
  mv "$temporary" "$destination"
}

ensure_tool "$linuxdeploy" "$linuxdeploy_url" "$linuxdeploy_sha256"
ensure_tool "$plugin" "$plugin_url" "$plugin_sha256"
ensure_tool "$runtime" "$runtime_url" "$runtime_sha256"
"$repo_root/packaging/linux/build-appdir.sh" "$appdir"

export ARCH=x86_64
export VERSION="$version"
export OUTPUT="$repo_root/dist/Deltiecord-${version}-x86_64.AppImage"
export LDAI_OUTPUT="$OUTPUT"
export LDAI_RUNTIME_FILE="$runtime"
export PATH="$tools_dir:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1
# linuxdeploy's embedded binutils may predate RELR sections emitted by newer
# distributions. Stripping is not required for correctness and a failed/partial
# strip is worse than a modestly larger reproducible image.
export NO_STRIP=1
"$linuxdeploy" --appimage-extract-and-run \
  --appdir "$appdir" \
  --executable "$appdir/usr/lib/deltiecord/deltiecord" \
  --desktop-file "$appdir/usr/share/applications/net.deltie.deltiecord.desktop" \
  --icon-file "$appdir/usr/share/icons/hicolor/scalable/apps/net.deltie.deltiecord.svg" \
  --custom-apprun "$repo_root/packaging/linux/deltiecord-launcher" \
  --output appimage
test -x "$OUTPUT"
echo "$OUTPUT"
