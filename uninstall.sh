#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="${BIN_DIR:-$HOME/bin}"
MPV_DIR="${MPV_DIR:-$HOME/.config/mpv}"
BASH_COMPLETION_FILE="${BASH_COMPLETION_FILE:-$HOME/.bash_completion}"

rm -f -- "$BIN_DIR/-play" "$BIN_DIR/-sync" "$BIN_DIR/bench-play"
rm -f -- "$MPV_DIR/scripts/fehnav.lua" "$MPV_DIR/scripts/detect-image.lua" "$MPV_DIR/scripts/tagbar.lua" "$MPV_DIR/script-opts/detect_image.conf"
if [[ -e "$BASH_COMPLETION_FILE" ]]; then
  tmp="$(mktemp)"
  awk '$0=="# >>> -play completion >>>" {skip=1; next} $0=="# <<< -play completion <<<" {skip=0; next} !skip {print}' "$BASH_COMPLETION_FILE" > "$tmp"
  mv -f -- "$tmp" "$BASH_COMPLETION_FILE"
fi

echo "removed bundle scripts. mpv.conf/input.conf and ~/.-sync are left intact."
