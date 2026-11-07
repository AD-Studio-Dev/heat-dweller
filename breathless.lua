-- Breathless enemy (shared logic for Breathless, Panicker and Puffer).
-- Flees the player and drops a fly every few seconds. Below 50% health the head
-- breaks off as a crying, tear-shooting drifter and the body wanders blindly.
-- panicker.lua and puffer.lua only pick a different sprite sheet.
---@diagnostic disable: undefined-global
local Breathless = {}
Breathless.__index = Breathless

-- Same 256 x 128 layout for every variant (see enemies_008-0010.json).
local SHEET_PATHS = {
  breathless = 'resources/gfx/enemies/spritesheets/enemies_008_breathless.png',
  panicker = 'resources/gfx/enemies/spritesheets/enemies_009_panicker.png',
  puffer = 'resources/gfx/enemies/spritesheets/enemies_010_puffer.png',
}
local SHEET_W, SHEET_H = 256, 128
local CELL = 32
local SPRITE_SCALE = 2
-- Head lift in pixels above the body's origin (spritesheet default was 6; +16 raises it higher). Change this to adjust.
local HEAD_OFFSET_Y = 22
local WALL_MARGIN = 64 + 24

local HEAD_FPS = 10
local FORWARD_FPS = 12
local SIDE_FPS = 12

local FLEE_SPEED = 120
local WANDER_SPEED = 55
local SPAWN_INTERVAL = 3.0
local SPAWN_PAUSE = 0.4
local MOVE_EPSILON = 0.01

local HEAD_DRIFT_SPEED = 45
local HEAD_RADIUS = 22
local HEAD_CONTACT_DAMAGE = 0.5
local TEAR_INTERVAL = 1.4
local TEAR_SPEED = 230
local TEAR_RADIUS = 7
local TEAR_DAMAGE = 0.5
local TEAR_LIFETIME = 3

local images = {} -- one image per variant, loaded on first use
local headQuads = {}
local forwardQuads = {}
local sideQuads = {}
local quadsBuilt = false

local function quad(x, y)
  return love.graphics.newQuad(x, y, CELL, CELL, SHEET_W, SHEET_H)
end

local function buildQuads()
  if quadsBuilt then
    return
  end
  quadsBuilt = true

  -- Head Frame 1..6: row Y=0, X=0..160.
  for index = 0, 5 do
    headQuads[index + 1] = quad(index * CELL, 0)
  end

  -- Body Forward Walk 1..9: (192,0), (224,0), then row Y=32, X=0..192.
  forwardQuads[1] = quad(192, 0)
  forwardQuads[2] = quad(224, 0)
  for index = 0, 6 do
    forwardQuads[3 + index] = quad(index * CELL, 32)
  end

  -- Body Right Walk 1..7: (224,32), then row Y=64, X=0..160.
  sideQuads[1] = quad(224, 32)
  for index = 0, 5 do
    sideQuads[2 + index] = quad(index * CELL, 64)
  end
end

local function getImage(kind)
  local image = images[kind]
  if not image then
    local path = SHEET_PATHS[kind] or SHEET_PATHS.breathless
    image = love.graphics.newImage(path)
    image:setFilter('nearest', 'nearest')
    images[kind] = image
  end
  return image
end

-- Call once from love.load / initializeMenu so the sheets are ready.
function Breathless.load()
  buildQuads()
  for kind in pairs(SHEET_PATHS) do
    getImage(kind)
  end
end

function Breathless.new(config)
  config = config or {}
  buildQuads()
  local health = config.health or 10
  local kind = config.kind or 'breathless'
  return setmetatable({
    kind = kind,
    selfDrawn = true, -- main.lua calls enemy:draw(camera) instead of renderer:drawEnemy
    x = config.x or 1100,
    y = config.y or 600,
    width = 64,
    height = 64,
    health = health,
    maxHealth = config.maxHealth or health,
    alive = true,
    state = 'fleeing', -- fleeing | spawning | wandering
    vx = 0,
    vy = 0,
    animationTime = 0,
    headTime = 0,
    spawnTimer = SPAWN_INTERVAL,
    pauseTimer = 0,
    decapitated = false,
    head = nil,
    tears = {},
    wanderTimer = 0,
    attackCooldown = 0,
    damage = config.damage or 0.5,
    contactRadius = config.contactRadius or 40,
  }, Breathless)
end

