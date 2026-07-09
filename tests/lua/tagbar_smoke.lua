-- Plain Lua smoke tests for mpv/scripts/tagbar.lua with mocked mp/mp.utils.
-- Run with: lua tests/lua/tagbar_smoke.lua
local root = arg[1] or '.'
local overlay = { data = '', updates = 0 }
function overlay:update() self.updates = self.updates + 1 end

local home = os.getenv('HOME')
local abc = home .. '/Downloads/abc.gif'
local movie = home .. '/Videos/movie.mp4'
local no_meta = home .. '/Downloads/no-meta.jpg'
local bsd_only = home .. '/Downloads/bsd-only.jpg'
local url = 'https://example.invalid/remote.mp4'

local props = {
  path = abc,
  ['osd-width'] = 900,
  ['playlist-pos'] = 0,
  ['playlist-count'] = 345345,
  playlist = {
    { filename = abc },
    { filename = movie },
    { filename = no_meta },
    { filename = url },
  },
}
local events = {}
local observed = {}
local bindings = {}
local binding_opts = {}
local errors = {}
local messages = {}

package.preload['mp'] = function()
  return {
    msg = { error = function(x) table.insert(errors, tostring(x)) end, info = function(_) end },
    create_osd_overlay = function(kind) assert(kind == 'ass-events'); return overlay end,
    get_property = function(k) return props[k] end,
    get_property_number = function(k, default) local v = props[k]; if type(v) == 'number' then return v end; return default end,
    get_property_native = function(k)
      if k == 'playlist' and props.raise_playlist then error('playlist boom') end
      return props[k]
    end,
    set_property_number = function(k, v) props[k] = v end,
    osd_message = function(x) table.insert(messages, tostring(x)) end,
    add_key_binding = function(_, name, fn, opts) bindings[name] = fn; binding_opts[name] = opts or {} end,
    register_event = function(name, fn) events[name] = fn end,
    observe_property = function(name, _, fn) observed[name] = fn end,
  }
end
package.preload['mp.utils'] = function()
  return {
    subprocess = function(req)
      local a = req.args or {}
      local path = a[#a]
      if a[1] == 'stat' and a[2] == '-c' and a[3] == '%Y' then
        if path == no_meta then error('stat mtime boom') end
        if path == bsd_only then return { status = 1, stdout = '' } end
        return { status = 0, stdout = '2\n' }
      end
      if a[1] == 'stat' and a[2] == '-f' and a[3] == '%m' then
        if path == bsd_only then return { status = 0, stdout = '6\n' } end
        if path == no_meta then error('bsd stat boom') end
        return { status = 1, stdout = '' }
      end
      if a[1] == 'stat' then return { status = 0, stdout = '1:2\n' } end
      if a[1] == 'mkdir' then return { status = 0, stdout = '' } end
      return { status = 0, stdout = '' }
    end
  }
end

-- Prepare tag/meta files.
local sync = os.getenv('SYNC_DIR')
os.execute('mkdir -p ' .. string.format('%q', sync))
local tag = assert(io.open(sync .. '/tag', 'w'))
tag:write('id\tpath\ttag_name\tcount\tadded_at\tupdated_at\n')
tag:write('1:2\t' .. props.path .. '\tfav\t1\t1\t1\n')
tag:write('1:2\t' .. props.path .. '\t6\t1\t1\t1\n')
tag:close()
local meta = assert(io.open(sync .. '/meta', 'w'))
meta:write('id\tpath\tsize\tmtime_ns\tctime_ns\tkind\text\twidth\theight\tduration\tbitrate_mbps\tmp\tanimated\thash\tmissing\n')
meta:write('1:2\t' .. props.path .. '\t3\t1000000000\t1000000000\timage\tgif\t1\t1\t\t\t1\t0\t\t0\n')
meta:write('2:3\t' .. movie .. '\t3\t3000000000\t3000000000\tvideo\tmp4\t1\t1\t1\t1\t1\t1\t\t0\n')
meta:close()

dofile(root .. '/mpv/scripts/tagbar.lua')
assert(type(events['file-loaded']) == 'function', 'file-loaded event registered')
assert(type(observed['playlist-pos']) == 'function', 'playlist-pos observer registered')
assert(type(bindings['random-image']) == 'function', 'random-image binding registered')
assert(binding_opts['random-image'] and binding_opts['random-image'].repeatable == true, 'random-image binding is repeatable')
assert(binding_opts['random-video'] and binding_opts['random-video'].repeatable == true, 'random-video binding is repeatable')
assert(binding_opts['newest'] and binding_opts['newest'].repeatable == true, 'newest binding is repeatable')

events['file-loaded']()
assert(overlay.data:find('\\an7'), 'ASS top-left alignment is escaped for Lua and present for ASS')
assert(overlay.data:find('~/Downloads/abc%.gif'), 'HOME path shortened')
assert(overlay.data:find('%[6,fav%]') or overlay.data:find('%[fav,6%]'), 'tags rendered')
assert(overlay.data:find('    %[1/345345%]'), 'right counter has left spacing')
assert(not overlay.data:find('alpha&H80'), 'no translucent top bar')

bindings['random-image']()
assert(props['playlist-pos'] == 0, 'random image uses favorite image candidate')

-- Regression: newest used to crash the whole script when stat/probe path handling failed.
local ok, err = pcall(function() bindings['newest']() end)
assert(ok, 'newest binding must not throw: ' .. tostring(err))
assert(props['playlist-pos'] == 1, 'newest falls back to meta and ignores failed stat entries')

bindings['invalidate-cache']()
props.playlist = {
  { filename = abc },
  { filename = bsd_only },
  { filename = url },
}
props['playlist-count'] = #props.playlist
props['playlist-pos'] = 0
bindings['newest']()
assert(props['playlist-pos'] == 1, 'newest uses BSD stat fallback and skips URLs')

bindings['invalidate-cache']()
props.playlist = {
  { filename = abc },
  { filename = movie },
}
props['playlist-count'] = #props.playlist
props['playlist-pos'] = 0
bindings['newest']()
assert(props['playlist-pos'] == 1, 'newest builds cache for current playlist')
props.playlist = {
  { filename = movie },
  { filename = abc },
}
props['playlist-pos'] = 1
bindings['newest']()
assert(props['playlist-pos'] == 0, 'newest cache changes when playlist content changes at same count')

props.raise_playlist = true
ok, err = pcall(function() bindings['newest']() end)
props.raise_playlist = false
assert(ok, 'newest safe binding catches playlist errors: ' .. tostring(err))
assert(messages[#messages] == 'tagbar: newest failed', 'newest safe binding reports failure')
bindings['invalidate-cache']()
bindings['random-image']()
assert(props['playlist-pos'] == 1, 'other tagbar bindings still work after newest failure')

print('Lua smoke tests OK')
