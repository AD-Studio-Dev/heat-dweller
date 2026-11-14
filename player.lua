-- Player movement and animation state.
local Player = {}
Player.__index = Player

-- Item-driven transformations. An evolution is active while the player owns the
-- item (matched by items.xml id or name). Costume and projectile art live in
-- renderer.lua, keyed by the same evolution name.
Player.EVOLUTIONS = {
  burnt_chilli = {
    itemId = 1,
    itemName = 'Burnt Chilli',
    damageBonus = 1,       -- flat, added before the multiplier
    damageMultiplier = 1.5, -- applied to the total
  },
}

function Player.new(config)
  config = config or {}

  local player = {
    x = config.startX or 800,
    y = config.startY or 600,
    width = config.width or 64,
    height = config.height or 64,
    speed = config.speed or 240,
    baseSpeed = config.speed or 240,
    acceleration = config.acceleration or 13, -- Controls slippery drift (lower = more slide)
    frameSpeed = config.frameSpeed or 0.08,
    blinkDuration = config.blinkDuration or 0.12,
    blinkInterval = config.blinkInterval or 2.5,
    pickupItem = nil,       -- item definition held overhead during a pickup
    pickupTime = 0,
    pickupBounceDuration = config.pickupBounceDuration or 0.15, -- pickup_1, then hold pickup_2

    facing = 'down',
    walkFacing = 'down',
    moving = false,
    velocityX = 0,
    velocityY = 0,
    animationTime = 0,
    blinkTime = 0,
    nextBlink = config.blinkInterval or 2.5,
    blinking = false,
    damageInvulnerabilityTimer = 0,
    damageInvulnerabilityDuration = config.damageInvulnerabilityDuration or 1,
    isHurt = false,
    hurtDuration = config.hurtDuration or 0.4,
    hurtFrameDuration = config.hurtFrameDuration or 0.1,
    hurtAnimationTime = 0,
    sweatShotCooldown = 0,
    sweatShotDelay = config.sweatShotDelay or 0.35,
    onShootSweat = config.onShootSweat, 

    -- Stats modified by passive collectibles.
    stats = {
      damage = 3,
      maxHealth = 100,
      health = 100,
      dollars = 20,
      luck = 0,
      keys = 0,
      fireRate = 0,
      size = 1,
    },
    activeEffects = {},
    evolutions = {},
    currentFloorType = config.currentFloorType or 'basement',
    onDamaged = config.onDamaged,
  }

  return setmetatable(player, Player)
end

function Player:applyItem(item)
  local effects = item.effects or {}

  for stat, amount in pairs(effects) do
    if stat == 'health' then
      if amount < 0 then
        self:reduceMaxHealth(-amount)
      else
        self.stats.maxHealth = self.stats.maxHealth + amount
        self.stats.health = math.min(self.stats.health + amount, self.stats.maxHealth)
      end
    elseif stat == 'speed' then
      self.speed = self.speed + amount
    elseif self.stats[stat] then
      self.stats[stat] = self.stats[stat] + amount
    end
  end

  if item.effect or item.activeEffect then
    table.insert(self.activeEffects, {
      name = item.name,
      description = item.effect or item.activeEffect,
      cooldown = item.cooldown or item.timedCooldown,
    })
  end
end

local function ownsEvolutionItem(inventory, evolution)
  for _, item in ipairs(inventory or {}) do
    local name = type(item.name) == 'string' and item.name:lower() or nil
    if tonumber(item.id) == evolution.itemId or name == evolution.itemName:lower() then
      return true
    end
  end
  return false
end

-- Call every frame with items:getInventoryItems(); the inventory is the single
-- source of truth, so picking an item up by any route (room, shop, deal)
-- transforms Matthew and a new run (new Player) resets it.
function Player:syncEvolutions(inventory)
  for name, evolution in pairs(Player.EVOLUTIONS) do
    self.evolutions[name] = ownsEvolutionItem(inventory, evolution)
  end
end

function Player:hasEvolution(name)
  return self.evolutions[name] == true
end

