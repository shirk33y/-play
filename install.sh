#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
MPV_DIR="${MPV_DIR:-$HOME/.config/mpv}"
SYNC_DIR="${SYNC_DIR:-$HOME/.-sync}"
BASH_COMPLETION_FILE="${BASH_COMPLETION_FILE:-$HOME/.bash_completion}"

mkdir -p "$BIN_DIR" "$MPV_DIR/scripts" "$MPV_DIR/script-opts" "$SYNC_DIR/backups" "$SYNC_DIR/thumbs"

backup_copy() {
  local src="$1" dst="$2"
  if [[ -e "$dst" ]] && ! cmp -s -- "$src" "$dst"; then
    cp -a -- "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
  fi
  cp -a -- "$src" "$dst"
}

install_bash_completion() {
  local begin="# >>> -play completion >>>"
  local end="# <<< -play completion <<<"
  local tmp
  mkdir -p -- "$(dirname "$BASH_COMPLETION_FILE")"
  tmp="$(mktemp)"
  if [[ -e "$BASH_COMPLETION_FILE" ]]; then
    awk -v begin="$begin" -v end="$end" '
      $0==begin {skip=1; next}
      $0==end {skip=0; next}
      !skip {print}
    ' "$BASH_COMPLETION_FILE" > "$tmp"
  fi
  {
    cat "$tmp"
    printf '%s\n' "$begin"
    cat "$ROOT/completion/bash.sh"
    printf '%s\n' "$end"
  } > "$BASH_COMPLETION_FILE"
  rm -f -- "$tmp"
}

install_bin() {
  local name="$1"
  cp -a -- "$ROOT/bin/$name" "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
}

install_bin -play
install_bin -sync
install_bin bench-play

backup_copy "$ROOT/mpv/input.conf" "$MPV_DIR/input.conf"
backup_copy "$ROOT/mpv/mpv.conf" "$MPV_DIR/mpv.conf"
backup_copy "$ROOT/mpv/scripts/fehnav.lua" "$MPV_DIR/scripts/fehnav.lua"
backup_copy "$ROOT/mpv/scripts/detect-image.lua" "$MPV_DIR/scripts/detect-image.lua"
backup_copy "$ROOT/mpv/scripts/tagbar.lua" "$MPV_DIR/scripts/tagbar.lua"
backup_copy "$ROOT/mpv/script-opts/detect_image.conf" "$MPV_DIR/script-opts/detect_image.conf"
install_bash_completion

[[ -e "$SYNC_DIR/include" ]] || : > "$SYNC_DIR/include"
[[ -e "$SYNC_DIR/exclude" ]] || : > "$SYNC_DIR/exclude"
[[ -e "$SYNC_DIR/meta" ]] || printf 'id\tpath\tsize\tmtime_ns\tctime_ns\tkind\text\twidth\theight\tduration\tbitrate_mbps\tmp\tanimated\thash\tmissing\n' > "$SYNC_DIR/meta"
[[ -e "$SYNC_DIR/tag" ]] || printf 'id\tpath\ttag_name\tcount\tadded_at\tupdated_at\n' > "$SYNC_DIR/tag"
[[ -e "$SYNC_DIR/work/partial" ]] || { mkdir -p "$SYNC_DIR/work"; printf 'id\tpath\tsize\tmtime_ns\tctime_ns\tkind\text\twidth\theight\tduration\tbitrate_mbps\tmp\tanimated\thash\tmissing\n' > "$SYNC_DIR/work/partial"; }

echo "installed -play, -sync, bench-play to $BIN_DIR"
echo "installed mpv config/scripts to $MPV_DIR"
echo "installed bash completion workaround to $BASH_COMPLETION_FILE"
echo "restart shell or run: source $BASH_COMPLETION_FILE"
echo "sync dir: $SYNC_DIR"
echo "make sure $BIN_DIR is in PATH"
