-- Plain Lua smoke tests for mpv/scripts/fehnav.lua with mocked mp/mp.utils.
-- Verifies script bindings are registered as repeatable and basic navigation works.
local root = arg[1] or '.'
local props = {
  ['playlist-pos'] = 1,
  ['playlist-count'] = 4,
  playlist = {
    { filename = '/media/a/001.jpg' },
    { filename = '/media/a/002.jpg' },
    { filename = '/media/b/003.jpg' },
    { filename = '/media/c/004.jpg' },
  },
}
local bindings = {}
local binding_opts = {}
local observed = {}

package.preload['mp'] = function()
  return {
    msg = { error = function(_) end, info = function(_) end },
    get_property_number = function(k, default) local v = props[k]; if type(v) == 'number' then return v end; return default end,
    get_property_native = function(k) return props[k] end,
    set_property_number = function(k, v) props[k] = v end,
    osd_message = function(_) end,
    add_key_binding = function(_, name, fn, opts) bindings[name] = fn; binding_opts[name] = opts or {} end,
    observe_property = function(name, _, fn) observed[name] = fn end,
  }
end
package.preload['mp.utils'] = function()
  return {
    split_path = function(path)
      local dir, file = path:match('^(.*)/(.-)$')
      return dir or '.', file or path
    end,
  }
end

dofile(root .. '/mpv/scripts/fehnav.lua')
for _, name in ipairs({'random', 'next', 'prev', 'prev-dir', 'next-dir'}) do
  assert(type(bindings[name]) == 'function', name .. ' binding registered')
  assert(binding_opts[name] and binding_opts[name].repeatable == true, name .. ' binding is repeatable')
end

bindings['next']()
assert(props['playlist-pos'] == 2, 'next moves forward')
bindings['prev']()
assert(props['playlist-pos'] == 1, 'prev moves back')
bindings['prev-dir']()
assert(props['playlist-pos'] == 0, 'prev-dir from non-first item jumps to first item in current dir')
bindings['prev-dir']()
assert(props['playlist-pos'] == 3, 'prev-dir from first item wraps to first item in previous dir')
bindings['next-dir']()
assert(props['playlist-pos'] == 0, 'next-dir wraps to next dir first item')
print('fehnav smoke tests OK')
