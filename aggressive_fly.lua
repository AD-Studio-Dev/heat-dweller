-- Aggressive Fly: a Fly that never wanders and always chases the player.
-- Inherits its stats/fields (health, size, etc.) from fly.lua, then overrides
-- movement and drawing. Spawned by Panicker and Puffer instead of a plain Fly.
---@diagnostic disable: undefined-global
local Fly = require('fly')
local Wet = require('wet')

local AggressiveFly = {}
AggressiveFly.__index = AggressiveFly
setmetatable(AggressiveFly, { __index = Fly }) -- fall back to anything Fly defines

-- Sprite sheet: 128 x 64, 32 x 32 cells. Change SHEET_PATH if your file is named differently.
local SHEET_PATH = 'resources/gfx/enemies/spritesheets/enemies_011_aggressivefly.png'
local SHEET_W, SHEET_H = 128, 64
local CELL = 32
local FRAME_COUNT = 6 -- 4 on the top row, 2 on the bottom
local FPS = 14
local SPRITE_SCALE = 2

local CHASE_SPEED = 120 -- px/s; raise for a nastier fly
local CONTACT_RADIUS = 36
local CONTACT_DAMAGE = 0.5
local CONTACT_INTERVAL = 0.75

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
  local fly = Fly:new(x, y) -- base stats, health, size, etc.
  fly.kind = 'aggressivefly'
  fly.selfDrawn = true
  fly.alive = true
  fly.speed = CHASE_SPEED
  fly.animationTime = 0
  fly.attackCooldown = 0
  return setmetatable(fly, AggressiveFly)
end

function AggressiveFly:update(dt, player)
  if not self.alive then
    return nil
  end
  local speedScale = Wet.update(self, dt)
  self.animationTime = (self.animationTime or 0) + dt
  self.attackCooldown = math.max(0, (self.attackCooldown or 0) - dt)

  if player then
    local dx, dy = player.x - self.x, player.y - self.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > 0 then
      self.x = self.x + dx / distance * CHASE_SPEED * speedScale * dt
      self.y = self.y + dy / distance * CHASE_SPEED * speedScale * dt
    end
    if distance <= CONTACT_RADIUS and self.attackCooldown <= 0 then
      player:takeDamage(CONTACT_DAMAGE)
      self.attackCooldown = CONTACT_INTERVAL
    end
  end
  return nil
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