-- Final per-hit damage: (base + flat bonuses) * multipliers.
function Player:getDamage()
  local damage = self.stats.damage
  for name, evolution in pairs(Player.EVOLUTIONS) do
    if self.evolutions[name] then
      damage = damage + (evolution.damageBonus or 0)
    end
  end
  for name, evolution in pairs(Player.EVOLUTIONS) do
    if self.evolutions[name] then
      damage = damage * (evolution.damageMultiplier or 1)
    end
  end
  return damage
end

function Player:takeDamage(amount, damageClass, floorType)
  if self.damageInvulnerabilityTimer > 0 or self.stats.health <= 0 then
    return false
  end
  local platform = self.temporaryPlatform
  if platform and platform.timer > 0 then
    local offsetX, offsetY = self.x - platform.x, self.y - platform.y
    if offsetX * offsetX + offsetY * offsetY <= platform.radius * platform.radius then
      return false
    end
  end

  local targetFloorType = floorType or self.currentFloorType or 'basement'
  local hearts = damageClass == 'boss' and 1 or 0.5
  if amount ~= nil then
    local numericAmount = tonumber(amount)
    if numericAmount ~= nil then
      if numericAmount <= 1 then
        hearts = numericAmount
      else
        hearts = numericAmount / 20
      end
    end
  end

  if targetFloorType == 'roof' or targetFloorType == 'sky' then
    hearts = math.max(hearts, 1)
  elseif damageClass ~= 'boss' then
    hearts = math.max(hearts, 0.5)
  end

  local healthUnitsPerHeart = 20
  local invulnerabilityDuration = hearts >= 1 and 2 or 1
  if self.onDamaged then
    self.onDamaged(hearts * healthUnitsPerHeart)
  end
  self.stats.health = math.max(0, self.stats.health - hearts * healthUnitsPerHeart)
  self.damageInvulnerabilityDuration = invulnerabilityDuration
  self.damageInvulnerabilityTimer = invulnerabilityDuration
  self.isHurt = true
  self.hurtAnimationTime = 0
  return true
end

function Player:reduceMaxHealth(amount)
  self.stats.maxHealth = math.max(0, self.stats.maxHealth - amount)
  self.stats.health = math.min(self.stats.health, self.stats.maxHealth)
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(value, maximum))
end

local function blocksFloorHole(startX, startY, endX, endY, playerRadius, holes)
  for _, hole in ipairs(holes or {}) do
    local radius = hole.radius + playerRadius
    local moveX, moveY = endX - startX, endY - startY
    local moveLengthSquared = moveX * moveX + moveY * moveY
    local progress = 0
    if moveLengthSquared > 0 then
      progress = clamp(
        ((hole.x - startX) * moveX + (hole.y - startY) * moveY) / moveLengthSquared,
        0,
        1
      )
    end
    local closestX, closestY = startX + moveX * progress, startY + moveY * progress
    local closestOffsetX, closestOffsetY = closestX - hole.x, closestY - hole.y
    local startOffsetX, startOffsetY = startX - hole.x, startY - hole.y
    local endOffsetX, endOffsetY = endX - hole.x, endY - hole.y
    local closestDistanceSquared = closestOffsetX * closestOffsetX
      + closestOffsetY * closestOffsetY
    local startDistanceSquared = startOffsetX * startOffsetX + startOffsetY * startOffsetY
    local endDistanceSquared = endOffsetX * endOffsetX + endOffsetY * endOffsetY
    if closestDistanceSquared < radius * radius
        and (startDistanceSquared >= radius * radius or endDistanceSquared < startDistanceSquared) then
      return true
    end
  end
  return false
end

local function overlapsObstacle(x, y, playerRadius, obstacles)
  for _, obstacle in ipairs(obstacles or {}) do
    local closestX = clamp(x, obstacle.x, obstacle.x + obstacle.width)
    local closestY = clamp(y, obstacle.y, obstacle.y + obstacle.height)
    local offsetX, offsetY = x - closestX, y - closestY
    if offsetX * offsetX + offsetY * offsetY < playerRadius * playerRadius then
      return true
    end
  end
  return false
