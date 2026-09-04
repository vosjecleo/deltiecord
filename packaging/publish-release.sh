#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: packaging/publish-release.sh --channel latest|stable|both [--clear-stable] [--install-host] [--skip-preflight]

Validates the committed release, pushes main and its version tag to GitHub and
the Deltie mirror, waits for GitHub Actions to publish the platform artifacts,
verifies them, and atomically updates the selected deltie.net release channel.
EOF
}

channel=''
install_host=false
skip_preflight=false
clear_stable=false
while (($#)); do
  case "$1" in
    --channel)
      (($# >= 2)) || { usage >&2; exit 2; }
      channel="$2"
      shift 2
      ;;
    --install-host)
      install_host=true
      shift
      ;;
    --clear-stable)
      clear_stable=true
      shift
      ;;
    --skip-preflight)
      skip_preflight=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$channel" in
  latest|stable|both) ;;
  *) printf '%s\n' '--channel must be latest, stable, or both.' >&2; exit 2 ;;
esac
if $clear_stable && [[ "$channel" != latest ]]; then
  printf '%s\n' '--clear-stable is only valid while publishing latest.' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

for command in curl git jq scp sha256sum ssh stat; do
  command -v "$command" >/dev/null || {
    printf 'Required command is unavailable: %s\n' "$command" >&2
    exit 1
  }
done

[[ "$(git branch --show-current)" == main ]] || {
  printf '%s\n' 'Releases must be published from main.' >&2
  exit 1
}
[[ -z "$(git status --porcelain=v1)" ]] || {
  printf '%s\n' 'Refusing to publish a dirty worktree. Commit the release first.' >&2
  exit 1
}

