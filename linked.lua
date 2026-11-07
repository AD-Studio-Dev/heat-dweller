-- Linked enemy: a Pacer pair joined by a tether. Both halves are drawn from one
-- 64x32 frame and move together, pacing along one axis and bouncing off walls.
---@diagnostic disable: undefined-global
local Wet = require('wet')

local Linked = {}
Linked.__index = Linked

local SHEET_PATH = 'resources/gfx/enemies/spritesheets/enemies_007_linked.png'
local SHEET_W, SHEET_H = 256, 128
local CELL_W, CELL_H = 64, 32
local COLUMNS = 4
local SPRITE_SCALE = 2
local FPS = 10
local WALL_MARGIN = 64 + 24 + 32

local SPEED = 95
local TURN_MIN, TURN_MAX = 2.0, 5.0
local HALF_OFFSET = 44 -- screen px from the pair's center to each body

local image
local rows = { {}, {}, {}, {} } -- 4 frames per row
local quadsBuilt = false

local function buildQuads()
  if quadsBuilt then
    return
  end
  quadsBuilt = true
  for row = 0, 3 do
    for column = 0, COLUMNS - 1 do
      rows[row + 1][column + 1] = love.graphics.newQuad(
        column * CELL_W, row * CELL_H, CELL_W, CELL_H, SHEET_W, SHEET_H
      )
    end
  end
end

-- Call once from initializeMenu so the sheet is ready.
function Linked.load()
  buildQuads()
  if not image then
    image = love.graphics.newImage(SHEET_PATH)
    image:setFilter('nearest', 'nearest')
  end
end

local function pickDirection(self)
  local horizontal = love.math.random() < 0.5
  local sign = love.math.random() < 0.5 and -1 or 1
  self.dirX = horizontal and sign or 0
  self.dirY = horizontal and 0 or sign
  self.turnTimer = TURN_MIN + love.math.random() * (TURN_MAX - TURN_MIN)
end

function Linked.new(config)
  config = config or {}
  buildQuads()
  local self = setmetatable({
    kind = 'linked',
    selfDrawn = true,
    x = config.x or 800,
    y = config.y or 600,
    width = HALF_OFFSET * 2 + 64, -- hitbox covers both bodies
    height = 64,
    health = config.health or 10,
    maxHealth = config.health or 10,
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
  }, Linked)
  pickDirection(self)
  return self
end

function Linked:update(dt, player, world)
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
    local minY = WALL_MARGIN - 32
    if self.y < minY then
      self.y, self.dirY = minY, math.abs(self.dirY)
    elseif self.y > maxY then
      self.y, self.dirY = maxY, -math.abs(self.dirY)
    end
  end

  if player and self.attackCooldown <= 0 then
    for _, side in ipairs({ -1, 1 }) do
      local dx = player.x - (self.x + side * HALF_OFFSET)
      local dy = player.y - self.y
      if math.sqrt(dx * dx + dy * dy) <= self.contactRadius then
        player:takeDamage(self.damage)
        self.attackCooldown = self.attackInterval
        break
      end
    end
  end
  return nil
end

function Linked:draw(camera)
  if not self.alive then
    return
  end
  camera = camera or { x = 0, y = 0 }
  -- Rows 1-2: pacing horizontally; rows 3-4: pacing vertically.
  local first = self.dirX ~= 0 and 1 or 3
  local index = math.floor(self.animationTime * FPS) % (COLUMNS * 2)
  local row = rows[first + math.floor(index / COLUMNS)]
  local quad = row[index % COLUMNS + 1]
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image, quad,
    math.floor(self.x - camera.x), math.floor(self.y - camera.y),
    0, SPRITE_SCALE, SPRITE_SCALE, CELL_W / 2, CELL_H / 2
  )
end

return Linked