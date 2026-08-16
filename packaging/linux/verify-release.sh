#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
library="$repo_root/build/linux/x64/release/bundle/lib/libvodozemac_bindings_dart.so"

test -f "$library" || {
  echo "Missing release E2EE library: $library" >&2
  exit 1
}

# flutter_vodozemac 0.7.1 can produce an apparently successful AOT build whose
# Dart DL shim was garbage-collected. Such a build fails only when main()
# initializes encryption, so reject it before any package is assembled.
if readelf --wide --symbols "$library" |
  grep -E 'UND.*Dart_(CurrentIsolate|InitializeApi|DeletePersistentHandle|HandleFromPersistent|NewPersistentHandle)_DL'; then
  echo 'Release E2EE library contains unresolved Dart DL symbols.' >&2
  exit 1
fi

echo 'Release E2EE linkage verified.'
