# -play

Fast `fd -> mpv` media launcher plus optional `~/.-sync` metadata/tag index.

## Install

```bash
brew install fd gawk parallel ffmpeg vips imagemagick coreutils && tmp="$(mktemp -d)" && curl -L https://github.com/shirk33y/-play/archive/refs/heads/main.zip -o "$tmp/-play.zip" && unzip -q "$tmp/-play.zip" -d "$tmp" && "$tmp/-play-main/install.sh" && rm -rf "$tmp"
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

## How it works

`-play` fast path is `fd -> playlist -> mpv`; no `stat`, no probe, no sync. Heavy filters merge live `fd/stat` with existing `~/.-sync/meta` and `tag`; they never run `ffprobe`.

`-sync` writes `~/.-sync/meta` atomically and keeps resumable checkpoints in `~/.-sync/work/partial`. Existing probe/hash data is reused when `dev:ino + size + mtime` match. Hashing is opt-in via `--hash`.
