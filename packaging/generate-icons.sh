#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_icon="$repo_root/icon.png"
command -v magick >/dev/null || {
  echo 'ImageMagick is required to regenerate platform icons.' >&2
  exit 1
}
test -f "$source_icon" || {
  echo "Missing authoritative icon: $source_icon" >&2
  exit 1
}

round_icon="$(mktemp --suffix=.png)"
trap 'rm -f "$round_icon"' EXIT
magick "$source_icon" \
  \( -size 256x256 xc:black -fill white \
    -draw 'circle 127.5,127.5 127.5,0' \) \
  -alpha off -compose CopyOpacity -composite "$round_icon"

for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%%:*}"
  size="${spec##*:}"
  target="$repo_root/android/app/src/main/res/mipmap-$density"
  magick "$round_icon" -resize "${size}x${size}" "$target/ic_launcher.png"
  cp "$target/ic_launcher.png" "$target/ic_launcher_round.png"
done

# Adaptive icons reserve the outer portion for launcher masks. Keeping the
# complete mark in the central safe zone prevents circular launchers clipping
# the Deltiecord triangle.
magick -size 432x432 canvas:none \
  \( "$source_icon" -fuzz 4% -transparent black -resize 288x288 \) \
  -gravity center -composite \
  "$repo_root/android/app/src/main/res/drawable/ic_launcher_foreground.png"
magick "$round_icon" -resize 256x256 \
  "$repo_root/packaging/linux/net.deltie.deltiecord.png"
magick "$round_icon" -define icon:auto-resize=256,128,64,48,32,24,16 \
  "$repo_root/windows/runner/resources/app_icon.ico"
