#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundle="$repo_root/build/linux/x64/release/bundle"
appdir="${1:?usage: build-appdir.sh APPDIR}"

test -x "$bundle/deltiecord" || { echo "Run flutter build linux --release first." >&2; exit 1; }
rm -rf "$appdir"
install -d "$appdir/usr/lib/deltiecord" "$appdir/usr/bin" \
  "$appdir/usr/share/applications" "$appdir/usr/share/metainfo" \
  "$appdir/usr/share/icons/hicolor/256x256/apps" \
  "$appdir/usr/share/doc/deltiecord"
cp -a "$bundle/." "$appdir/usr/lib/deltiecord/"
ln -s ../lib/deltiecord/deltiecord "$appdir/usr/bin/deltiecord"
install -m 0644 "$repo_root/packaging/linux/net.deltie.deltiecord.desktop" \
  "$appdir/usr/share/applications/net.deltie.deltiecord.desktop"
install -m 0644 "$repo_root/packaging/linux/net.deltie.deltiecord.metainfo.xml" \
  "$appdir/usr/share/metainfo/net.deltie.deltiecord.appdata.xml"
install -m 0644 "$repo_root/packaging/linux/net.deltie.deltiecord.png" \
  "$appdir/usr/share/icons/hicolor/256x256/apps/net.deltie.deltiecord.png"
ln -s usr/share/applications/net.deltie.deltiecord.desktop "$appdir/net.deltie.deltiecord.desktop"
ln -s usr/share/icons/hicolor/256x256/apps/net.deltie.deltiecord.png "$appdir/net.deltie.deltiecord.png"
ln -s net.deltie.deltiecord.png "$appdir/.DirIcon"
install -m 0644 "$repo_root/LICENSE" "$appdir/usr/share/doc/deltiecord/LICENSE"
install -m 0644 "$repo_root/CREDITS.md" "$appdir/usr/share/doc/deltiecord/CREDITS.md"
install -m 0644 "$repo_root/THIRD-PARTY-NOTICES.md" \
  "$appdir/usr/share/doc/deltiecord/THIRD-PARTY-NOTICES.md"
install -m 0644 "$bundle/data/flutter_assets/NOTICES.Z" \
  "$appdir/usr/share/doc/deltiecord/FLUTTER-NOTICES.Z"
install -m 0755 "$repo_root/packaging/linux/deltiecord-launcher" \
  "$appdir/AppRun"