local function clampToRoom(self, world)
  self.x = math.max(WALL_MARGIN, math.min(world.width - WALL_MARGIN, self.x))
  self.y = math.max(WALL_MARGIN, math.min(world.height - WALL_MARGIN, self.y))
end

local function pickWanderDirection(self)
  local angle = love.math.random() * math.pi * 2
  self.vx = math.cos(angle) * WANDER_SPEED
  self.vy = math.sin(angle) * WANDER_SPEED
  self.wanderTimer = 0.6 + love.math.random() * 1.2
  if love.math.random() < 0.2 then -- clumsy pauses
    self.vx, self.vy = 0, 0
  end
end

function Breathless:decapitate()
  self.decapitated = true
  self.state = 'wandering'
  self.pauseTimer = 0
  local angle = love.math.random() * math.pi * 2
  self.head = {
    x = self.x,
    y = math.floor(self.y - HEAD_OFFSET_Y),
    vx = math.cos(angle) * HEAD_DRIFT_SPEED,
    vy = math.sin(angle) * HEAD_DRIFT_SPEED,
    tearTimer = 0.8,
    animationTime = 0,
    contactCooldown = 0,
  }
  pickWanderDirection(self)
end

local function updateHead(self, dt, player, world)
  local head = self.head
  head.animationTime = head.animationTime + dt
  head.contactCooldown = math.max(0, head.contactCooldown - dt)
  head.x = head.x + head.vx * dt
  head.y = head.y + head.vy * dt

  local minX, maxX = WALL_MARGIN, world.width - WALL_MARGIN
  local minY, maxY = WALL_MARGIN, world.height - WALL_MARGIN
  if head.x < minX then
    head.x, head.vx = minX, math.abs(head.vx)
  elseif head.x > maxX then
    head.x, head.vx = maxX, -math.abs(head.vx)
  end
  if head.y < minY then
    head.y, head.vy = minY, math.abs(head.vy)
  elseif head.y > maxY then
    head.y, head.vy = maxY, -math.abs(head.vy)
  end

  head.tearTimer = head.tearTimer - dt
  if head.tearTimer <= 0 then
    head.tearTimer = TEAR_INTERVAL
    local dx, dy = player.x - head.x, player.y - head.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > 0 then
      self.tears[#self.tears + 1] = {
        x = head.x,
        y = head.y + 8,
        vx = dx / distance * TEAR_SPEED,
        vy = dy / distance * TEAR_SPEED,
        life = TEAR_LIFETIME,
      }
    end
  end

  local dx, dy = player.x - head.x, player.y - head.y
  if head.contactCooldown <= 0 and dx * dx + dy * dy <= (HEAD_RADIUS + 20) ^ 2 then
    player:takeDamage(HEAD_CONTACT_DAMAGE)
    head.contactCooldown = 0.75
  end
end

local function updateTears(self, dt, player, world)
  for index = #self.tears, 1, -1 do
    local tear = self.tears[index]
    tear.x = tear.x + tear.vx * dt
    tear.y = tear.y + tear.vy * dt
    tear.life = tear.life - dt

    local remove = tear.life <= 0
      or tear.x < 64 or tear.x > world.width - 64
      or tear.y < 64 or tear.y > world.height - 64
    if not remove then
      local dx, dy = player.x - tear.x, player.y - tear.y
      if dx * dx + dy * dy <= (TEAR_RADIUS + 20) ^ 2 then
        player:takeDamage(TEAR_DAMAGE)
        remove = true
      end
    end
    if remove then
      table.remove(self.tears, index)
    end
  end
end

