-- Aimless enemy: paces back and forth along one axis like a TBOI Pacer.
-- Ignores the player, bounces off walls, and hurts on contact.
---@diagnostic disable: undefined-global
local Wet = require('wet')

local Aimless = {}
Aimless.__index = Aimless

local SHEET_PATH = 'resources/gfx/enemies/spritesheets/enemies_006_aimless.png'
local SHEET_W, SHEET_H = 256, 128
local CELL = 32
local SPRITE_SCALE = 2
local FRAMES_PER_ROW = 8
local FPS = 12
local WALL_MARGIN = 64 + 24

local SPEED = 95
local TURN_MIN, TURN_MAX = 2.0, 5.0 -- seconds before it may swap axis/direction

local image
local rows = { {}, {} } -- row 1: Y=0 (vertical pacing), row 2: Y=32 (horizontal pacing)
local quadsBuilt = false

local function buildQuads()
  if quadsBuilt then
    return
  end
  quadsBuilt = true
  for row = 0, 1 do
    for column = 0, FRAMES_PER_ROW - 1 do
      rows[row + 1][column + 1] = love.graphics.newQuad(
        column * CELL, row * CELL, CELL, CELL, SHEET_W, SHEET_H
      )
    end
  end
end

-- Call once from initializeMenu so the sheet is ready.
function Aimless.load()
  buildQuads()
  if not image then
    image = love.graphics.newImage(SHEET_PATH)
    image:setFilter('nearest', 'nearest')
  end
end

local function pickDirection(self, keepAxis)
  local horizontal
  if keepAxis then
    horizontal = self.dirX ~= 0
  else
    horizontal = love.math.random() < 0.5
  end
  local sign = love.math.random() < 0.5 and -1 or 1
  self.dirX = horizontal and sign or 0
  self.dirY = horizontal and 0 or sign
  self.turnTimer = TURN_MIN + love.math.random() * (TURN_MAX - TURN_MIN)
end

function Aimless.new(config)
  config = config or {}
  buildQuads()
  local self = setmetatable({
    kind = 'aimless',
    selfDrawn = true,
    x = config.x or 800,
    y = config.y or 600,
    width = 64,
    height = 64,
    health = config.health or 7,
    maxHealth = config.health or 7,
    damage = config.damage or 0.5,
    speed = config.speed or SPEED,
    contactRadius = config.contactRadius or 44,
    attackCooldown = 0,
    attackInterval = 0.75,
    animationTime = 0,
    alive = true,
    dirX = 0,
    dirY = 0,
    turnTimer = 0,
  }, Aimless)
  pickDirection(self)
  return self
end

function Aimless:update(dt, player, world)
  if not self.alive then
    return nil
  end
  local speedScale = Wet.update(self, dt)
  self.animationTime = self.animationTime + dt
  self.attackCooldown = math.max(0, self.attackCooldown - dt)

  self.turnTimer = self.turnTimer - dt
  if self.turnTimer <= 0 then
    pickDirection(self)
  end

  self.x = self.x + self.dirX * self.speed * speedScale * dt
  self.y = self.y + self.dirY * self.speed * speedScale * dt

  if world then
    local maxX, maxY = world.width - WALL_MARGIN, world.height - WALL_MARGIN
    if self.x < WALL_MARGIN then
      self.x, self.dirX = WALL_MARGIN, math.abs(self.dirX)
    elseif self.x > maxX then
      self.x, self.dirX = maxX, -math.abs(self.dirX)
    end
    if self.y < WALL_MARGIN then
      self.y, self.dirY = WALL_MARGIN, math.abs(self.dirY)
    elseif self.y > maxY then
      self.y, self.dirY = maxY, -math.abs(self.dirY)
    end
  end

  if player then
    local dx, dy = player.x - self.x, player.y - self.y
    if math.sqrt(dx * dx + dy * dy) <= self.contactRadius and self.attackCooldown <= 0 then
      player:takeDamage(self.damage)
      self.attackCooldown = self.attackInterval
    end
  end
  return nil
end

function Aimless:draw(camera)
  if not self.alive then
    return
  end
  camera = camera or { x = 0, y = 0 }
  local row = rows[self.dirX ~= 0 and 2 or 1]
  local frame = math.floor(self.animationTime * FPS) % FRAMES_PER_ROW + 1
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image, row[frame],
    math.floor(self.x - camera.x), math.floor(self.y - camera.y),
    0, SPRITE_SCALE, SPRITE_SCALE, CELL / 2, CELL / 2
  )
end

return Aimless