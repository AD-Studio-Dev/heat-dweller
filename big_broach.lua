-- Big Broach: a huge buzzing fly boss. Cycle: slow hover stalk (with orbiting shield
-- flies) -> full-body red flash telegraph -> short straight dash (ends by launching
-- 1-2 red chaser flies) -> brief recovery.
--
-- Sprite sheet: resources/gfx/bosses/big_broach.png, a horizontal strip of
-- eight equal frames (frameW = width / 8, frameH = height), nearest filtering, in pairs
-- (wings down, wings up): 1-2 front, 3-4 facing right, 5-6 facing left, 7-8 back.
--
-- Like sogface.lua, everything lives here and main.lua keeps one reference
-- (View.big_broach). Real fly enemies are created by main.lua: update() returns a list
-- of { type = 'fly' | 'aggressivefly', x = , y = } for main to turn into enemies.
---@diagnostic disable: undefined-global
local BigBroach = {}
BigBroach.__index = BigBroach

BigBroach.SHEET_PATH = 'resources/gfx/bosses/big_broach.png'
BigBroach.PORTRAIT_PATH = 'resources/gfx/ui/boss/portrait_big_broach.png'

local FRAME_COUNT = 8
local DIRECTION_INDEX = { front = 1, right = 2, left = 3, back = 4 }

-- Tuning ---------------------------------------------------------------------
local DRAW_SCALE = 3                 -- 64 px frame -> 192 px on screen
local RADIUS = 56                    -- body hitbox (circle)
local HEALTH_KITCHEN = 260           -- Floor 3
local HEALTH_BEDROOM = 320           -- Floor 4
local WALL_INSET = 64                -- one tile of wall frame around the room
local WALL_REACH = 0.75              -- fraction of RADIUS allowed to touch the wall

local STALK_TIME = 2.5
local TELEGRAPH_TIME = 0.65
local DASH_TIME = 0.4
local RECOVER_TIME = 0.8

local STALK_SPEED = 85               -- slow hover toward Matthew (px / s)
local STALK_ACCEL = 5                -- how quickly velocity follows the target
local DASH_MIN_SPEED, DASH_MAX_SPEED = 420, 700

-- Wing buzz: seconds per flap for each phase (smaller = faster).
local FLAP_NORMAL, FLAP_TELEGRAPH, FLAP_DASH = 0.085, 0.045, 0.04

local BOB_FREQ, BOB_AMOUNT = 6, 2    -- hover bob: sin(t * 6) * 2 px
local RED_PULSE_RATE = 16            -- red flash on/off steps per second
local HIT_FLASH_TIME = 0.12
local CONTACT_DAMAGE = 10            -- half a heart (20 HP per heart)
local CONTACT_COOLDOWN = 1.0

-- Orbiting shield flies
local ORBIT_CAP_KITCHEN, ORBIT_CAP_BEDROOM = 3, 4
local ORBIT_SPAWN_INTERVAL = 0.9     -- only while stalking
local ORBIT_SPEED = 2.4              -- rad / s
local ORBIT_LIFE_MIN, ORBIT_LIFE_MAX = 4.5, 6.5
local ORBIT_HEALTH = 10
local ORBIT_DISTANCE = RADIUS + 34

local RED_FLIES_MIN, RED_FLIES_MAX = 1, 2

-- Assets ---------------------------------------------------------------------

function BigBroach.loadAssets()
  if BigBroach.image ~= nil then
    return BigBroach.image or nil
  end
  BigBroach.image = false -- remember a failed load so we do not retry every spawn
  if not love.filesystem.getInfo(BigBroach.SHEET_PATH) then
    print('Big Broach sprite sheet missing: ' .. BigBroach.SHEET_PATH)
    return nil
  end
  local ok, image = pcall(love.graphics.newImage, BigBroach.SHEET_PATH)
  if not ok or not image then
    print('Big Broach sprite sheet could not be loaded: ' .. tostring(image))
    return nil
  end
  image:setFilter('nearest', 'nearest')
  local imageWidth, imageHeight = image:getWidth(), image:getHeight()
  BigBroach.frameW = imageWidth / FRAME_COUNT
  BigBroach.frameH = imageHeight
  BigBroach.quads = {}
  for index = 1, FRAME_COUNT do
    BigBroach.quads[index] = love.graphics.newQuad(
      (index - 1) * BigBroach.frameW, 0, BigBroach.frameW, BigBroach.frameH,
      imageWidth, imageHeight
    )
  end
  BigBroach.image = image
  return image
