#!/usr/bin/env bash
# Run the offline decision-logic checks. Needs a Lua 5.x interpreter; set LUA to point at one if
# `lua` isn't on PATH (Windows: LUA="$LOCALAPPDATA/Programs/Lua/bin/lua.exe" ./run.sh).
set -euo pipefail
cd "$(dirname "$0")"

LUA="${LUA:-lua}"
SCRIPTS="${1:-../../ue4ss/TFWStaggerControl/Scripts}"

echo "== recorded tester timelines =="
"$LUA" replay.lua "$SCRIPTS"
echo
echo "== synthetic scenarios =="
"$LUA" scenarios.lua "$SCRIPTS"
