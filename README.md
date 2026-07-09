# -play

v0.8.3

Fast `fd → mpv` media launcher plus optional `~/.-sync` metadata/tag index.

## Install

```bash
brew install git fd gawk parallel ffmpeg vips imagemagick coreutils && repo="${XDG_DATA_HOME:-$HOME/.local/share}/-play" && if [ -d "$repo/.git" ]; then git -C "$repo" pull --ff-only; else mkdir -p "$(dirname "$repo")" && git clone https://github.com/shirk33y/-play.git "$repo"; fi && "$repo/install.sh"
```

## Usage

```text
-play [OPTIONS] [QUERY_OR_PATH ...] [-F|--fd-args FD_ARGS ...] [-M|--mpv-args MPV_ARGS ...]

-i, --image                 images only
-v, --video                 videos only
-f, --fav                   alias: --tag fav
-g, --tag TAG               fav|del|0..9
-m, --meta                  only ~/.-sync/meta; no filesystem scan
-l, --list                  print files; do not start mpv
-s, --size [+|-]SIZE        e.g. +20M, -500K, 2G
-a, --age [+|-]AGE          5d/-5d = recent; +5d = older
-d, --duration [+|-]DUR     from existing meta only
-r, --resolution [+|-]MP    from existing meta only; presets xs,s,m,l,xl
-b, --bitrate [+|-]MBPS     from existing meta only
-F, --fd-args ...           pass-through to fd until -M or end
-M, --mpv-args ...          pass-through to mpv until -F or end
```

```text
-sync [OPTIONS] [PATH ...]

-f, --fast                  stat/ext only; no probe/thumbs; hash only with --hash
-P, --no-probe              no ffprobe/vipsheader/identify
-x, --hash                  compute hash for new/changed files; default off
-T, --no-thumbs             disable thumbnails placeholder
-j, --jobs N                0 = auto; default max(1, floor(nproc/2))
```

## Examples

```bash
-play ~/Videos
-play -v ~/Videos
-play -i ~/Pictures
-play -l -v ~/Videos
-play -v -a 5d -s +20M ~/Videos
-play -v -d +10m ~/Videos
-play -i -r +12.5 ~/Pictures
-play -g fav
-play -g del
-play -m -g fav ~/NAS
-play -v ~/Videos -F -H -d 2 -M --shuffle --fs

-sync ~/Videos
-sync -f ~/Videos
-sync -P -T ~/Videos
-sync --hash ~/Videos
-sync -j 8 ~/Videos

bench-play ~/Videos
```

## How it works

`-play` without heavy filters uses the fast path: `fd -> playlist -> mpv`; no `stat`, no probe, no sync. Filters like size/age use live `fd/stat`. Filters like duration/resolution/bitrate/tag merge live `fd` results with existing `~/.-sync/meta` and `tag`; they never run `ffprobe`.

`-sync` builds `~/.-sync/meta` atomically and keeps resumable checkpoints in `~/.-sync/work/partial`. Existing probe/hash data is reused when `dev:ino + size + mtime` match. Hashing is opt-in via `--hash`.

mpv keys: `j/k` next/prev, `u` random, `h/l` dir nav, `v/i` random favorite video/image, `n` newest, `y/Y` fav add/remove, `d/D` del add/remove, `0..9` tag, shifted digits remove tag.

## Tests

```bash
tests/run-cli-tests.sh
tests/run-lua-tests.sh
tests/run-behavior-tests.py
```

Lua tests use a mocked `mp` module and catch syntax errors in mpv scripts before release.

Playlists are natural-sorted by full path (`image1` before `image12`).