end

-- HP-bar icon / intro portrait: the dedicated portrait if it exists, else frame 1.
function BigBroach.getPortrait()
  if BigBroach.portrait ~= nil then
    return BigBroach.portrait or nil
  end
  BigBroach.portrait = false
  if love.filesystem.getInfo(BigBroach.PORTRAIT_PATH) then
    local ok, image = pcall(love.graphics.newImage, BigBroach.PORTRAIT_PATH)
    if ok and image then
      image:setFilter('nearest', 'nearest')
      BigBroach.portrait = image
      return image
    end
  end
  if not BigBroach.loadAssets() then
    return nil
  end
  local ok, image = pcall(function()
    local source = love.image.newImageData(BigBroach.SHEET_PATH)
    local frameW, frameH = math.floor(BigBroach.frameW), math.floor(BigBroach.frameH)
    local cropped = love.image.newImageData(frameW, frameH)
    cropped:paste(source, 0, 0, 0, 0, frameW, frameH)
    local portrait = love.graphics.newImage(cropped)
    portrait:setFilter('nearest', 'nearest')
    return portrait
  end)
  if ok then
    BigBroach.portrait = image
    return image
  end
  return nil
end

-- Orbiting shield fly (lightweight; becomes a real Fly enemy when it breaks off) -------

local OrbitFly = {}
OrbitFly.__index = OrbitFly

function OrbitFly:takeDamage(amount)
  if not self.alive then
    return false
  end
  self.hitFlashTimer = HIT_FLASH_TIME
  self.health = math.max(0, self.health - (amount or 0))
  if self.health <= 0 then
    self.alive = false
    return true
  end
  return false
end

function OrbitFly:isInvulnerable()
  return not self.alive
end

local function newOrbitFly(boss)
  return setmetatable({
    kind = 'broach_fly',
    alive = true,
    health = ORBIT_HEALTH,
    maxHealth = ORBIT_HEALTH,
    width = 22,
    height = 22,
    radius = 11,
    angle = math.random() * math.pi * 2,
    distance = ORBIT_DISTANCE + math.random(-8, 8),
    life = ORBIT_LIFE_MIN + math.random() * (ORBIT_LIFE_MAX - ORBIT_LIFE_MIN),
    flap = math.random() * 0.1,
    hitFlashTimer = 0,
    x = boss.x,
    y = boss.y,
  }, OrbitFly)
end

-- Construction ---------------------------------------------------------------

function BigBroach.new(world)
  BigBroach.loadAssets()
  local floorIndex = world.floorIndex or 3
  local bedroom = floorIndex >= 4
  local health = bedroom and HEALTH_BEDROOM or HEALTH_KITCHEN

  return setmetatable({
    kind = 'big_broach',
    world = world,
    x = world.width / 2,
    y = world.height / 2,
    width = RADIUS * 2,
    height = RADIUS * 2,
    radius = RADIUS,
    health = health,
    maxHealth = health,
    alive = true,
    ignoresObstacles = true, -- he flies over box blocks and furniture
    orbitCap = bedroom and ORBIT_CAP_BEDROOM or ORBIT_CAP_KITCHEN,
    vx = 0,
    vy = 0,
    state = 'stalk',
    stateDuration = STALK_TIME,
    stateTimer = STALK_TIME,
    stateElapsed = 0,
    animationTime = 0,
    facing = 'front',
    wingUp = false,
    flapTimer = 0,
    targetX = world.width / 2,
    targetY = world.height / 2,
    dashDirX = 0,
    dashDirY = 1,
    dashSpeed = 0,
    contactCooldown = 0,
    hitFlashTimer = 0,
    orbitSpawnTimer = 0.4,
    breakOffPending = false,
    flies = {},
  }, BigBroach)
end

-- Combat interface (same shape as the other bosses) --------------------------

function BigBroach:isInvulnerable()
  return not self.alive
end

-- Orbiting flies that are still alive: main.lua adds these to the shot / foam targets.
function BigBroach:getFlyTargets()
  return self.flies