end

function Player:update(dt, input, world)
  local wasMoving = self.moving
  local previousWalkFacing = self.walkFacing
  self.damageInvulnerabilityTimer = math.max(0, self.damageInvulnerabilityTimer - dt)
  if self.isHurt then
    self.hurtAnimationTime = self.hurtAnimationTime + dt
    if self.hurtAnimationTime >= self.hurtDuration then
      self.isHurt = false
      self.hurtAnimationTime = 0
    end
  end
  if self.temporaryPlatform then
    self.temporaryPlatform.timer = self.temporaryPlatform.timer - dt
    if self.temporaryPlatform.timer <= 0 then
      self.temporaryPlatform = nil
    end
  end
  local directionX = 0
  local directionY = 0

  if input.left then directionX = directionX - 1 end
  if input.right then directionX = directionX + 1 end
  if input.up then directionY = directionY - 1 end
  if input.down then directionY = directionY + 1 end

  local directionLength = math.sqrt(directionX * directionX + directionY * directionY)
  self.moving = directionLength > 0

  -- Calculate target velocity based on input
  local targetVx = 0
  local targetVy = 0
  if directionLength > 0 then
    directionX = directionX / directionLength
    directionY = directionY / directionLength
    targetVx = directionX * self.speed
    targetVy = directionY * self.speed
  end

  -- Smoothly slide (interpolate) velocity toward target velocity for the drift effect
  local accel = self.acceleration or 12
  self.velocityX = self.velocityX + (targetVx - self.velocityX) * math.min(1, accel * dt)
  self.velocityY = self.velocityY + (targetVy - self.velocityY) * math.min(1, accel * dt)

  local nextX = self.x + self.velocityX * dt
  local nextY = self.y + self.velocityY * dt
  local holePlayerRadius = math.min(self.width, self.height) / 2
  if blocksFloorHole(
      self.x, self.y, nextX, self.y, holePlayerRadius, world.floorHoles
    ) then
    nextX = self.x
  end
  if blocksFloorHole(
      nextX, self.y, nextX, nextY, holePlayerRadius, world.floorHoles
    ) then
    nextY = self.y
  end
  if overlapsObstacle(nextX, self.y, holePlayerRadius, world.solidObstacles) then
    nextX = self.x
  end
  if overlapsObstacle(nextX, nextY, holePlayerRadius, world.solidObstacles) then
    nextY = self.y
  end
  self.x = nextX
  self.y = nextY

  if self.moving then
    local movementFacing
    if directionX < 0 then
      movementFacing = 'left'
    elseif directionX > 0 then
      movementFacing = 'right'
    elseif directionY < 0 then
      movementFacing = 'up'
    else
      movementFacing = 'down'
    end
    self.facing = movementFacing
    self.walkFacing = movementFacing

    if not wasMoving or self.walkFacing ~= previousWalkFacing then
      self.animationTime = 0
    end
    self.animationTime = self.animationTime + dt
  elseif wasMoving then
    self.animationTime = 0
  end

  local halfWidth = self.width / 2
  local halfHeight = self.height / 2
  -- Stop at the inner face of the walls (world.wall px thick), not the room edge.
  local wall = world.wall or 0
  self.x = clamp(self.x, halfWidth + wall, world.width - halfWidth - wall)
  self.y = clamp(self.y, halfHeight + wall, world.height - halfHeight - wall)

  if world.camera then
    local camera = world.camera
    camera.x = clamp(self.x - camera.width / 2, 0, math.max(0, world.width - camera.width))
    camera.y = clamp(self.y - camera.height / 2, 0, math.max(0, world.height - camera.height))
  end

  self:updateBlink(dt)

  self.sweatShotCooldown = math.max(0, self.sweatShotCooldown - dt)
end

-- Seconds between shots after fire-rate items. Single source of truth for both
-- the shooting cooldown and the HUD attack-speed readout.
function Player:getShotCooldown()
  local rateMultiplier = math.max(0.25, 1 + self.stats.fireRate)
  return math.max(0.12, self.sweatShotDelay / rateMultiplier)
