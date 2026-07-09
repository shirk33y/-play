-- Adapted from occivink/mpv-image-viewer/scripts/detect-image.lua
-- Original project is released under the Unlicense; see licenses/mpv-image-viewer-UNLICENSE.

local options = require "mp.options"
local msg = require "mp.msg"

local opts = {
  command_on_first_image_loaded = "",
  command_on_image_loaded = "",
  command_on_non_image_loaded = "",
}

options.read_options(opts, nil, function() end)

local was_image = false
local properties = {}

local function run_maybe(command)
  if command ~= "" then mp.command(command) end
end

local function set_image(is_image)
  if is_image and not was_image then
    msg.info("First image detected")
    run_maybe(opts.command_on_first_image_loaded)
  end

  if is_image then
    msg.info("Image detected")
    run_maybe(opts.command_on_image_loaded)
  end

  if not is_image and was_image then
    msg.info("Non-image detected")
    run_maybe(opts.command_on_non_image_loaded)
  end

  was_image = is_image
end

local function properties_changed()
  local dwidth = properties["dwidth"]
  local tracks = properties["track-list"]
  local path = properties["path"]
  local framecount = properties["estimated-frame-count"]

  if not path or path == "" then return end
  if not tracks or #tracks == 0 then return end

  local audio_tracks = 0
  for _, track in ipairs(tracks) do
    if track.type == "audio" then audio_tracks = audio_tracks + 1 end
  end

  if not framecount and audio_tracks > 0 then
    set_image(false)
  elseif framecount and dwidth and dwidth > 0 then
    set_image((framecount == 0 or framecount == 1) and audio_tracks == 0)
  end
end

local function observe(propname)
  mp.observe_property(propname, "native", function(_, val)
    if val ~= properties[propname] then
      properties[propname] = val
      msg.verbose("Property " .. propname .. " changed")
      properties_changed()
    end
  end)
end

observe("estimated-frame-count")
observe("track-list")
observe("dwidth")
observe("path")
