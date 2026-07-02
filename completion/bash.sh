# -play bash completion workaround for commands beginning with '-'.
# Must be sourced before bash-completion tries dynamic _comp_load for -play/-sync.
__minus_play_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()
  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W '-i --image -v --video -f --fav -g --tag -m --meta -l --list -s --size -a --age -d --duration -r --resolution -b --bitrate -F --fd-args -M --mpv-args -h --help --version' -- "$cur") )
    return 0
  fi
  compopt -o default 2>/dev/null || true
  compopt -o bashdefault 2>/dev/null || true
  return 0
}
__minus_sync_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()
  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W '-f --fast -P --no-probe -x --hash -T --no-thumbs -j --jobs -h --help --version' -- "$cur") )
    return 0
  fi
  compopt -o default 2>/dev/null || true
  compopt -o bashdefault 2>/dev/null || true
  return 0
}
complete -r -- -play 2>/dev/null || true
complete -r -- -sync 2>/dev/null || true
complete -o default -o bashdefault -F __minus_play_complete -- -play
complete -o default -o bashdefault -F __minus_sync_complete -- -sync
complete -o default -o bashdefault -F __minus_play_complete -- bench-play