end

-- Shots per second (about 2.9 with no fire-rate items).
function Player:getAttackSpeed()
  return 1 / self:getShotCooldown()
end

function Player:shootSweat(directionX, directionY)
  if type(directionX) == 'string' then
    local directions = {
      up = { 0, -1 },
      down = { 0, 1 },
      left = { -1, 0 },
      right = { 1, 0 },
    }
    local direction = directions[directionX]
    if not direction then
      return false
    end
    directionX, directionY = direction[1], direction[2]
  end
  if type(directionX) ~= 'number' or type(directionY) ~= 'number'
      or directionX == 0 and directionY == 0 then
    return false
  end

  local directionLength = math.sqrt(directionX * directionX + directionY * directionY)
  directionX = directionX / directionLength
  directionY = directionY / directionLength
  if math.abs(directionX) > math.abs(directionY) then
    self.facing = directionX < 0 and 'left' or 'right'
  else
    self.facing = directionY < 0 and 'up' or 'down'
  end

  if self.sweatShotCooldown > 0 or self.stats.health <= 0 or not self.onShootSweat then
    return false
  end

  self.sweatShotCooldown = self:getShotCooldown()
  self.onShootSweat(directionX, directionY)
  return true
end

function Player:updateBlink(dt)
  if self.blinking then
    self.blinkTime = self.blinkTime + dt
    if self.blinkTime >= self.blinkDuration then
      self.blinking = false
      self.blinkTime = 0
      self.nextBlink = self.blinkInterval * (0.7 + math.random() * 0.6)
    end
  else
    self.nextBlink = self.nextBlink - dt
    if self.nextBlink <= 0 then
      self.blinking = true
      self.blinkTime = 0
    end
  end
end

-- Item pickup pose: pickup_1 (bounce) then pickup_2 (arms raised) while the
-- collected item floats over the head. main.lua starts/ends it with the pickup.
function Player:startPickup(item)
  self.pickupItem = item
  self.pickupTime = 0
end

function Player:updatePickup(dt)
  if self.pickupItem then
    self.pickupTime = self.pickupTime + dt
  end
end

function Player:endPickup()
  self.pickupItem = nil
  self.pickupTime = 0
end

function Player:isPickingUp()
  return self.pickupItem ~= nil
end

function Player:isDead()
  return self.stats.health <= 0
end

local WALK_FORWARD_FRAMES = 8 -- walk_forward_0..7
local WALK_RIGHT_FRAMES = 7   -- walk_right_0..6

function Player:getBodyFrame()
  if self.pickupItem then
    return self.pickupTime < self.pickupBounceDuration and 'pickup_1' or 'pickup_2'
  end

  local walkFacing = self.walkFacing or self.facing
  local sideways = walkFacing == 'left' or walkFacing == 'right'
  local prefix = sideways and 'walk_right_' or 'walk_forward_'

  -- Hurt and dead bodies stand still; only the head changes (hurt_head / death_head).
  if not self.moving or self.isHurt or self:isDead() then
    return prefix .. '0'
  end

  local count = sideways and WALK_RIGHT_FRAMES or WALK_FORWARD_FRAMES
  local cycleDuration = self.frameSpeed * count
  local cycleTime = self.animationTime % cycleDuration
  local frameIndex = math.min(count - 1, math.floor(cycleTime / self.frameSpeed))
  return prefix .. frameIndex
end

function Player:getHeadFrame()
  if self.pickupItem then
    return 'pickup_head'
  end
  if self:isDead() then
    return 'death_head'
  end
  if self.isHurt then
    return 'hurt_head'
  end

  local frame = 'head_forward'
  if self.facing == 'up' then
    frame = 'head_back'
  elseif self.facing == 'left' or self.facing == 'right' then
    frame = 'head_right' -- the renderer mirrors it for 'left'
  end

  -- Periodic blink only; shooting never triggers it.
  if self.blinking then
    frame = frame .. '_blink'
  end

  return frame
end

return Player