end

-- Returns true when this hit kills it.
function BigBroach:takeDamage(amount)
  if not self.alive then
    return false
  end
  self.hitFlashTimer = HIT_FLASH_TIME
  self.health = math.max(0, self.health - (amount or 0))
  self.breakOffPending = true -- being hurt sets the shield flies loose
  if self.health <= 0 then
    self.alive = false
    self.flies = {}
    self.breakOffPending = false
    return true
  end
  return false
end

-- Facing -----------------------------------------------------------------------

-- Picks front / right / left / back from a direction. A little hysteresis stops the
-- sprite flickering when the two axes are nearly equal.
function BigBroach:updateFacing(dx, dy)
  if dx * dx + dy * dy < 1 then
    return
  end
  local horizontal = self.facing == 'left' or self.facing == 'right'
  local absX, absY = math.abs(dx), math.abs(dy)
  if horizontal then
    if absY > absX * 1.25 then
      self.facing = dy > 0 and 'front' or 'back'
    else
      self.facing = dx > 0 and 'right' or 'left'
    end
  else
    if absX > absY * 1.25 then
      self.facing = dx > 0 and 'right' or 'left'
    else
      self.facing = dy > 0 and 'front' or 'back'
    end
  end
end

-- State machine --------------------------------------------------------------

function BigBroach:setState(state, duration)
  self.state = state
  self.stateDuration = duration
  self.stateTimer = duration
  self.stateElapsed = 0
end

function BigBroach:clampToRoom()
  local world = self.world
  local reach = WALL_INSET + self.radius * WALL_REACH
  local minX, maxX = reach, world.width - reach
  local minY, maxY = reach, world.height - reach
  local clamped = false
  if self.x < minX then self.x, clamped = minX, true
  elseif self.x > maxX then self.x, clamped = maxX, true end
  if self.y < minY then self.y, clamped = minY, true
  elseif self.y > maxY then self.y, clamped = maxY, true end
  return clamped
end

