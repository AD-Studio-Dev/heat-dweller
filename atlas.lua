-- Character atlas data and LÖVE Quad creation.
--
-- Matthew's sheet is an 832 x 32 strip of 32 x 32 frames described by
-- characters_001_matthew.json. Sheets that are not that strip (the sky/angel
-- form is still the old 40 x 40 grid) are drawn through a small legacy layout
-- so they keep working until they are redrawn.
---@diagnostic disable: undefined-global
local Json = require('json')

local STRIP_WIDTH, STRIP_HEIGHT = 832, 32
local FRAME_SIZE = 32
local DEFAULT_FRAME_SECONDS = 0.1

-- Left-to-right order of the strip; only used if the JSON cannot be read.
local function stripOrder()
  local order = {
    'head_forward', 'head_forward_blink',
    'head_right', 'head_right_blink',
    'head_back', 'head_back_blink',
    'pickup_head', 'hurt_head', 'death_head',
  }
  for index = 0, 7 do order[#order + 1] = 'walk_forward_' .. index end
  for index = 0, 6 do order[#order + 1] = 'walk_right_' .. index end
  order[#order + 1] = 'pickup_1'
  order[#order + 1] = 'pickup_2'
  return order
end

-- Old 40 x 40 grid (sky/angel form).
local function legacyFrames()
  local frames = {}
  local function add(name, x, y)
    frames[name] = { x = x, y = y, w = 40, h = 40, duration = DEFAULT_FRAME_SECONDS }
  end
  add('head_forward_1', 0, 0);   add('head_forward_blink', 40, 0)
  add('head_right_1', 80, 0);    add('head_right_blink', 120, 0)
  add('head_back_1', 160, 0);    add('head_back_blink', 200, 0)
  add('body_idle', 0, 40)
  for index = 0, 4 do add('walk_down_' .. index, 40 + index * 40, 40) end
  add('walk_right_0', 120, 80); add('walk_right_1', 160, 80); add('walk_right_2', 200, 80)
  add('walk_right_3', 0, 120);  add('walk_right_4', 40, 120)
  add('walk_right_5', 80, 120); add('walk_right_6', 120, 120)
  return frames
end

-- New frame name -> legacy frame name (poses the old sheet lacks fall back to
-- the closest plain frame).
local function legacyName(name)
  local walkIndex = name:match('^walk_forward_(%d+)$')
  if walkIndex then
    return 'walk_down_' .. (tonumber(walkIndex) % 5)
  end
  if name == 'head_forward' or name == 'head_right' or name == 'head_back'
      or name == 'hurt_head' or name == 'death_head' or name == 'pickup_head' then
    return (name == 'head_right' or name == 'head_back') and (name .. '_1') or 'head_forward_1'
  end
  if name == 'pickup_1' or name == 'pickup_2' then
    return 'body_idle'
  end
  return name
end

-- Row (in the 32 px cell) where each body pose's collar starts. The head is
-- pinned so its bottom edge overlaps the collar by HEAD_COLLAR_OVERLAP pixels.
local BODY_COLLAR_ROW = {
  walk_forward_3 = 12, walk_forward_7 = 12,
  walk_right_1 = 12, walk_right_4 = 12,
  pickup_1 = 11,
}
local DEFAULT_COLLAR_ROW = 10
local HEAD_BOTTOM_ROW = 30      -- head sprites end on row 30 (30x28, rows 2..29)
local HEAD_COLLAR_OVERLAP = 3

local Atlas = {
  imagePath = 'resources/gfx/characters/characters_001_matthew.png',
  jsonPath = 'resources/gfx/characters_001_matthew.json',
  layout = 'strip',
  frameSize = FRAME_SIZE,
  stripFrames = nil,
  frames = nil,
  tags = {},
}

function Atlas:loadStripData()
  if self.stripFrames then
    return
  end

  local frames, tags
  if love.filesystem.getInfo(self.jsonPath) then
    local contents = love.filesystem.read(self.jsonPath)
    local decoded, data = pcall(Json.decode, contents or '')
    if decoded and type(data) == 'table' and type(data.frames) == 'table' then
      frames = {}
      for name, entry in pairs(data.frames) do
        local rect = type(entry) == 'table' and entry.frame
        if type(rect) == 'table' then
          frames[name] = {
            x = rect.x, y = rect.y, w = rect.w, h = rect.h,
            duration = (tonumber(entry.duration) or DEFAULT_FRAME_SECONDS * 1000) / 1000,
          }
        end
      end
      tags = data.meta and data.meta.frameTags or {}
    else
      print('Character JSON could not be read: ' .. tostring(data))
    end
  else
    print('Missing character JSON, using built-in layout: ' .. self.jsonPath)
  end

  if not frames or next(frames) == nil then
    frames = {}
    for index, name in ipairs(stripOrder()) do
      frames[name] = {
        x = (index - 1) * FRAME_SIZE, y = 0, w = FRAME_SIZE, h = FRAME_SIZE,
        duration = DEFAULT_FRAME_SECONDS,
      }
    end
    tags = {}
  end

  self.stripFrames = frames
  self.tags = tags
end

function Atlas:load()
  self:loadStripData()
  self.image = love.graphics.newImage(self.imagePath)
  self.image:setFilter('nearest', 'nearest')
  local imageWidth, imageHeight = self.image:getDimensions()

  if imageWidth == STRIP_WIDTH and imageHeight == STRIP_HEIGHT then
    self.layout = 'strip'
    self.frames = self.stripFrames
    self.frameSize = FRAME_SIZE
  else
    self.layout = 'legacy'
    self.frames = legacyFrames()
    self.frameSize = 40
  end

  for _, frame in pairs(self.frames) do
    frame.quad = love.graphics.newQuad(
      frame.x, frame.y, frame.w, frame.h, imageWidth, imageHeight
    )
  end

  return self
end

-- Returns the frame for a strip-layout name, whatever sheet is loaded.
function Atlas:getFrame(name)
  if not self.frames then
    return nil
  end
  if self.layout == 'legacy' then
    return self.frames[legacyName(name)]
  end
  return self.frames[name]
end

-- Vertical offset (in sprite pixels) that seats the head on a given body pose.
-- Legacy heads were drawn pre-aligned, so they need none.
function Atlas:getHeadOffset(bodyFrameName)
  if self.layout == 'legacy' then
    return 0
  end
  local collarRow = BODY_COLLAR_ROW[bodyFrameName] or DEFAULT_COLLAR_ROW
  return collarRow + HEAD_COLLAR_OVERLAP - HEAD_BOTTOM_ROW
end

-- True when another sheet (a costume) shares this atlas's frame layout.
function Atlas:matchesLayout(image)
  if not image or not self.image then
    return false
  end
  local width, height = image:getDimensions()
  local atlasWidth, atlasHeight = self.image:getDimensions()
  return width == atlasWidth and height == atlasHeight
end

return Atlas