-- Returns a list of spawned enemies (main.lua appends them to the room).
function Breathless:update(dt, player, world)
  if not self.alive then
    return nil
  end

  local spawned
  self.animationTime = self.animationTime + dt
  self.headTime = self.headTime + dt
  self.attackCooldown = math.max(0, self.attackCooldown - dt)

  if not self.decapitated and self.health < self.maxHealth * 0.5 then
    self:decapitate()
  end

  if self.state == 'fleeing' then
    -- Exact inverse of the direction toward the player.
    local toTargetX, toTargetY = player.x - self.x, player.y - self.y
    local distance = math.sqrt(toTargetX * toTargetX + toTargetY * toTargetY)
    if distance > 0 then
      self.vx = -toTargetX / distance * FLEE_SPEED
      self.vy = -toTargetY / distance * FLEE_SPEED
    else
      self.vx, self.vy = 0, 0
    end
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    clampToRoom(self, world)

    self.spawnTimer = self.spawnTimer - dt
    if self.spawnTimer <= 0 then
      self.state = 'spawning'
      self.pauseTimer = SPAWN_PAUSE
      self.vx, self.vy = 0, 0
      -- Breathless spawns plain flies; Panicker and Puffer spawn Aggressive Flies.
      local FlyClass = require(self.kind == 'breathless' and 'fly' or 'aggressive_fly')
      spawned = { FlyClass:new(self.x, self.y) }
    end
  elseif self.state == 'spawning' then
    self.vx, self.vy = 0, 0
    self.pauseTimer = self.pauseTimer - dt
    if self.pauseTimer <= 0 then
      self.state = 'fleeing'
      self.spawnTimer = SPAWN_INTERVAL
    end
  elseif self.state == 'wandering' then
    self.wanderTimer = self.wanderTimer - dt
    if self.wanderTimer <= 0 then
      pickWanderDirection(self)
    end
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    local beforeX, beforeY = self.x, self.y
    clampToRoom(self, world)
    if self.x ~= beforeX then self.vx = -self.vx end
    if self.y ~= beforeY then self.vy = -self.vy end

    -- Blind body still hurts on contact.
    local dx, dy = player.x - self.x, player.y - self.y
    if self.attackCooldown <= 0 and dx * dx + dy * dy <= self.contactRadius ^ 2 then
      player:takeDamage(self.damage)
      self.attackCooldown = 0.75
    end
  end

  if self.head then
    updateHead(self, dt, player, world)
  end
  updateTears(self, dt, player, world)

  return spawned
end

local function isMoving(self)
  return math.abs(self.vx) > MOVE_EPSILON or math.abs(self.vy) > MOVE_EPSILON
end

local function headFrameIndex(moving, time)
  if not moving then
    return 1 -- Head Frame 1 only while idle
  end
  return 2 + math.floor(time * HEAD_FPS) % 5 -- Head Frame 2..6
end

function Breathless:getBodyQuad()
  if math.abs(self.vx) > math.abs(self.vy) then
    local index = math.floor(self.animationTime * SIDE_FPS) % #sideQuads + 1
    return sideQuads[index], self.vx > 0 and -SPRITE_SCALE or SPRITE_SCALE
  end
  local index = math.floor(self.animationTime * FORWARD_FPS) % #forwardQuads + 1
  return forwardQuads[index], SPRITE_SCALE
end

function Breathless:draw(camera)
  if not self.alive then
    return
  end
  camera = camera or { x = 0, y = 0 }
  local image = getImage(self.kind)

  love.graphics.setColor(1, 1, 1, 1)
  local bodyQuad, scaleX
  if isMoving(self) then
    bodyQuad, scaleX = self:getBodyQuad()
  else
    bodyQuad, scaleX = forwardQuads[1], SPRITE_SCALE
  end
  local bodyX = math.floor(self.x - camera.x)
  local bodyY = math.floor(self.y - camera.y)
  love.graphics.draw(image, bodyQuad, bodyX, bodyY, 0, scaleX, SPRITE_SCALE, CELL / 2, CELL / 2)

  if not self.decapitated then
    local headY = math.floor(self.y - HEAD_OFFSET_Y)
    local frame = headFrameIndex(isMoving(self), self.headTime)
    love.graphics.draw(
      image, headQuads[frame], bodyX, math.floor(headY - camera.y),
      0, scaleX, SPRITE_SCALE, CELL / 2, CELL / 2
    )
  elseif self.head then
    -- Detached head: no offset, always crying/animated.
    local head = self.head
    local frame = 2 + math.floor(head.animationTime * HEAD_FPS) % 5
    love.graphics.draw(
      image, headQuads[frame], math.floor(head.x - camera.x), math.floor(head.y - camera.y),
      0, SPRITE_SCALE, SPRITE_SCALE, CELL / 2, CELL / 2
    )
  end

  for _, tear in ipairs(self.tears) do
    love.graphics.setColor(0.45, 0.75, 1, 0.95)
    love.graphics.circle('fill', math.floor(tear.x - camera.x), math.floor(tear.y - camera.y), TEAR_RADIUS)
    love.graphics.setColor(0.85, 0.95, 1, 0.9)
    love.graphics.circle('fill', math.floor(tear.x - camera.x) - 2, math.floor(tear.y - camera.y) - 2, 2)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Breathless