local function releaseFly(spawns, fly)
  spawns[#spawns + 1] = { type = 'fly', x = fly.x, y = fly.y }
end

-- Advances Big Broach. Returns a list of enemies main.lua should create (maybe empty).
function BigBroach:update(dt, player, solids)
  local spawns = {}
  self.hitFlashTimer = math.max(0, self.hitFlashTimer - dt)
  if not self.alive then
    return spawns
  end

  self.animationTime = self.animationTime + dt
  self.stateElapsed = self.stateElapsed + dt
  self.stateTimer = self.stateTimer - dt
  self.contactCooldown = math.max(0, self.contactCooldown - dt)

  -- Wing buzz.
  local flapInterval = FLAP_NORMAL
  if self.state == 'telegraph' then
    flapInterval = FLAP_TELEGRAPH
  elseif self.state == 'dash' then
    flapInterval = FLAP_DASH
  end
  self.flapTimer = self.flapTimer + dt
  while self.flapTimer >= flapInterval do
    self.flapTimer = self.flapTimer - flapInterval
    self.wingUp = not self.wingUp
  end

  local toPlayerX, toPlayerY = 0, 0
  local distance = 0
  if player then
    toPlayerX, toPlayerY = player.x - self.x, player.y - self.y
    distance = math.sqrt(toPlayerX * toPlayerX + toPlayerY * toPlayerY)
  end

  local state = self.state
  if state == 'stalk' then
    -- Drift straight at Matthew, facing the way he moves.
    local playerRadius = player and math.max(player.width or 32, player.height or 32) / 2 or 0
    local wantX, wantY = 0, 0
    if distance > self.radius * 0.5 + playerRadius and distance > 0 then
      wantX, wantY = toPlayerX / distance * STALK_SPEED, toPlayerY / distance * STALK_SPEED
    end
    local follow = math.min(1, dt * STALK_ACCEL)
    self.vx = self.vx + (wantX - self.vx) * follow
    self.vy = self.vy + (wantY - self.vy) * follow
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    self:clampToRoom()
    self:updateFacing(wantX ~= 0 and wantX or toPlayerX, wantY ~= 0 and wantY or toPlayerY)

    -- Grow the orbiting shield, one fly at a time.
    self.orbitSpawnTimer = self.orbitSpawnTimer - dt
    if self.orbitSpawnTimer <= 0 and #self.flies < self.orbitCap then
      self.flies[#self.flies + 1] = newOrbitFly(self)
      self.orbitSpawnTimer = ORBIT_SPAWN_INTERVAL
    end

    if self.stateTimer <= 0 then
      -- Lock on to where Matthew stands right now.
      self.targetX, self.targetY = player and player.x or self.x, player and player.y or self.y
      self.vx, self.vy = 0, 0
      self:setState('telegraph', TELEGRAPH_TIME)
    end
  elseif state == 'telegraph' then
    -- Frozen in place; face the locked target.
    self.vx, self.vy = 0, 0
    self:updateFacing(self.targetX - self.x, self.targetY - self.y)
    if self.stateTimer <= 0 then
      local dx, dy = self.targetX - self.x, self.targetY - self.y
      local length = math.sqrt(dx * dx + dy * dy)
      if length < 1 then
        dx, dy, length = 0, 1, 1
      end
      self.dashDirX, self.dashDirY = dx / length, dy / length
      self.dashSpeed = math.max(DASH_MIN_SPEED,
        math.min(DASH_MAX_SPEED, length / DASH_TIME * 1.1))
      self:setState('dash', DASH_TIME)
      if self.onScreenShake then
        self.onScreenShake(3, 'big_broach_dash')
      end
    end
  elseif state == 'dash' then
    self.x = self.x + self.dashDirX * self.dashSpeed * dt
    self.y = self.y + self.dashDirY * self.dashSpeed * dt
    local hitWall = self:clampToRoom()
    self:updateFacing(self.dashDirX, self.dashDirY)
    if self.stateTimer <= 0 or hitWall then
      -- End of the dash: launch 1-2 red chaser flies forward.
      local count = math.random(RED_FLIES_MIN, RED_FLIES_MAX)
      for index = 1, count do
        local side = (index - (count + 1) / 2) * 34
        spawns[#spawns + 1] = {
          type = 'aggressivefly',
          x = self.x + self.dashDirX * self.radius * 0.9 - self.dashDirY * side,
          y = self.y + self.dashDirY * self.radius * 0.9 + self.dashDirX * side,
        }
      end
      self.vx, self.vy = 0, 0
      self:setState('recover', RECOVER_TIME)
      if self.onScreenShake then
        self.onScreenShake(4, 'big_broach_dash_end')
      end
    end
  elseif state == 'recover' then
    self.vx, self.vy = 0, 0
    self:updateFacing(toPlayerX, toPlayerY)
    if self.stateTimer <= 0 then
      self:setState('stalk', STALK_TIME)
      self.orbitSpawnTimer = 0.3
    end
  end

  -- Orbiting shield flies: circle him, break off after a while or when he is hurt.
  for index = #self.flies, 1, -1 do
    local fly = self.flies[index]
    fly.hitFlashTimer = math.max(0, fly.hitFlashTimer - dt)
    fly.flap = fly.flap + dt
    if not fly.alive then
      table.remove(self.flies, index)
    else
      fly.angle = fly.angle + ORBIT_SPEED * dt
      fly.life = fly.life - dt
      fly.x = self.x + math.cos(fly.angle) * fly.distance
      fly.y = self.y + math.sin(fly.angle) * fly.distance * 0.8
        + math.sin(self.animationTime * BOB_FREQ) * BOB_AMOUNT
      if self.breakOffPending or fly.life <= 0 then
        releaseFly(spawns, fly)
        table.remove(self.flies, index)
      end
    end
  end
  self.breakOffPending = false

  -- Touching the body hurts.
  if player and self.contactCooldown <= 0 then
    local playerRadius = math.max(player.width or 32, player.height or 32) / 2
    local contact = self.radius * 0.9 + playerRadius * 0.8
    if distance * distance <= contact * contact then
      player:takeDamage(CONTACT_DAMAGE)
      self.contactCooldown = CONTACT_COOLDOWN
    end
  end

  return spawns
end

-- Pose ------------------------------------------------------------------------

-- 1-based index into the eight-frame strip: pair per direction, down then up.
function BigBroach:getFrameIndex()
  local pair = DIRECTION_INDEX[self.facing] or 1
  return (pair - 1) * 2 + (self.wingUp and 2 or 1)
end

-- True on the "on" beats of the telegraph's red pulse.
function BigBroach:isRedFlashOn()
  return self.alive and self.state == 'telegraph'
    and math.floor(self.stateElapsed * RED_PULSE_RATE) % 2 == 0
end

-- Drawing ----------------------------------------------------------------------

local function drawOrbitFly(fly, cameraX, cameraY)
  local x = math.floor(fly.x - cameraX)
  local y = math.floor(fly.y - cameraY)
  local wingLift = (math.floor(fly.flap / 0.04) % 2 == 0) and -4 or 2
  love.graphics.setColor(0.9, 0.93, 0.95, 0.85)
  love.graphics.ellipse('fill', x - 6, y + wingLift, 6, 3.5)
  love.graphics.ellipse('fill', x + 6, y + wingLift, 6, 3.5)
  love.graphics.setColor(0.07, 0.06, 0.07, 1)
  love.graphics.circle('fill', x, y, 7)
  love.graphics.setColor(0.8, 0.12, 0.12, 1)
  love.graphics.rectangle('fill', x - 3, y - 1, 2, 2)
  love.graphics.rectangle('fill', x + 1, y - 1, 2, 2)
  if fly.hitFlashTimer > 0 then
    love.graphics.setBlendMode('add')
    love.graphics.setColor(1, 1, 1, math.min(1, fly.hitFlashTimer / HIT_FLASH_TIME))
    love.graphics.circle('fill', x, y, 8)
    love.graphics.setBlendMode('alpha')
  end
end

function BigBroach:draw(camera)
  local cameraX, cameraY = camera and camera.x or 0, camera and camera.y or 0
  local screenX = math.floor(self.x - cameraX)
  local screenY = math.floor(self.y - cameraY)
  local bob = math.floor(math.sin(self.animationTime * BOB_FREQ) * BOB_AMOUNT + 0.5)
  local bodyY = screenY + bob

  local alpha, scale = 1, DRAW_SCALE
  local scaleY = DRAW_SCALE
  if self.deathSequence then
    local sequence = self.deathSequence
    local progress = 1 - math.max(0, sequence.timer) / sequence.duration
    alpha = 1 - progress
    scale = DRAW_SCALE * (1 + progress * 0.25)
    scaleY = DRAW_SCALE * (1 - progress * 0.35)
  end

  -- Soft shadow so the hovering body reads against the floor.
  love.graphics.setColor(0, 0, 0, 0.25 * alpha)
  love.graphics.ellipse('fill', screenX, screenY + math.floor(self.radius * 1.05),
    self.radius * 0.85, 12)

  local image = BigBroach.image
  if image then
    local quad = BigBroach.quads[self:getFrameIndex()]
    local originX, originY = BigBroach.frameW / 2, BigBroach.frameH / 2
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(image, quad, screenX, bodyY, 0, scale, scaleY, originX, originY)
    -- The sprite is nearly black, so a multiply tint would barely show; the red warning
    -- and the hit flash are additive overlays of the same frame instead.
    if self:isRedFlashOn() then
      love.graphics.setBlendMode('add')
      love.graphics.setColor(1, 0.25, 0.25, 0.9)
      love.graphics.draw(image, quad, screenX, bodyY, 0, scale, scaleY, originX, originY)
      love.graphics.setBlendMode('alpha')
    end
    if self.hitFlashTimer > 0 then
      love.graphics.setBlendMode('add')
      love.graphics.setColor(1, 1, 1, math.min(1, self.hitFlashTimer / HIT_FLASH_TIME) * alpha)
      love.graphics.draw(image, quad, screenX, bodyY, 0, scale, scaleY, originX, originY)
      love.graphics.setBlendMode('alpha')
    end
  else
    -- Sprite sheet missing: a plain dark blob so the fight is still playable.
    love.graphics.setColor(self:isRedFlashOn() and 0.8 or 0.1, 0.05, 0.05, alpha)
    love.graphics.circle('fill', screenX, bodyY, self.radius)
  end

  for _, fly in ipairs(self.flies) do
    drawOrbitFly(fly, cameraX, cameraY)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return BigBroach