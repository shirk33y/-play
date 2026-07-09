#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tests/check-lua-static.py"

find_cmd() {
  local c
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  return 1
}

LUA="$(find_cmd lua lua5.4 lua5.3 lua5.2 lua5.1 || true)"
LUAC="$(find_cmd luac luac5.4 luac5.3 luac5.2 luac5.1 || true)"

if [[ -n "$LUAC" ]]; then
  "$LUAC" -p "$ROOT"/mpv/scripts/*.lua
elif [[ -n "$LUA" ]]; then
  for f in "$ROOT"/mpv/scripts/*.lua; do "$LUA" -e "assert(loadfile(arg[1]))" "$f"; done
else
  echo "Lua interpreter not found; static checks only" >&2
  exit 0
fi

if [[ -n "$LUA" ]]; then
  TMP="${TMPDIR:-/tmp}/play-lua-tests.$$"
  mkdir -p "$TMP/home" "$TMP/sync"
  HOME="$TMP/home" SYNC_DIR="$TMP/sync" "$LUA" "$ROOT/tests/lua/tagbar_smoke.lua" "$ROOT"
  HOME="$TMP/home" SYNC_DIR="$TMP/sync" "$LUA" "$ROOT/tests/lua/fehnav_smoke.lua" "$ROOT"
  rm -rf "$TMP"
fi
