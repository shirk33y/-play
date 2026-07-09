local mp = require 'mp'
local utils = require 'mp.utils'

local home = os.getenv('HOME') or ''
local sync_dir = os.getenv('SYNC_DIR') or (home .. '/.-sync')
local tag_file = sync_dir .. '/tag'
local meta_file = sync_dir .. '/meta'
local overlay = mp.create_osd_overlay('ass-events')

local id_cache = {}
local stat_cache = {}
local tag_cache = nil
local tag_path_cache = nil
local meta_by_path = nil
local index_cache = nil
local newest_cache = nil
local math_random_seeded = false
local load_meta, load_tags

local image_ext = {
  apng=true,avif=true,bmp=true,cur=true,dds=true,dib=true,dpx=true,exr=true,farbfeld=true,ff=true,fits=true,gif=true,hdr=true,heic=true,heif=true,ico=true,
  j2c=true,j2k=true,jfif=true,jp2=true,jpc=true,jpe=true,jpeg=true,jpg=true,jxl=true,pam=true,pbm=true,pcx=true,pfm=true,pgm=true,phm=true,pict=true,pix=true,
  png=true,pnm=true,ppm=true,psd=true,qoi=true,ras=true,sgi=true,svg=true,tga=true,tif=true,tiff=true,txd=true,webp=true,xbm=true,xpm=true,xwd=true,
}
local video_ext = {
  ['3g2']=true,['3gp']=true,['3gp2']=true,['3gpp']=true,amv=true,asf=true,avi=true,av1=true,bik=true,dav=true,divx=true,drc=true,dv=true,['dvr-ms']=true,evo=true,
  f4v=true,flv=true,h264=true,h265=true,hevc=true,ivf=true,m1v=true,m2p=true,m2t=true,m2ts=true,m2v=true,m4v=true,mj2=true,mjpeg=true,mk3d=true,
  mkv=true,mod=true,mov=true,mp4=true,mp4v=true,mpe=true,mpeg=true,mpg=true,mpg2=true,mts=true,mxf=true,nsv=true,nut=true,ogm=true,ogv=true,qt=true,
  rm=true,rmvb=true,roq=true,smk=true,swf=true,tod=true,trp=true,ts=true,vob=true,webm=true,wm=true,wmv=true,wtv=true,y4m=true,yuv=true,
}

local function ass_escape(s)
  s = tostring(s or '')
  s = s:gsub('\\', '\\e')
  s = s:gsub('{', '\\{')
  s = s:gsub('}', '\\}')
  return s
end

local function basename(path)
  return (path or ''):match('([^/]+)$') or path or ''
end

local function ext_of(path)
  local e = (path or ''):match('%.([^%.%/]+)$') or ''
  return e:lower()
end

