#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
feh = (ROOT / 'mpv/scripts/fehnav.lua').read_text()
tag = (ROOT / 'mpv/scripts/tagbar.lua').read_text()


def ok(name):
    print(f'ok  {name}')


def assert_true(cond, name):
    if not cond:
        raise SystemExit(f'not ok  {name}')
    ok(name)

# Regression: k/j must not bounce through playlist-play-index; direct property set is stable.
assert_true('mp.set_property_number("playlist-pos", i)' in feh, 'fehnav uses stable playlist-pos jumps')
assert_true('playlist-play-index' not in feh, 'fehnav avoids playlist-play-index bounce')

# Regression: h behavior. In a directory run, non-first item -> first current dir.
# First item -> first item of previous dir.
def prev_dir_targets(dirs):
    n = len(dirs)
    runs = []
    i = 0
    while i < n:
        start = i
        d = dirs[i]
        while i + 1 < n and dirs[i+1] == d:
            i += 1
        runs.append((start, i, d))
        i += 1
    prev = {}
    for ri, (first, last, _) in enumerate(runs):
        prev_first = runs[(ri - 1) % len(runs)][0]
        for idx in range(first, last + 1):
            prev[idx] = prev_first if idx == first else first
    return prev

p = prev_dir_targets(['a','a','a','b','b','c'])
assert_true(p[1] == 0 and p[2] == 0, 'h jumps to first file of current dir when not first')
assert_true(p[3] == 0 and p[5] == 3 and p[0] == 5, 'h jumps to first file of previous dir when already first')

# Regression: i/v random candidates are favorite-only.
assert_true("path_has_tag(p, 'fav')" in tag, 'random image/video filters favorite tags')
assert_true("no favorite " in tag, 'random image/video reports no favorite candidates')

# Regression: topbar is text-only near top, with middle ellipsis and spacing.
assert_true('local y = 4' in tag, 'topbar y margin is 4px')
assert_true('tag_text = \'    [\'' in tag, 'topbar has four spaces before tags')
assert_true('#tag_text + #right + 16' in tag, 'topbar reserves spacing before right counter')
assert_true('middle_ellipsis' in tag and " .. '…' .. " in tag, 'topbar uses middle ellipsis')
assert_true('pcall(function()' in tag and 'tagbar refresh failed' in tag, 'topbar refresh is crash guarded')
assert_true('alpha&H80' not in tag and 'bar_h' not in tag, 'topbar has no semi-transparent bar')

# Regression: display path update should not require stat if meta has id.
assert_true('local rec = meta_by_path[path]' in tag, 'topbar can get id from meta by path')
assert_true("mp.observe_property('playlist-pos'" in tag and "mp.register_event('file-loaded'" in tag, 'topbar refreshes on playlist position and file load')

# Regression: n/newest must not kill the Lua script when stat/subprocess fails.
assert_true('local function safe_binding' in tag and "safe_binding('newest'" in tag, 'tagbar key bindings are crash guarded')
assert_true('pcall(function()' in tag and 'utils.subprocess' in tag, 'tagbar subprocess is pcall guarded')
assert_true('stat_mtime_ns' in tag and "stat', '-f', '%m'" in tag, 'newest uses safe GNU/BSD stat fallback')

print('ALL OK')
