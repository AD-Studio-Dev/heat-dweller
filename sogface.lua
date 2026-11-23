-- Sogface: a floating boss that bounces diagonally around the room, then puffs
-- its cheeks and spits a burst of water.
--
-- Sprite sheet: resources/gfx/bosses/sogface.png, a horizontal strip
-- of six equal frames (frameW = width / 6, frameH = height), nearest filtering:
--   1 idle squished (wide grin)      2 idle stretched (tall grin)
--   3 puffed-cheek wind-up           4 small "O" transition
--   5 wide-open "O" spit             6 post-spit exhausted hold
--
-- Variant: 25% of spawns are the Sewer Champion (resources/gfx/bosses/sogface_sewer.png,
-- same six-frame layout): +25% max HP, murky olive tears, and one guaranteed bonus
-- pickup on defeat (main.lua reads `bonusPickup`).
--
-- Sound effects (resources/sfx/, loaded once when this module is first required):
--   sogface_inhale.wav / sogface_inhale_2.wav  cheek-puff telegraph (frames 3-4)
--   sogface_spit.wav / sogface_spit_2.wav      the spit burst (frames 5-6)
--
-- Everything lives in this module (state, projectiles, puddles, drawing) so
-- main.lua only needs one reference (View.sogface) and no new top-level locals.
---@diagnostic disable: undefined-global
local Sogface = {}
Sogface.__index = Sogface

Sogface.SHEET_PATHS = {
  normal = 'resources/gfx/bosses/sogface.png',
  sewer = 'resources/gfx/bosses/sogface_sewer.png',
}
Sogface.SHEET_PATH = Sogface.SHEET_PATHS.normal
Sogface.VARIANT_NORMAL, Sogface.VARIANT_SEWER = 'normal', 'sewer'

local FRAME_COUNT = 6
local FRAME_IDLE_WIDE, FRAME_IDLE_TALL = 1, 2
local FRAME_WINDUP, FRAME_POP, FRAME_SPIT, FRAME_EXHAUSTED = 3, 4, 5, 6

