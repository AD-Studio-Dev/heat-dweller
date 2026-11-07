-- Aggressive Fly: behaves exactly like a regular Fly (appear animation, drifting
-- physics with acceleration and drag, periodic dash, recovery, contact damage),
-- except that when it is "tracking" it homes in on the player instead of
-- wandering to random points. Only the sprite sheet and the chase differ.
-- Spawned by Panicker and Puffer instead of a plain Fly.
---@diagnostic disable: undefined-global
local Fly = require('fly')

local AggressiveFly = {}
AggressiveFly.__index = AggressiveFly
setmetatable(AggressiveFly, { __index = Fly }) -- everything not overridden comes from Fly

-- Sprite sheet: 128 x 64, 32 x 32 cells. Change SHEET_PATH if your file is named differently.
local SHEET_PATH = 'resources/gfx/enemies/spritesheets/enemies_011_aggressivefly.png'
local SHEET_W, SHEET_H = 128, 64
local CELL = 32
local FRAME_COUNT = 6 -- 4 on the top row, 2 on the bottom
local FPS = 14
local SPRITE_SCALE = 2

local image
local quads = {}

function AggressiveFly.load()
  if image then
    return
  end
  image = love.graphics.newImage(SHEET_PATH)
  image:setFilter('nearest', 'nearest')
  for index = 0, FRAME_COUNT - 1 do
    quads[index + 1] = love.graphics.newQuad(
      (index % 4) * CELL, math.floor(index / 4) * CELL, CELL, CELL, SHEET_W, SHEET_H
    )
  end
end

-- Same constructor shape as Fly: AggressiveFly:new(x, y)
function AggressiveFly:new(x, y)
  AggressiveFly.load()
  local fly = Fly:new(x, y) -- same stats, health, speed, dash timings as a regular Fly
  fly.kind = 'aggressivefly'
  fly.selfDrawn = true
  fly.animationTime = 0
  return setmetatable(fly, AggressiveFly)
end

-- Fly:update calls updateDrift() to pick a direction while tracking. A regular fly
-- picks random points to wander to; this one heads straight for the player.
function AggressiveFly:updateDrift()
  local target = self.chaseTarget
  if not target then
    return 0, 0
  end
  local dx, dy = target.x - self.x, target.y - self.y
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance > 0 then
    return dx / distance, dy / distance
  end
  return 0, 0
end

function AggressiveFly:update(dt, player, world)
  self.chaseTarget = player
  self.animationTime = (self.animationTime or 0) + dt
  return Fly.update(self, dt, player, world)
end

function AggressiveFly:draw(camera)
  if not self.alive then
    return
  end
  camera = camera or { x = 0, y = 0 }
  local frame = math.floor(self.animationTime * FPS) % FRAME_COUNT + 1
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image, quads[frame],
    math.floor(self.x - camera.x), math.floor(self.y - camera.y),
    0, SPRITE_SCALE, SPRITE_SCALE, CELL / 2, CELL / 2
  )
end

return AggressiveFly