local function home_shorten(path)
  if home ~= '' and path:sub(1, #home + 1) == home .. '/' then
    return '~/' .. path:sub(#home + 2)
  end
  return path
end

local function middle_ellipsis(s, max_chars)
  s = tostring(s or '')
  if max_chars <= 1 then return '…' end
  if #s <= max_chars then return s end
  local file = basename(s)
  if #file + 4 >= max_chars then
    local keep = math.max(1, max_chars - 2)
    local head = math.floor(keep / 2)
    local tail = keep - head
    return s:sub(1, head) .. '…' .. s:sub(#s - tail + 1)
  end
  local tail = math.min(#s, math.max(#file + 4, math.floor(max_chars * 0.62)))
  local head = max_chars - tail - 1
  if head < 2 then head = 2; tail = max_chars - head - 1 end
  return s:sub(1, head) .. '…' .. s:sub(#s - tail + 1)
end

local function subprocess(args)
  local ok, res = pcall(function()
    return utils.subprocess({args = args, cancellable = false})
  end)
  if not ok or type(res) ~= 'table' then return '' end
  if res.status == 0 then return (res.stdout or ''):gsub('%s+$', '') end
  return ''
end

local function is_url(path)
  return tostring(path or ''):match('^%a[%w+.-]*://') ~= nil
end

local function stat_mtime_ns(path)
  if not path or path == '' or is_url(path) then return nil end
  if stat_cache[path] ~= nil then return stat_cache[path] or nil end

  local out = subprocess({'stat', '-c', '%Y', '--', path})
  if out == '' then out = subprocess({'stat', '-f', '%m', '--', path}) end

  local seconds = tonumber(out)
  if seconds then
    local ns = seconds * 1000000000
    stat_cache[path] = ns
    return ns
  end

  stat_cache[path] = false
  return nil
end

local function current_path()
  return mp.get_property('path') or ''
end

local function file_id(path)
  if path == '' then return '' end
  if id_cache[path] ~= nil then return id_cache[path] or '' end
  if not meta_by_path then load_meta() end
  local rec = meta_by_path[path]
  if rec and rec.id and rec.id ~= '' then
    id_cache[path] = rec.id
    return rec.id
  end
  local id = subprocess({'stat', '-c', '%d:%i', '--', path})
  if id == '' then id_cache[path] = false else id_cache[path] = id end
  return id
end

local function tags_for_path_or_id(path, id)
  if not tag_cache or not tag_path_cache then load_tags() end
  local by_path = tag_path_cache[path]
  local by_id = (id and id ~= '') and tag_cache[id] or nil
  if by_id and #by_id > 0 then return by_id end
  return by_path or {}
end

local function ensure_sync_dir()
  utils.subprocess({args={'mkdir', '-p', sync_dir}, cancellable=false})
  local f = io.open(tag_file, 'r')
  if f then f:close(); return end
  f = io.open(tag_file, 'w')
  if f then f:write('id\tpath\ttag_name\tcount\tadded_at\tupdated_at\n'); f:close() end
end

local function sort_tags(t)
  table.sort(t, function(a,b)
    local order = {fav=90, del=91}
    local oa = tonumber(a) or order[a] or 99
    local ob = tonumber(b) or order[b] or 99
    if oa == ob then return a < b end
    return oa < ob
  end)
end

load_tags = function()
  local by_id = {}
  local by_path = {}
  local f = io.open(tag_file, 'r')
  if f then
    for line in f:lines() do
      local cols = {}
      for part in (line .. '\t'):gmatch('(.-)\t') do table.insert(cols, part) end
      if cols[1] ~= 'id' and cols[1] and cols[1] ~= '' and cols[3] and cols[3] ~= '' then
        by_id[cols[1]] = by_id[cols[1]] or {}
        table.insert(by_id[cols[1]], cols[3])
        if cols[2] and cols[2] ~= '' then
          by_path[cols[2]] = by_path[cols[2]] or {}
          table.insert(by_path[cols[2]], cols[3])
        end
      end
    end
    f:close()
  end
  for _, tags in pairs(by_id) do sort_tags(tags) end
  for _, tags in pairs(by_path) do sort_tags(tags) end
  tag_cache = by_id
  tag_path_cache = by_path
  return by_id
end

local function has_tag_list(tags, tag)
  for _, t in ipairs(tags or {}) do if t == tag then return true end end
  return false
end

local function path_has_tag(path, tag)
  if not tag_cache or not tag_path_cache then load_tags() end
  local by_path = tag_path_cache[path]
  if has_tag_list(by_path, tag) then return true end
  if not meta_by_path then load_meta() end
  local rec = meta_by_path[path]
  if rec and rec.id and has_tag_list(tag_cache[rec.id], tag) then return true end
  -- Do not stat every playlist item here. random video/image must stay fast.
  -- Current-file tag display and tag writes still use stat via file_id().
  return false
end

local function read_tags_for(id)
  if id == '' then return {} end
  if not tag_cache then load_tags() end
  return tag_cache[id] or {}
end

load_meta = function()
  local m = {}
  local f = io.open(meta_file, 'r')
  if not f then meta_by_path = m; return m end
  for line in f:lines() do
    local cols = {}
    for part in (line .. '\t'):gmatch('(.-)\t') do table.insert(cols, part) end
    if cols[1] ~= 'id' and cols[2] and cols[2] ~= '' then
      m[cols[2]] = {id=cols[1], kind=cols[6], mtime=tonumber(cols[4] or '') or nil}
    end
  end
  f:close()
  meta_by_path = m
  return m
end

local function kind_of(path)
  if not meta_by_path then load_meta() end
  local rec = meta_by_path[path]
  if rec and (rec.kind == 'video' or rec.kind == 'image') then return rec.kind end
  local e = ext_of(path)
  if video_ext[e] then return 'video' end
  if image_ext[e] then return 'image' end
  return 'other'
end

local function playlist_items()
  return mp.get_property_native('playlist') or {}
end

local function playlist_signature(items)
  local parts = { tostring(#items) }
  for _, item in ipairs(items) do
    local p = (item and item.filename) or ''
    parts[#parts + 1] = tostring(#p)
    parts[#parts + 1] = p
  end
  return table.concat(parts, '\0')
end

local function invalidate_index_cache()
  index_cache = nil
  newest_cache = nil
end

local function build_index_cache()
  local items = playlist_items()
  local c = { signature = playlist_signature(items), videos = {}, images = {} }
  for i, item in ipairs(items) do
    local p = (item and item.filename) or ''
    if path_has_tag(p, 'fav') then
      local kind = kind_of(p)
      if kind == 'video' then table.insert(c.videos, i - 1)
      elseif kind == 'image' then table.insert(c.images, i - 1) end
    end
  end
  index_cache = c
  return c
end

local function get_index_cache()
  local items = playlist_items()
  if not index_cache or index_cache.signature ~= playlist_signature(items) then return build_index_cache() end
  return index_cache
end

local function jump_to(index0)
  if index0 then mp.set_property_number('playlist-pos', index0) end
end

local function random_from_candidates(label, candidates)
  if not math_random_seeded then math.randomseed(os.time()); math_random_seeded = true end
  local cur = mp.get_property_number('playlist-pos', 0)
  if #candidates == 0 then mp.osd_message('no favorite ' .. label .. ' in playlist'); return end
  if #candidates == 1 then jump_to(candidates[1]); return end
  local idx = candidates[math.random(#candidates)]
  while idx == cur do idx = candidates[math.random(#candidates)] end
  jump_to(idx)
end

local function random_kind(kind)
  local c = get_index_cache()
  if kind == 'video' then random_from_candidates('video', c.videos)
  else random_from_candidates('image', c.images) end
end

local function build_newest_cache()
  local items = playlist_items()
  if not meta_by_path then load_meta() end
  local best_i, best_t = nil, nil
  for i, item in ipairs(items) do
    local p = (item and item.filename) or ''
    local t = nil
    local rec = meta_by_path[p]
    if rec and rec.mtime then t = rec.mtime end
    if not t then t = stat_mtime_ns(p) end
    if t and (not best_t or t > best_t) then best_t = t; best_i = i - 1 end
  end
  newest_cache = { signature = playlist_signature(items), index = best_i, mtime = best_t }
  return newest_cache
end

local function newest_in_playlist()
  local items = playlist_items()
  local c = newest_cache
  if not c or c.signature ~= playlist_signature(items) then c = build_newest_cache() end
  if c.index then jump_to(c.index) else mp.osd_message('newest: no stat/meta') end
end

function refresh_topbar()
  local ok, err = pcall(function()
    local path = current_path()
    local w = mp.get_property_number('osd-width', 0)
    if path == '' or w <= 0 then overlay.data = ''; overlay:update(); return end
    if not meta_by_path then load_meta() end
    local rec = meta_by_path[path]
    local id = rec and rec.id or ''
    -- Only stat for display when meta/path tag lookup cannot know tags. This keeps topbar refresh cheap.
    if id == '' and tag_path_cache == nil then load_tags() end
    local tags = tags_for_path_or_id(path, id)
    local tag_text = ''
    if #tags > 0 then tag_text = '    [' .. table.concat(tags, ',') .. ']' end
    local pos = (mp.get_property_number('playlist-pos', 0) or 0) + 1
    local total = mp.get_property_number('playlist-count', 1) or 1
    local right = '    [' .. tostring(pos) .. '/' .. tostring(total) .. ']'
    local font = 9
    local charw = font * 0.58
    -- Reserve room for four visible spaces before tags and four before right counter.
    local reserved_chars = #tag_text + #right + 16
    local max_chars = math.max(8, math.floor((w / charw) - reserved_chars))
    local p = middle_ellipsis(home_shorten(path), max_chars)
    local y = 4
    local ass = ''
    -- Text only: no semi-transparent bar. Border keeps it readable and prevents status sitting under a bar.
    ass = ass .. string.format('{\\an7\\pos(4,%d)\\fs%d\\bord1\\shad0\\1c&HFFFFFF&\\3c&H000000&\\alpha&H00&}%s%s', y, font, ass_escape(p), ass_escape(tag_text))
    ass = ass .. string.format('{\\an9\\pos(%d,%d)\\fs%d\\bord1\\shad0\\1c&HFFFFFF&\\3c&H000000&\\alpha&H00&}%s', w - 4, y, font, ass_escape(right))
    overlay.data = ass
    overlay:update()
  end)
  if not ok then
    overlay.data = ''
    overlay:update()
    mp.msg.error('tagbar refresh failed: ' .. tostring(err))
  end
end
local function update_tag(tag, remove)
  ensure_sync_dir()
  local path = current_path()
  if path == '' then return end
  if path:find('\t', 1, true) or path:find('\n', 1, true) then mp.osd_message('tag: bad path'); return end
  local id = file_id(path)
  if id == '' then mp.osd_message('tag: stat failed'); return end
  local now = tostring(os.time())
  local lines = {}
  local found = false
  local f = io.open(tag_file, 'r')
  if f then
    for line in f:lines() do
      local cols = {}
      for part in (line .. '\t'):gmatch('(.-)\t') do table.insert(cols, part) end
      if cols[1] == 'id' then
        table.insert(lines, line)
      elseif cols[1] == id and cols[3] == tag then
        found = true
        if not remove then
          local count = tonumber(cols[4] or '0') or 0
          cols[2] = path
          cols[4] = tostring(count + 1)
          cols[6] = now
          table.insert(lines, table.concat({cols[1], cols[2], cols[3], cols[4], cols[5] or now, cols[6]}, '\t'))
        end
      else
        table.insert(lines, line)
      end
    end
    f:close()
  end
  if #lines == 0 then table.insert(lines, 'id\tpath\ttag_name\tcount\tadded_at\tupdated_at') end
  if not found and not remove then
    table.insert(lines, table.concat({id, path, tag, '1', now, now}, '\t'))
  end
  local tmp = tag_file .. '.tmp.' .. tostring(os.time()) .. '.' .. tostring(math.random(100000))
  local wf = io.open(tmp, 'w')
  if not wf then mp.osd_message('tag: write failed'); return end
  for _, line in ipairs(lines) do wf:write(line, '\n') end
  wf:close()
  os.rename(tmp, tag_file)
  tag_cache = nil
  tag_path_cache = nil
  invalidate_index_cache()
  if remove then mp.osd_message('removed tag ' .. tag) else mp.osd_message('tagged ' .. tag) end
  refresh_topbar()
end

local function safe_binding(name, fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then
      if mp.msg and mp.msg.error then mp.msg.error('tagbar binding failed: ' .. name .. ': ' .. tostring(err)) end
      if mp.osd_message then mp.osd_message('tagbar: ' .. name .. ' failed') end
      refresh_topbar()
    end
  end
end

mp.add_key_binding(nil, 'random-video', safe_binding('random-video', function() random_kind('video') end), {repeatable=true})
mp.add_key_binding(nil, 'random-image', safe_binding('random-image', function() random_kind('image') end), {repeatable=true})
mp.add_key_binding(nil, 'newest', safe_binding('newest', newest_in_playlist), {repeatable=true})
mp.add_key_binding(nil, 'add-fav', safe_binding('add-fav', function() update_tag('fav', false) end))
mp.add_key_binding(nil, 'remove-fav', safe_binding('remove-fav', function() update_tag('fav', true) end))
mp.add_key_binding(nil, 'add-del', safe_binding('add-del', function() update_tag('del', false) end))
mp.add_key_binding(nil, 'remove-del', safe_binding('remove-del', function() update_tag('del', true) end))
for i=0,9 do
  local t = tostring(i)
  mp.add_key_binding(nil, 'add-tag-' .. t, safe_binding('add-tag-' .. t, function() update_tag(t, false) end))
  mp.add_key_binding(nil, 'remove-tag-' .. t, safe_binding('remove-tag-' .. t, function() update_tag(t, true) end))
end
mp.add_key_binding(nil, 'invalidate-cache', safe_binding('invalidate-cache', function()
  invalidate_index_cache()
  meta_by_path = nil
  tag_cache = nil
  tag_path_cache = nil
  id_cache = {}
  stat_cache = {}
end))

mp.register_event('file-loaded', refresh_topbar)
mp.observe_property('playlist-count', 'number', invalidate_index_cache)
mp.observe_property('playlist-pos', 'number', refresh_topbar)
mp.observe_property('osd-width', 'number', refresh_topbar)