-- Tuning ---------------------------------------------------------------------
local DRAW_SCALE = 3              -- 64 px frame -> 192 px on screen
local RADIUS = 68                 -- body hitbox (circle)
local BASE_HEALTH = 160           -- Basement (Crawler 140 < Sogface < Lil' Snake 180)
local FLOOR_TWO_HEALTH = 200      -- Living Room
local WALL_INSET = 64             -- one tile of wall frame around the room
local WALL_REACH = 0.75           -- fraction of RADIUS allowed to touch the wall

local SPEED_X, SPEED_Y = 140, 110 -- steady diagonal drift (px / s)
local SLOW_FACTOR = 0.25          -- drift speed during wind-up / spit / exhaustion

local IDLE_MIN, IDLE_MAX = 3.5, 4.5
local WINDUP_TIME = 2.0
local POP_TIME = 0.08
local SPIT_TIME = 0.25
local EXHAUST_TIME = 2.0
local EXHAUST_RAMP = 0.4          -- last part of the hold eases speed back up

local WATER_COLOR = { 0.31, 0.765, 0.969 }   -- #4FC3F7
local WATER_DARK = { 0.12, 0.5, 0.8 }
local WATER_SHINE = { 0.85, 0.96, 1 }
-- Sewer Champion: murky olive tears, with a darker rim and a dull highlight.
local SEWER_COLOR = { 0.48, 0.55, 0.41 }
local SEWER_DARK = { 0.29, 0.33, 0.25 }
local SEWER_SHINE = { 0.78, 0.84, 0.7 }
local SEWER_CHANCE = 0.25             -- chance a spawned Sogface is the Sewer Champion
local SEWER_HEALTH_MULTIPLIER = 1.25  -- +25% max HP
local RING_COUNT, RING_SPEED = 8, 250
local FAN_COUNT, FAN_SPREAD, FAN_SPEED = 5, 0.24, 300
local PROJECTILE_RADIUS = 11
local PROJECTILE_LIFE = 3.4
local PROJECTILE_DAMAGE = 10      -- half a heart (20 HP per heart)
local CONTACT_DAMAGE = 10
local CONTACT_COOLDOWN = 1.0
local MAX_PUDDLES = 36
local PUDDLE_LIFE = 4.0

local IDLE_FREQ = 5               -- idle squash / stretch speed (rad / s)
local IDLE_AMPLITUDE = 0.16       -- idle scaleX / scaleY swing
local IDLE_BOB = 3                -- idle vertical float, in px
-- Wall-bounce jelly: a damped spring on the scale offsets. Stiffness sets how fast it
-- wobbles, damping how quickly it settles (lower damping = more wobbles).
local IMPACT_AMOUNT = 0.34
local IMPACT_STIFFNESS = 260
local IMPACT_DAMPING = 9
local IMPACT_LIMIT = 0.5
local HIT_FLASH_TIME = 0.12

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Sound effects ----------------------------------------------------------------

-- Static sources, loaded once at module startup. A missing file only means no sound.
local function loadSfx(path)
  if not (love and love.audio and love.filesystem) then
    return nil
  end
  if not love.filesystem.getInfo(path) then
    print('Sogface sound effect missing: ' .. path)
    return nil
  end
  local ok, source = pcall(love.audio.newSource, path, 'static')
  if not ok or not source then
    print('Sogface sound effect could not be loaded: ' .. path .. ': ' .. tostring(source))
    return nil
  end
  return source
end

local function loadSfxGroup(paths)
  local group = {}
  for _, path in ipairs(paths) do
    group[#group + 1] = loadSfx(path)
  end
  return group
end

Sogface.sfx = {
  inhale = loadSfxGroup({
    'resources/sfx/sogface_inhale.wav',
    'resources/sfx/sogface_inhale_2.wav',
  }),
  spit = loadSfxGroup({
    'resources/sfx/sogface_spit.wav',
    'resources/sfx/sogface_spit_2.wav',
  }),
}

-- Every loaded source, so main.lua can register them with the SFX volume setting.
function Sogface.getSfxSources()
  local sources = {}
  for _, group in pairs(Sogface.sfx) do
    for _, source in ipairs(group) do
      sources[#sources + 1] = source
    end
  end
  return sources
end

-- Plays a random clip from the group at a subtle random pitch (0.95 - 1.05).
-- stop() rewinds the source, so a repeat always starts from the beginning.
local function playRandomSfx(group)
  if #group == 0 then
    return
  end
  local source = group[math.random(1, #group)]
  source:stop()
  source:setPitch(0.95 + math.random() * 0.1)
  source:play()
end

-- Assets ---------------------------------------------------------------------

-- Loads (once) and returns the sprite sheet for a variant:
-- { image, frameW, frameH, quads }. A missing Sewer Champion sheet falls back to the
-- normal sheet, so the variant stays playable. Returns nil if no sheet loads at all.
function Sogface.loadAssets(variant)
  if not Sogface.SHEET_PATHS[variant] then
    variant = Sogface.VARIANT_NORMAL
  end
  Sogface.sheets = Sogface.sheets or {}
  local cached = Sogface.sheets[variant]
  if cached ~= nil then
    return cached or nil
  end
  Sogface.sheets[variant] = false -- remember a failed load so we do not retry every spawn

  local path = Sogface.SHEET_PATHS[variant]
  if not love.filesystem.getInfo(path) then
    print('Sogface sprite sheet missing: ' .. path)
    if variant ~= Sogface.VARIANT_NORMAL then
      Sogface.sheets[variant] = Sogface.loadAssets(Sogface.VARIANT_NORMAL) or false
    end
    return Sogface.sheets[variant] or nil
  end
  local ok, image = pcall(love.graphics.newImage, path)
  if not ok or not image then
    print('Sogface sprite sheet could not be loaded: ' .. tostring(image))
    if variant ~= Sogface.VARIANT_NORMAL then
      Sogface.sheets[variant] = Sogface.loadAssets(Sogface.VARIANT_NORMAL) or false
    end
    return Sogface.sheets[variant] or nil
  end
  image:setFilter('nearest', 'nearest')
  local imageWidth, imageHeight = image:getWidth(), image:getHeight()
  local sheet = {
    path = path,
    image = image,
    frameW = imageWidth / FRAME_COUNT,
    frameH = imageHeight,
    quads = {},
  }
  for index = 1, FRAME_COUNT do
    sheet.quads[index] = love.graphics.newQuad(
      (index - 1) * sheet.frameW, 0, sheet.frameW, sheet.frameH,
      imageWidth, imageHeight
    )
  end
  Sogface.sheets[variant] = sheet
  if variant == Sogface.VARIANT_NORMAL then -- keep the old single-sheet fields
    Sogface.image, Sogface.frameW, Sogface.frameH, Sogface.quads = image, sheet.frameW, sheet.frameH, sheet.quads
  end
  return sheet
end

-- Frame 1 as a standalone image, for the boss HP bar and the boss intro card.
function Sogface.getPortrait(variant)
  if not Sogface.SHEET_PATHS[variant] then
    variant = Sogface.VARIANT_NORMAL
  end
  Sogface.portraits = Sogface.portraits or {}
  if Sogface.portraits[variant] ~= nil then
    return Sogface.portraits[variant] or nil
  end
  Sogface.portraits[variant] = false
  local sheet = Sogface.loadAssets(variant)
  if not sheet then
    return nil
  end
  local ok, portrait = pcall(function()
    local source = love.image.newImageData(sheet.path)
    local frameW, frameH = math.floor(sheet.frameW), math.floor(sheet.frameH)
    local cropped = love.image.newImageData(frameW, frameH)
    cropped:paste(source, 0, 0, 0, 0, frameW, frameH)
    local image = love.graphics.newImage(cropped)
    image:setFilter('nearest', 'nearest')
    return image
  end)
  if ok then
    Sogface.portraits[variant] = portrait
    return portrait
  end
  return nil
end

-- Construction ---------------------------------------------------------------

local function randomIdleTime()
  return IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN)
end

-- `options.variant` ('normal' or 'sewer') forces a variant (debugging, tests);
-- otherwise there is a 25% chance of the Sewer Champion.
function Sogface.new(world, options)
  local variant = options and options.variant
  if not Sogface.SHEET_PATHS[variant] then
    variant = math.random() < SEWER_CHANCE and Sogface.VARIANT_SEWER or Sogface.VARIANT_NORMAL
  end
  local sewer = variant == Sogface.VARIANT_SEWER
  Sogface.loadAssets(variant)
  local health = BASE_HEALTH
  if (world.floorIndex or 1) >= 2 then
    health = FLOOR_TWO_HEALTH
  end
  if sewer then
    health = math.floor(health * SEWER_HEALTH_MULTIPLIER + 0.5)
  end
  local directionX = math.random(0, 1) == 0 and -1 or 1
  local directionY = math.random(0, 1) == 0 and -1 or 1

  return setmetatable({
    kind = 'sogface',
    variant = variant,
    sewerChampion = sewer,
    bonusPickup = sewer, -- main.lua drops one guaranteed heart / coin / key on defeat
    world = world,
    x = world.width / 2,
    y = world.height / 2,
    width = RADIUS * 2,
    height = RADIUS * 2,
    radius = RADIUS,
    health = health,
    maxHealth = health,
    alive = true,
    ignoresObstacles = true, -- it floats over box blocks and furniture
    vx = SPEED_X * directionX,
    vy = SPEED_Y * directionY,
    state = 'idle',
    stateDuration = 0,
    stateTimer = randomIdleTime(),
    animationTime = 0,
    attackCount = 0,
    contactCooldown = 0,
    hitFlashTimer = 0,
    impactX = 0,
    impactY = 0,
    impactVX = 0,
    impactVY = 0,
    bobY = 0,
    sx = 1,
    sy = 1,
    projectiles = {},
    puddles = {},
  }, Sogface)
end

-- Combat interface (same shape as the other bosses) --------------------------

function Sogface:isInvulnerable()
  return not self.alive
end

-- Returns true when this hit kills it.
function Sogface:takeDamage(amount)
  if not self.alive then
    return false
  end
  self.hitFlashTimer = HIT_FLASH_TIME
  self.health = math.max(0, self.health - (amount or 0))
  if self.health <= 0 then
    self.alive = false
    self.projectiles = {}
    return true
  end
  return false
end

-- State machine --------------------------------------------------------------

-- Water / olive-green colours for tears and puddles.
function Sogface:getPalette()
  if self.variant == Sogface.VARIANT_SEWER then
    return SEWER_COLOR, SEWER_DARK, SEWER_SHINE
  end
  return WATER_COLOR, WATER_DARK, WATER_SHINE
end

function Sogface:setState(state, duration)
  self.state = state
  self.stateDuration = duration
  self.stateTimer = duration
  if state == 'windup' then
    playRandomSfx(Sogface.sfx.inhale) -- cheek-puff telegraph (frames 3-4)
  elseif state == 'spit' then
    playRandomSfx(Sogface.sfx.spit) -- the burst (frames 5-6)
    -- Recoil pop: snap narrow and tall, then ease back to normal.
    self.sx, self.sy = 0.8, 1.24
    if self.onScreenShake then
      self.onScreenShake(5, 'sogface_spit')
    end
  end
end

function Sogface:fire(player)
  self.attackCount = self.attackCount + 1
  local mouthY = self.y + self.radius * 0.3
  local angles, speed = {}, RING_SPEED

  if self.attackCount % 2 == 1 then
    -- 8-way ring; every other ring is rotated half a step so gaps move around.
    local offset = (math.floor(self.attackCount / 2) % 2) * (math.pi / RING_COUNT)
    for index = 0, RING_COUNT - 1 do
      angles[#angles + 1] = offset + index * (math.pi * 2 / RING_COUNT)
    end
  else
    -- Aimed fan toward the player.
    local aim = atan2(player.y - mouthY, player.x - self.x)
    local middle = (FAN_COUNT + 1) / 2
    for index = 1, FAN_COUNT do
      angles[#angles + 1] = aim + (index - middle) * FAN_SPREAD
    end
    speed = FAN_SPEED
  end

  for _, angle in ipairs(angles) do
    self.projectiles[#self.projectiles + 1] = {
      x = self.x + math.cos(angle) * self.radius * 0.5,
      y = mouthY + math.sin(angle) * self.radius * 0.3,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      angle = angle,
      radius = PROJECTILE_RADIUS,
      life = PROJECTILE_LIFE,
      age = 0,
    }
  end
end

-- Projectiles and puddles ----------------------------------------------------

function Sogface:addPuddle(x, y)
  local puddles = self.puddles
  puddles[#puddles + 1] = {
    x = x, y = y,
    radius = 14 + math.random() * 8,
    life = PUDDLE_LIFE,
  }
  while #puddles > MAX_PUDDLES do
    table.remove(puddles, 1)
  end
end

local function pointInSolid(x, y, margin, solids)
  for _, rect in ipairs(solids or {}) do
    if x > rect.x - margin and x < rect.x + rect.width + margin
        and y > rect.y - margin and y < rect.y + rect.height + margin then
      return true
    end
  end
  return false
end

function Sogface:updateProjectiles(dt, player, solids)
  for index = #self.puddles, 1, -1 do
    local puddle = self.puddles[index]
    puddle.life = puddle.life - dt
    if puddle.life <= 0 then
      table.remove(self.puddles, index)
    end
  end

  if not player then
    return
  end
  local world = self.world
  local playerRadius = math.max(player.width or 32, player.height or 32) / 2 * 0.75
  local edge = WALL_INSET + 4
  for index = #self.projectiles, 1, -1 do
    local projectile = self.projectiles[index]
    projectile.x = projectile.x + projectile.vx * dt
    projectile.y = projectile.y + projectile.vy * dt
    projectile.life = projectile.life - dt
    projectile.age = projectile.age + dt

    local finished = projectile.life <= 0
    local offsetX, offsetY = player.x - projectile.x, player.y - projectile.y
    local hitRange = playerRadius + projectile.radius
    if offsetX * offsetX + offsetY * offsetY <= hitRange * hitRange then
      player:takeDamage(PROJECTILE_DAMAGE)
      finished = true
    elseif projectile.x < edge or projectile.x > world.width - edge
        or projectile.y < edge or projectile.y > world.height - edge
        or pointInSolid(projectile.x, projectile.y, projectile.radius * 0.5, solids) then
      finished = true
    end

    if finished then
      self:addPuddle(projectile.x, projectile.y)
      table.remove(self.projectiles, index)
    end
  end
end

-- Update ---------------------------------------------------------------------

function Sogface:update(dt, player, solids)
  self.hitFlashTimer = math.max(0, self.hitFlashTimer - dt)
  self:updateProjectiles(dt, player, solids)
  if not self.alive then
    return
  end

  self.animationTime = self.animationTime + dt
  self.contactCooldown = math.max(0, self.contactCooldown - dt)
  self.stateTimer = self.stateTimer - dt

  local moveFactor = 1
  local state = self.state
  if state == 'idle' then
    if self.stateTimer <= 0 then
      self:setState('windup', WINDUP_TIME)
    end
  elseif state == 'windup' then
    moveFactor = SLOW_FACTOR
    if self.stateTimer <= 0 then
      self:setState('pop', POP_TIME)
    end
  elseif state == 'pop' then
    moveFactor = SLOW_FACTOR
    if self.stateTimer <= 0 then
      self:setState('spit', SPIT_TIME)
      self:fire(player)
    end
  elseif state == 'spit' then
    moveFactor = SLOW_FACTOR
    if self.stateTimer <= 0 then
      self:setState('exhausted', EXHAUST_TIME)
    end
  elseif state == 'exhausted' then
    local ramp = 1 - math.max(0, math.min(1, self.stateTimer / EXHAUST_RAMP))
    moveFactor = SLOW_FACTOR + (1 - SLOW_FACTOR) * ramp * ramp
    if self.stateTimer <= 0 then
      self:setState('idle', randomIdleTime())
    end
  end

  -- Diagonal drift; bounce off the room's walls.
  local world = self.world
  local reach = WALL_INSET + self.radius * WALL_REACH
  local minX, maxX = reach, world.width - reach
  local minY, maxY = reach, world.height - reach
  self.x = self.x + self.vx * moveFactor * dt
  self.y = self.y + self.vy * moveFactor * dt

  local hitX, hitY = false, false
  if self.x < minX then
    self.x, self.vx, hitX = minX, math.abs(self.vx), true
  elseif self.x > maxX then
    self.x, self.vx, hitX = maxX, -math.abs(self.vx), true
  end
  if self.y < minY then
    self.y, self.vy, hitY = minY, math.abs(self.vy), true
  elseif self.y > maxY then
    self.y, self.vy, hitY = maxY, -math.abs(self.vy), true
  end
  if hitX then -- squashed against a side wall: narrower, taller
    self.impactX = self.impactX - IMPACT_AMOUNT
    self.impactY = self.impactY + IMPACT_AMOUNT * 0.9
  end
  if hitY then -- squashed against floor / ceiling wall: wider, shorter
    self.impactY = self.impactY - IMPACT_AMOUNT
    self.impactX = self.impactX + IMPACT_AMOUNT * 0.9
  end
  -- Damped spring back to rest (semi-implicit Euler, sub-stepped for stability).
  local steps = math.max(1, math.ceil(dt / (1 / 120)))
  local step = dt / steps
  for _ = 1, steps do
    self.impactVX = self.impactVX
      + (-IMPACT_STIFFNESS * self.impactX - IMPACT_DAMPING * self.impactVX) * step
    self.impactVY = self.impactVY
      + (-IMPACT_STIFFNESS * self.impactY - IMPACT_DAMPING * self.impactVY) * step
    self.impactX = self.impactX + self.impactVX * step
    self.impactY = self.impactY + self.impactVY * step
  end
  self.impactX = math.max(-IMPACT_LIMIT, math.min(IMPACT_LIMIT, self.impactX))
  self.impactY = math.max(-IMPACT_LIMIT, math.min(IMPACT_LIMIT, self.impactY))

  -- Ease the displayed scale toward the pose's target.
  local targetX, targetY = self:getTargetScale()
  local ease = math.min(1, dt * (self.state == 'spit' and 12 or 18))
  self.sx = self.sx + (targetX - self.sx) * ease
  self.sy = self.sy + (targetY - self.sy) * ease
  -- Squished = sitting low, stretched = floating high, so the bob rides the same wave.
  local bobTarget = 0
  if self.state == 'idle' then
    bobTarget = math.sin(self.animationTime * IDLE_FREQ) * IDLE_BOB
  end
  self.bobY = self.bobY + (bobTarget - self.bobY) * ease

  -- Touching the body hurts.
  if player and self.contactCooldown <= 0 then
    local offsetX, offsetY = player.x - self.x, player.y - self.y
    local playerRadius = math.max(player.width or 32, player.height or 32) / 2
    local contact = self.radius * 0.9 + playerRadius * 0.8
    if offsetX * offsetX + offsetY * offsetY <= contact * contact then
      player:takeDamage(CONTACT_DAMAGE)
      self.contactCooldown = CONTACT_COOLDOWN
    end
  end
end

-- Pose ------------------------------------------------------------------------

-- Idle tween: scaleX = 1 + s*0.16, scaleY = 1 - s*0.16 with s = sin(t*5).
-- s >= 0 is squished wide (frame 1), s < 0 is stretched tall (frame 2).
function Sogface:getIdleScale()
  local wave = math.sin(self.animationTime * IDLE_FREQ)
  return 1 + wave * IDLE_AMPLITUDE, 1 - wave * IDLE_AMPLITUDE
end

function Sogface:getTargetScale()
  local state = self.state
  if state == 'idle' then
    return self:getIdleScale()
  elseif state == 'windup' then
    local progress = 1 - math.max(0, self.stateTimer) / self.stateDuration
    return 1 + 0.16 * progress, 1 + 0.12 * progress -- swelling as pressure builds
  elseif state == 'pop' then
    return 1.14, 1.12
  elseif state == 'exhausted' then
    return 1.05, 0.93 -- slumped
  end
  return 1, 1
end

-- 1-based index into the six-frame strip.
function Sogface:getFrameIndex()
  if not self.alive then
    return FRAME_EXHAUSTED
  end
  local state = self.state
  if state == 'windup' then
    return FRAME_WINDUP
  elseif state == 'pop' then
    return FRAME_POP
  elseif state == 'spit' then
    return FRAME_SPIT
  elseif state == 'exhausted' then
    return FRAME_EXHAUSTED
  end
  local scaleX, scaleY = self:getIdleScale()
  if scaleX >= 1 then
    return FRAME_IDLE_WIDE
  elseif scaleY > 1 then
    return FRAME_IDLE_TALL
  end
  return FRAME_IDLE_WIDE
end

-- Drawing ----------------------------------------------------------------------

local function drawWater(projectile, cameraX, cameraY, color, dark, shine)
  local x = math.floor(projectile.x - cameraX)
  local y = math.floor(projectile.y - cameraY)
  local radius = projectile.radius
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(projectile.angle or 0)
  love.graphics.setColor(dark[1], dark[2], dark[3], 1)
  love.graphics.ellipse('fill', 0, 0, radius * 1.3 + 2, radius * 0.9 + 2)
  love.graphics.setColor(color[1], color[2], color[3], 1)
  love.graphics.ellipse('fill', 0, 0, radius * 1.3, radius * 0.9)
  love.graphics.setColor(shine[1], shine[2], shine[3], 0.9)
  love.graphics.ellipse('fill', radius * 0.25, -radius * 0.25, radius * 0.4, radius * 0.22)
  love.graphics.pop()
end

function Sogface:draw(camera)
  local cameraX, cameraY = camera and camera.x or 0, camera and camera.y or 0
  local waterColor, waterDark, waterShine = self:getPalette()

  -- Puddles lie on the floor, under everything.
  for _, puddle in ipairs(self.puddles) do
    local fade = math.min(1, puddle.life / 1.2)
    love.graphics.setColor(waterColor[1], waterColor[2], waterColor[3], 0.42 * fade)
    love.graphics.ellipse('fill',
      math.floor(puddle.x - cameraX), math.floor(puddle.y - cameraY),
      puddle.radius, puddle.radius * 0.5)
    love.graphics.setColor(waterShine[1], waterShine[2], waterShine[3], 0.25 * fade)
    love.graphics.ellipse('line',
      math.floor(puddle.x - cameraX), math.floor(puddle.y - cameraY),
      puddle.radius, puddle.radius * 0.5)
  end

  local sheet = Sogface.loadAssets(self.variant)
  local image = sheet and sheet.image
  local screenX = math.floor(self.x - cameraX)
  local screenY = math.floor(self.y - cameraY)

  local alpha, scaleX, scaleY = 1, self.sx + self.impactX, self.sy + self.impactY
  local dying = self.deathSequence ~= nil
  if dying then
    local sequence = self.deathSequence
    local progress = 1 - math.max(0, sequence.timer) / sequence.duration
    alpha = 1 - progress
    scaleX = scaleX * (1 + progress * 0.3)
    scaleY = scaleY * (1 - progress * 0.4)
  end

  do
    -- Soft shadow so the floating body reads against the floor.
    love.graphics.setColor(0, 0, 0, 0.22 * alpha)
    love.graphics.ellipse('fill', screenX, screenY + math.floor(self.radius * 0.95),
      self.radius * 0.8, 11)

    local bodyY = screenY + math.floor((self.bobY or 0) + 0.5)
    local shakeX = 0
    if self.state == 'windup' and self.alive then
      local progress = 1 - math.max(0, self.stateTimer) / self.stateDuration
      shakeX = math.floor(math.sin(self.animationTime * 50) * 2.5 * progress + 0.5)
    end

    if image then
      local quad = sheet.quads[self:getFrameIndex()]
      local originX, originY = sheet.frameW / 2, sheet.frameH / 2
      local drawX = screenX + shakeX
      love.graphics.setColor(1, 1, 1, alpha)
      love.graphics.draw(image, quad, drawX, bodyY, 0,
        scaleX * DRAW_SCALE, scaleY * DRAW_SCALE, originX, originY)
      if self.hitFlashTimer > 0 then -- white flash on hit
        love.graphics.setBlendMode('add')
        love.graphics.setColor(1, 1, 1, math.min(1, self.hitFlashTimer / HIT_FLASH_TIME) * alpha)
        love.graphics.draw(image, quad, drawX, bodyY, 0,
          scaleX * DRAW_SCALE, scaleY * DRAW_SCALE, originX, originY)
        love.graphics.setBlendMode('alpha')
      end
    else
      -- Sprite sheet missing: a plain blue blob so the fight is still playable.
      love.graphics.setColor(waterDark[1], waterDark[2], waterDark[3], alpha)
      love.graphics.ellipse('fill', screenX + shakeX, bodyY,
        self.radius * scaleX, self.radius * scaleY)
    end
  end

  for _, projectile in ipairs(self.projectiles) do
    drawWater(projectile, cameraX, cameraY, waterColor, waterDark, waterShine)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Sogface