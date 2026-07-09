local mp = require "mp"

math.randomseed(os.time())

local dir_cache = nil

local function current_pos()
  local p = mp.get_property_number("playlist-playing-pos", -1)
  if p < 0 then p = mp.get_property_number("playlist-pos", -1) end
  return p
end

local function play_index(i)
  if i == nil then return end
  mp.set_property_number("playlist-pos", i)
end

local function dirname(path)
  if not path or path == "" then return "" end
  path = path:gsub("[/\\]+$", "")
  return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function playlist()
  return mp.get_property_native("playlist", {}) or {}
end

local function invalidate_dir_cache()
  dir_cache = nil
end

local function build_dir_cache()
  local pl = playlist()
  local n = #pl
  local cache = { count = n, next_dir = {}, prev_dir = {} }
  if n <= 1 then dir_cache = cache; return cache end

  local dirs = {}
  for i, item in ipairs(pl) do
    dirs[i] = dirname(item and item.filename)
  end

  local runs = {}
  local i = 1
  while i <= n do
    local start_i = i
    local d = dirs[i]
    while i + 1 <= n and dirs[i + 1] == d do i = i + 1 end
    table.insert(runs, { first = start_i, last = i, dir = d })
    i = i + 1
  end

  if #runs <= 1 then dir_cache = cache; return cache end

  for ri, run in ipairs(runs) do
    local next_run = runs[(ri % #runs) + 1]
    local prev_run = runs[((ri - 2) % #runs) + 1]
    for idx = run.first, run.last do
      cache.next_dir[idx - 1] = next_run.first - 1
      -- h: first go to the first file of the current directory.
      -- If already there, jump to the first file of the previous directory.
      if idx == run.first then
        cache.prev_dir[idx - 1] = prev_run.first - 1
      else
        cache.prev_dir[idx - 1] = run.first - 1
      end
    end
  end

  dir_cache = cache
  return cache
end

local function get_dir_cache()
  local n = mp.get_property_number("playlist-count", 0) or 0
  if not dir_cache or dir_cache.count ~= n then return build_dir_cache() end
  return dir_cache
end

local function random_item()
  local n = mp.get_property_number("playlist-count", 0)
  if n <= 0 then return end

  local cur = current_pos()
  local next = math.random(0, n - 1)

  if n > 1 then
    while next == cur do
      next = math.random(0, n - 1)
    end
  end

  play_index(next)
end

local function step_playlist(delta)
  local n = mp.get_property_number("playlist-count", 0) or 0
  if n <= 0 then return end
  local cur = current_pos()
  if cur < 0 then cur = 0 end
  local target = (cur + delta) % n
  play_index(target)
end

local function jump_dir(step)
  local cur = current_pos()
  if cur < 0 then return end

  local cache = get_dir_cache()
  local target = nil
  if step > 0 then target = cache.next_dir[cur] else target = cache.prev_dir[cur] end

  if target ~= nil then play_index(target) else mp.osd_message("no other directory") end
end

mp.add_key_binding(nil, "random", random_item, {repeatable=true})
mp.add_key_binding(nil, "next", function() step_playlist(1) end, {repeatable=true})
mp.add_key_binding(nil, "prev", function() step_playlist(-1) end, {repeatable=true})
mp.add_key_binding(nil, "prev-dir", function() jump_dir(-1) end, {repeatable=true})
mp.add_key_binding(nil, "next-dir", function() jump_dir(1) end, {repeatable=true})
mp.add_key_binding(nil, "invalidate-cache", invalidate_dir_cache)
mp.observe_property("playlist-count", "number", invalidate_dir_cache)
