#!/usr/bin/env bash
set -euo pipefail
export PATH="/clang64/bin:/usr/bin:$PATH"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export SB_CACHE="$ROOT/.cache/windows"
export PATH="$SB_CACHE/dotnet:$PATH"
[[ -n ${SB_GAME:-} ]] && export SB_GAME=$(cygpath -u "$SB_GAME")
cd "$ROOT"
case "${1:-build}" in
  build)          exec bash build.sh ;;
  check-build)    export SB_DIST="$SB_CACHE/dist"; exec bash build.sh ;;
  build-install)  exec bash build.sh --install ;;
  native)         exec bash native/sbslice/build.sh "$SB_CACHE/sbslice" ;;
  test-lua)       exec bash ue4ss/test/run.sh "${@:2}" ;;
  test-native)    exec bash native/sbslice/test/run.sh "${@:2}" ;;
  package)        exec bash package.sh ;;
  check-package)  export SB_RELEASE="$SB_CACHE/package-check"; exec bash package.sh ;;
  install)        exec bash ue4ss/install.sh ;;
  *) echo "unknown action: $1" >&2; exit 2 ;;
esac
