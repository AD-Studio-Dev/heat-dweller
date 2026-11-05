-- Stationary Angel: an elite enemy that exists ONLY on The Sky floor.
-- It never moves. While the room timer climbs it shakes harder and harder,
-- then it locks onto the player's X position, telegraphs a ground lane, and
-- calls down a full-height divine beam. It takes MORE damage the more hurt it
-- is, and visibly shrinks as it loses health.
local StationaryAngel = {}
StationaryAngel.__index = StationaryAngel

StationaryAngel.FLOOR_TYPE = 'sky'
StationaryAngel.MAX_PER_ROOM = 4 -- hard cap, enforced in rooms.lua and main.lua

-- Tuning ---------------------------------------------------------------
local MAX_HEALTH = 300            -- ~75 sweat hits at 4 damage (before bonuses)
local ARMOR = 1                   -- flat reduction per hit, never below MIN_DAMAGE
local MIN_DAMAGE = 1
local MISSING_HEALTH_BONUS = 1.5  -- +150% damage taken at 0% health
local HIT_STACK_STEP = 0.05       -- +5% damage taken per recent hit
local HIT_STACK_CAP = 0.5         -- ...up to +50%
local HIT_STACK_WINDOW = 2        -- seconds without a hit before the stack resets

local MIN_SIZE_FACTOR = 0.4       -- visual scale at 0% health (1 at full health)
local BASE_HITBOX = 96            -- hurtbox size at full health (px)
local MIN_HITBOX = 56             -- the hurtbox never shrinks below this

local ATTACK_THRESHOLD = 5        -- seconds of charge-up before each burst
local BEAMS_PER_BURST = 3
local TELEGRAPH_DURATION = 0.6    -- warning before the first beam of a burst
local FOLLOWUP_TELEGRAPH = 0.45   -- warning before beams 2 and 3 (re-locks onto the player)
local BEAM_DURATION = 0.4
local BEAM_WIDTH = 96
local BEAM_DAMAGE = 20            -- 1 heart
local IDLE_SHAKE_MAX = 6          -- px of sprite shake just before the lock-on
local ATTACK_SHAKE = 8

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(value, maximum))
end

function StationaryAngel.isAllowedOn(floorType)
  return floorType == StationaryAngel.FLOOR_TYPE
end

function StationaryAngel.new(config)
  config = config or {}
  local maxHealth = config.health or MAX_HEALTH

  local angel = setmetatable({
    kind = 'stationaryangel',
    x = config.x or 640,
    y = config.y or 360,
    width = BASE_HITBOX,
    height = BASE_HITBOX,
    radius = BASE_HITBOX / 2,
    speed = 0,
    maxHealth = maxHealth,
    health = maxHealth,
    lastHealth = maxHealth,
    armor = config.armor or ARMOR,
    alive = true,
    animationTime = 0,
    sizeFactor = 1,
    hitStack = 0,
    hitStackTimer = 0,
    hitFlashTimer = 0,

    -- Starts negative when `startDelay` is set, so several angels in one room
    -- don't all fire on the same frame.
    roomTimer = -(config.startDelay or 0),
    beamIndex = 0, -- which beam of the current burst is telegraphing/firing (1-3)
    attackThreshold = config.attackThreshold or ATTACK_THRESHOLD,
    attackState = 'idle', -- idle -> telegraph -> firing -> idle
    attackTimer = 0,
    beamX = 0,
    beamWidth = BEAM_WIDTH,
    beamBottom = 960,
    telegraphDuration = TELEGRAPH_DURATION,
    beamDuration = BEAM_DURATION,
    shakeIntensity = 0,
  }, StationaryAngel)

  angel:refreshSize()
  return angel
end

-- Sprite scale and hurtbox follow the health ratio. The hurtbox shrinks more
-- slowly than the sprite and has a floor, so it stays satisfying to hit.
function StationaryAngel:refreshSize()
  local ratio = clamp(self.health / self.maxHealth, 0, 1)
  self.sizeFactor = MIN_SIZE_FACTOR + (1 - MIN_SIZE_FACTOR) * ratio
  local hitSize = math.max(MIN_HITBOX, BASE_HITBOX * self.sizeFactor)
  self.width = hitSize
  self.height = hitSize
  self.radius = hitSize / 2
end

-- Damage multiplier grows as health drops and as hits chain together.
function StationaryAngel:getDamageMultiplier()
  local missing = 1 - clamp(self.health / self.maxHealth, 0, 1)
  local stack = math.min(HIT_STACK_CAP, self.hitStack * HIT_STACK_STEP)
  return 1 + missing * MISSING_HEALTH_BONUS + stack
end

function StationaryAngel:die()
  self.health = 0
  self.lastHealth = 0
  self.alive = false
  -- Dying cancels any telegraph or beam in progress.
  self.attackState = 'idle'
  self.attackTimer = 0
  self.beamIndex = 0
  self.shakeIntensity = 0
  self:refreshSize()
