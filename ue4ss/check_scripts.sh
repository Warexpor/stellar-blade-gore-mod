#!/usr/bin/env bash
# Check shipped Lua syntax and unexpected global reads, without installing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS=${1:-$ROOT/ue4ss/StellarBladeGore/Scripts}
LUAC=luac
command -v luac5.4 >/dev/null && LUAC=luac5.4
if command -v "$LUAC" >/dev/null; then
  for f in "$SCRIPTS"/*.lua; do
    "$LUAC" -p "$f" || { echo "script check failed: $f doesn't load"; exit 1; }
    # and reads no global but Lua's and UE4SS's: a local used above its definition is a nil global at run time
    # (gore.lua's seam hold called addr() before it was defined and never ran, playtest)
    bad=$("$LUAC" -l -p "$f" | grep -o 'GETTABUP.*_ENV "[A-Za-z_0-9]*"' | grep -o '"[^"]*"' | tr -d '"' | sort -u |
      grep -vxE 'assert|collectgarbage|debug|dofile|loadfile|load|error|io|ipairs|math|next|os|pairs|pcall|print|rawget|rawset|require|select|setmetatable|getmetatable|string|table|tonumber|tostring|type|xpcall|utf8|FName|FText|LoadAsset|StaticFindObject|StaticConstructObject|FindAllOf|FindFirstOf|FindObject|NotifyOnNewObject|RegisterHook|RegisterKeyBind|ExecuteInGameThread|ExecuteWithDelay|LoopAsync|DumpUSMAP|Key|ModifierKey|EInternalObjectFlags|EObjectFlags|UEHelpers' || true)
    [[ -z $bad ]] || { echo "script check failed: $f reads undefined globals: $bad"; exit 1; }
  done
else
  echo "warning: Lua compiler not found; script syntax and global checks skipped" >&2
fi