release_id="$(sed -n 's/^version: \([^[:space:]]*\).*/\1/p' pubspec.yaml)"
[[ "$release_id" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || {
  printf 'Invalid pubspec release ID: %s\n' "$release_id" >&2
  exit 1
}
version="${release_id%%+*}"
build="${release_id##*+}"
tag="v${version}-b${build}"
[[ "$(sed -n "s/^const deltiecordVersion = '\([^']*\)';/\1/p" lib/version.dart)" == "$version" ]]
[[ "$(sed -n "s/^const deltiecordBuildNumber = '\([^']*\)';/\1/p" lib/version.dart)" == "$build" ]]
[[ "$(sed -n 's/^pkgver=//p' packaging/arch/PKGBUILD)" == "$version" ]]
[[ "$(sed -n 's/^pkgrel=//p' packaging/arch/PKGBUILD)" == "$build" ]]

if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
  [[ "$(git rev-list -n 1 "$tag")" == "$(git rev-parse HEAD)" ]] || {
    printf 'Release tag %s points to another commit.\n' "$tag" >&2
    exit 1
  }
else
  create_tag=true
fi

if ! $skip_preflight; then
  dart format --output=none --set-exit-if-changed lib test
  flutter pub get --enforce-lockfile
  flutter analyze
  flutter test
  python3 -m unittest discover -s server -p 'test_*.py'
  while IFS= read -r script; do bash -n "$script"; done < <(
    find packaging -type f -name '*.sh' -print | sort
  )
fi

if [[ "${create_tag:-false}" == true ]]; then
  git tag -a "$tag" -m "Deltiecord $release_id ($channel)"
fi
git push github main
git push deltie main
git push github "$tag"
git push deltie "$tag"

temporary="$(mktemp -d -t deltiecord-release.XXXXXXXX)"
trap 'rm -rf -- "$temporary"' EXIT
base_url="https://github.com/vosjecleo/deltiecord/releases/download/$tag"
checksum_url="$base_url/SHA256SUMS"
printf 'Waiting for GitHub Actions release %s' "$tag"
for _ in $(seq 1 180); do
  if curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
      "$checksum_url" -o "$temporary/SHA256SUMS"; then
    printf '%s\n' ' ready.'
    break
  fi
  printf '.'
  sleep 30
done
[[ -s "$temporary/SHA256SUMS" ]] || {
  printf '\nTimed out waiting for GitHub release %s.\n' "$tag" >&2
  exit 1
}

artifacts=(
  "deltiecord-${release_id}-windows-x64-portable.zip"
  "deltiecord-${release_id}-windows-x64-setup.exe"
  "deltiecord-${release_id}-linux-appimage-x86_64.AppImage"
  "deltiecord-${release_id}-linux-arch-x86_64.pkg.tar.zst"
  "deltiecord-${release_id}-linux-debian-amd64.deb"
  "deltiecord-${release_id}-android-arm64-v8a.apk"
  "deltiecord-${release_id}-android-armeabi-v7a.apk"
  "deltiecord-${release_id}-android-x86_64.apk"
  "deltiecord-${release_id}-android.aab"
)
[[ "$(wc -l <"$temporary/SHA256SUMS")" -eq "${#artifacts[@]}" ]] || {
  printf '%s\n' 'GitHub checksum manifest has an unexpected artifact count.' >&2
  exit 1
}
for artifact in "${artifacts[@]}"; do
  [[ "$(awk -v name="$artifact" '$2 == name { count++ } END { print count + 0 }' \
    "$temporary/SHA256SUMS")" -eq 1 ]] || {
      printf 'Missing checksum for %s\n' "$artifact" >&2
      exit 1
    }
  curl --fail --show-error --location --retry 4 --proto '=https' --tlsv1.2 \
    "$base_url/$artifact" -o "$temporary/$artifact"
done
(cd "$temporary" && sha256sum --check --strict SHA256SUMS)

current_manifest="$temporary/current-releases.json"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  https://deltie.net/cord/releases.json -o "$current_manifest"
jq -e '.platforms.android and .platforms.linux and .platforms.windows' \
  "$current_manifest" >/dev/null

asset_json() {
  local pattern="$1" file name digest size
  jq -n '[]' >"$temporary/assets.json"
  for file in "$temporary"/$pattern; do
    [[ -f "$file" ]] || { printf 'No artifact matches %s\n' "$pattern" >&2; exit 1; }
    name="${file##*/}"
    digest="$(sha256sum -- "$file" | cut -d' ' -f1)"
    size="$(stat -c '%s' -- "$file")"
    jq --arg name "$name" --arg digest "$digest" --argjson size "$size" \
      '. + [{name: $name, sha256: $digest, size: $size}]' \
      "$temporary/assets.json" >"$temporary/assets.next.json"
    mv -- "$temporary/assets.next.json" "$temporary/assets.json"
  done
  jq -c . "$temporary/assets.json"
}

android_assets="$(asset_json "deltiecord-${release_id}-android*")"
linux_assets="$(asset_json "deltiecord-${release_id}-linux-*")"
windows_assets="$(asset_json "deltiecord-${release_id}-windows-*")"
updated_at="$(date --utc +'%Y-%m-%dT%H:%M:%S+00:00')"

jq --arg channel "$channel" \
  --argjson clear_stable "$clear_stable" \
  --arg version "$version" \
  --argjson build "$build" \
  --arg updated "$updated_at" \
  --argjson android "$android_assets" \
  --argjson linux "$linux_assets" \
  --argjson windows "$windows_assets" '
  def set_channel($name):
    .platforms.android[$name] = $android |
    .platforms.linux[$name] = $linux |
    .platforms.windows[$name] = $windows;
  if $channel == "both" then
    set_channel("latest") | set_channel("stable") |
    .version = $version | .build = $build | .release = "stable" |
    .stable_version = $version | .stable_build = $build
  elif $channel == "latest" then
    set_channel("latest") |
    .version = $version | .build = $build | .release = "latest"
  else
    set_channel("stable") |
    .stable_version = $version | .stable_build = $build
  end |
  if $clear_stable then
    .platforms.android.stable = [] |
    .platforms.linux.stable = [] |
    .platforms.windows.stable = [] |
    del(.stable_version, .stable_build)
  else . end |
  .updated_at = $updated
' "$current_manifest" >"$temporary/releases.json"
jq -e . "$temporary/releases.json" >/dev/null

remote_root='/srv/storage/www/deltie/cord'
remote_stage="$remote_root/.publish-$tag-$$"
ssh -o BatchMode=yes deltie "mkdir -m 700 -- '$remote_stage'"
cleanup_remote() { ssh -o BatchMode=yes deltie "rm -rf -- '$remote_stage'" >/dev/null 2>&1 || true; }
trap 'cleanup_remote; rm -rf -- "$temporary"' EXIT
scp -q -- "$temporary/SHA256SUMS" "$temporary/releases.json" \
  "${artifacts[@]/#/$temporary/}" "deltie:$remote_stage/"

ssh -o BatchMode=yes deltie "bash -s" -- \
  "$remote_root" "$remote_stage" "$version" "$build" "${artifacts[@]}" <<'REMOTE'
set -euo pipefail
remote_root="$1"
stage="$2"
version="$3"
build="$4"
shift 4
archive="/srv/storage/releases-archive/deltiecord/${version}-b${build}"
mkdir -p -- "$archive"
if [[ -f "$remote_root/releases.json" ]]; then
  cp -- "$remote_root/releases.json" "$archive/releases.before.json"
fi
if [[ -f "$remote_root/SHA256SUMS" ]]; then
  cp -- "$remote_root/SHA256SUMS" "$archive/SHA256SUMS.before"
fi
for artifact in "$@"; do
  install -m 0644 -- "$stage/$artifact" "$remote_root/$artifact"
done
install -m 0644 -- "$stage/SHA256SUMS" "$remote_root/SHA256SUMS"
install -m 0644 -- "$stage/releases.json" "$remote_root/releases.json"
rm -rf -- "$stage"
REMOTE

published="$(curl --fail --silent --show-error --location \
  "https://deltie.net/cord/releases.json?build=$build")"
if [[ "$channel" == latest || "$channel" == both ]]; then
  [[ "$(jq -r '.build' <<<"$published")" == "$build" ]]
fi
if [[ "$channel" == stable || "$channel" == both ]]; then
  [[ "$(jq -r '.stable_build' <<<"$published")" == "$build" ]]
fi
if $clear_stable; then
  [[ "$(jq '[.platforms[].stable | length] | add' <<<"$published")" == 0 ]]
  [[ "$(jq -r 'has("stable_version") or has("stable_build")' <<<"$published")" == false ]]
fi

if $install_host; then
  command -v pkexec >/dev/null || {
    printf '%s\n' 'pkexec is required for --install-host.' >&2
    exit 1
  }
  pkexec apt install -y "$temporary/deltiecord-${release_id}-linux-debian-amd64.deb"
fi

printf 'Published Deltiecord %s to %s.\n' "$release_id" "$channel"