end

-- Continuous damage (Fire Extinguisher foam, applied every frame). Gets the
-- inverse-scaling multiplier but not armor or hit stacking, which are per-hit.
function StationaryAngel:takeContinuousDamage(amount)
  if not self.alive then
    return false
  end
  self.hitFlashTimer = 0.08
  self.health = math.max(0, self.health - (tonumber(amount) or 0) * self:getDamageMultiplier())
  self.lastHealth = self.health
  if self.health <= 0 then
    self:die()
    return true
  end
  self:refreshSize()
  return false
end

-- Returns true when this hit defeats the angel (same contract as the bosses).
function StationaryAngel:takeDamage(amount)
  if not self.alive then
    return false
  end

  local reduced = math.max(MIN_DAMAGE, (tonumber(amount) or 0) - self.armor)
  local dealt = reduced * self:getDamageMultiplier()

  self.hitStack = self.hitStack + 1
  self.hitStackTimer = HIT_STACK_WINDOW
  self.hitFlashTimer = 0.08
  self.health = math.max(0, self.health - dealt)
  self.lastHealth = self.health

  if self.health <= 0 then
    self:die()
    return true
  end
  self:refreshSize()
  return false
end

-- Safety net: if some other system lowers `health` directly (instead of calling
-- takeDamage), undo that raw loss and run it through takeDamage so armor and the
-- inverse scaling still apply.
function StationaryAngel:absorbExternalDamage()
  if self.health < self.lastHealth - 1e-6 then
    local raw = self.lastHealth - self.health
    self.health = self.lastHealth
    self:takeDamage(raw)
  else
    self.lastHealth = self.health
  end
end

function StationaryAngel:isBeamActive()
  return self.alive and self.attackState == 'firing'
end

function StationaryAngel:isTelegraphing()
  return self.alive and self.attackState == 'telegraph'
end

-- 0 at the start of the warning, 1 when the beam fires.
function StationaryAngel:getTelegraphProgress()
  return clamp(1 - self.attackTimer / self.telegraphDuration, 0, 1)
end

function StationaryAngel:getBeamProgress()
  return clamp(1 - self.attackTimer / self.beamDuration, 0, 1)
end

function StationaryAngel:update(dt, player, world)
  if not self.alive then
    return
  end

  self:absorbExternalDamage()
  if not self.alive then
    return
  end

  self.animationTime = self.animationTime + dt
  self.hitFlashTimer = math.max(0, self.hitFlashTimer - dt)
  if self.hitStackTimer > 0 then
    self.hitStackTimer = self.hitStackTimer - dt
    if self.hitStackTimer <= 0 then
      self.hitStack = 0
    end
  end
  if world and world.height then
    self.beamBottom = world.height
  end

  if self.attackState == 'idle' then
    self.roomTimer = self.roomTimer + dt
    local ramp = clamp(self.roomTimer / self.attackThreshold, 0, 1)
    self.shakeIntensity = IDLE_SHAKE_MAX * ramp * ramp
    if self.roomTimer >= self.attackThreshold then
      self.beamIndex = 1
      self:beginTelegraph(player, world, TELEGRAPH_DURATION)
    end
  elseif self.attackState == 'telegraph' then
    self.shakeIntensity = ATTACK_SHAKE
    self.attackTimer = self.attackTimer - dt
    if self.attackTimer <= 0 then
      self.attackState = 'firing'
      self.attackTimer = self.beamDuration
    end
  elseif self.attackState == 'firing' then
    self.shakeIntensity = ATTACK_SHAKE
    self.attackTimer = self.attackTimer - dt
    -- Full-height vertical column: hits no matter how far up or down the player is.
    local halfWidth = self.beamWidth / 2 + (player.width or 64) * 0.25
    if math.abs(player.x - self.beamX) <= halfWidth then
      player:takeDamage(BEAM_DAMAGE, 'beam')
    end
    if self.attackTimer <= 0 then
      if self.beamIndex < BEAMS_PER_BURST then
        -- Next beam of the burst: re-lock onto wherever Matthew is now.
        self.beamIndex = self.beamIndex + 1
        self:beginTelegraph(player, world, FOLLOWUP_TELEGRAPH)
      else
        self.attackState = 'idle'
        self.attackTimer = 0
        self.beamIndex = 0
        self.roomTimer = 0
        self.shakeIntensity = 0
      end
    end
  end
end

-- Locks the beam column onto the player's current X and starts the warning.
function StationaryAngel:beginTelegraph(player, world, duration)
  local worldWidth = world and world.width or 1280
  self.beamX = clamp(player.x, self.beamWidth / 2, worldWidth - self.beamWidth / 2)
  self.telegraphDuration = duration
  self.attackState = 'telegraph'
  self.attackTimer = duration
end

return StationaryAngel