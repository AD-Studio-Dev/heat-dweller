local TheGeometric = {}
TheGeometric.__index = TheGeometric

local bodyBaseHealth = 480
local headHealth = 48
local recoveryDuration = 3
local finalHeadHealth = 150

-- Final-phase collision tuning.
local FINAL_WALL_RADIUS_FACTOR = 0.42 -- props use a smaller hitbox than the 256 px head
local STUCK_CHECK_INTERVAL = 0.5      -- seconds between "did I move?" checks
local STUCK_MIN_TRAVEL = 24           -- px the boss must cover per check
local GHOST_DURATION = 0.6            -- seconds it may pass through props to escape

-- Circle vs rectangle. Returns push normal (nx, ny) and penetration depth, or nil.
local function circleRectPush(x, y, radius, rect)
  local closestX = math.max(rect.x, math.min(x, rect.x + rect.width))
  local closestY = math.max(rect.y, math.min(y, rect.y + rect.height))
  local dx, dy = x - closestX, y - closestY
  local distanceSquared = dx * dx + dy * dy
  if distanceSquared >= radius * radius then
    return nil
  end
  if distanceSquared > 0 then
    local distance = math.sqrt(distanceSquared)
    return dx / distance, dy / distance, radius - distance
  end
  -- Centre is inside the rectangle: leave through the nearest side.
  local left = x - rect.x
  local right = rect.x + rect.width - x
  local top = y - rect.y
  local bottom = rect.y + rect.height - y
  local nearest = math.min(left, right, top, bottom)
  if nearest == left then return -1, 0, left + radius end
  if nearest == right then return 1, 0, right + radius end
  if nearest == top then return 0, -1, top + radius end
  return 0, 1, bottom + radius
end

local function overlapsAnySolid(x, y, radius, solids)
  for _, solid in ipairs(solids or {}) do
    if circleRectPush(x, y, radius, solid) then
      return true
    end
  end
  return false
end

local function configureHead(boss, head)
  head.kind = 'geometric_head'
  head.width = 128
  head.height = 128
  head.health = head.health or headHealth
  head.maxHealth = head.maxHealth or headHealth
  head.alive = head.alive ~= false
  head.geometricPart = true
  head.hitFlashTimer = head.hitFlashTimer or 0
  head.isInvulnerable = function(self)
    return not self.alive
  end
  head.takeDamage = function(self, amount)
    return boss:damageHead(self, amount)
  end
end

function TheGeometric.new(world)
  local boss = setmetatable({
    kind = 'geometric',
    projectilePassThroughWhenInvulnerable = true,
    x = world.width / 2,
    y = world.height / 2,
    width = 224,
    height = 224,
    radius = 112,
    health = bodyBaseHealth,
    maxHealth = bodyBaseHealth,
    bodyHealth = bodyBaseHealth,
    speed = 48,
    alive = true,
    bodyAlive = true,
    world = world,
    animationTime = 0,
    facing = 'forward',
    moving = false,
    contactCooldown = 0,
    phase = 'body',
    heads = {},
    headOrbitAngle = 0,
    headShatters = {},
    bodyInvulnerabilityTimer = 0,
    finalShakeTimer = 0,
    finalVx = 280,
    finalVy = -235,
    -- Final-phase unstick state.
    finalPlaced = false,
    ghostTimer = 0,
    unstickCount = 0,
    overlapFrames = 0,
    stuckTimer = 0,
  }, TheGeometric)
  boss:spawnHeads(1, true)
  return boss
end

function TheGeometric:spawnHeads(count, shieldBody)
  self.heads = {}
  self.shieldActive = shieldBody
  for index = 1, count do
    local head = {
      orbitOffset = (index - 1) * math.pi * 2 / count,
      health = headHealth,
      maxHealth = headHealth,
      alive = true,
    }
    configureHead(self, head)
    self.heads[#self.heads + 1] = head
  end
  self:updateHeadPositions()
end

function TheGeometric:updateHeadPositions()
  local count = #self.heads
  local orbitRadius = count == 1 and 176 or count == 2 and 190 or 208
  for _, head in ipairs(self.heads) do
    local angle = self.headOrbitAngle + head.orbitOffset
    head.x = self.x + math.cos(angle) * orbitRadius
    head.y = self.y + math.sin(angle) * orbitRadius
    head.facing = math.cos(angle) < 0 and 'left' or 'right'
  end
end

function TheGeometric:restoreRuntimeState()
  for _, head in ipairs(self.heads or {}) do
    configureHead(self, head)
  end
  self.heads = self.heads or {}
  self.headShatters = self.headShatters or {}
  self.finalShakeTimer = self.finalShakeTimer or 0
  self.bodyHealth = math.max(0, math.min(
    bodyBaseHealth,
    self.bodyHealth or self.health or bodyBaseHealth
  ))
  if self.phase == 'final' then
    self.maxHealth = self.finalHeadHealth or finalHeadHealth
    self.width = 256
    self.height = 256
    self.radius = 128
    -- Re-check placement after loading a save, and reset the failsafe state.
    self.finalPlaced = false
    self.ghostTimer = 0
    self.unstickCount = 0
    self.overlapFrames = 0
    self.stuckTimer = 0
    self.stuckAnchorX, self.stuckAnchorY = nil, nil
  else
    self.maxHealth = bodyBaseHealth
    self.width = 224
    self.height = 224
    self.radius = 112
    self.health = self.bodyHealth
  end
  local hasLivingHead = false
  for _, head in ipairs(self.heads) do
    if head.alive then
      hasLivingHead = true
      break
    end
  end
  self.shieldActive = hasLivingHead
    and (self.phase == 'body' or self.phase == 'split_two' or self.phase == 'split_four')
  self:updateHeadPositions()
end

function TheGeometric:damageHead(head, amount)
  if not self.alive or not head.alive or self.phase == 'body_recovery'
      or self.phase == 'body_final' or self.phase == 'final' then
    return false
  end

  head.hitFlashTimer = 0.14
  head.health = math.max(0, head.health - amount)
  if head.health <= 0 then
    head.alive = false
    self.headShatters[#self.headShatters + 1] = {
      x = head.x,
      y = head.y,
      timer = 0.45,
    }
    if self.onScreenShake then
      self.onScreenShake(6, 'head_destroyed')
    end
    local remainingHeads = false
    for _, candidate in ipairs(self.heads) do
      if candidate.alive then
        remainingHeads = true
        break
      end
    end
    if not remainingHeads and self.shieldActive then
      self.shieldActive = false
      if self.phase == 'split_two' then
        self.phase = 'body_after_two'
      elseif self.phase == 'split_four' then
        self.phase = 'body_after_four'
      end
    end
    return true
  end
  return false
end

function TheGeometric:isInvulnerable()
  return not self.alive or (self.phase ~= 'final' and not self.bodyAlive) or self.shieldActive
    or self.phase == 'body_recovery'
end

function TheGeometric:beginFinalPhase()
  self.phase = 'final'
  self.bodyAlive = false
  self.shieldActive = false
  self.heads = {}
  self.width = 256
  self.height = 256
  self.radius = 128
  self.health = finalHeadHealth
  self.finalHeadHealth = finalHeadHealth
  self.maxHealth = finalHeadHealth
  self.finalVx = self.finalVx < 0 and -330 or 330
  self.finalVy = self.finalVy < 0 and -295 or 295
  -- Fresh failsafe state; the first final frame relocates us out of any prop.
  self.finalPlaced = false
  self.ghostTimer = 0
  self.unstickCount = 0
  self.overlapFrames = 0
  self.stuckTimer = 0
  self.stuckAnchorX, self.stuckAnchorY = nil, nil
end

function TheGeometric:takeDamage(amount)
  if not self.alive or self:isInvulnerable() then
    return false
  end

  if self.phase == 'final' then
    self.health = math.max(0, self.health - amount)
    if self.health <= 0 then
      self.alive = false
      return true
    end
    return false
  end

  self.bodyHealth = math.max(0, self.bodyHealth - amount)
  if self.phase == 'body' and self.bodyHealth <= self.maxHealth * 0.5 then
    self.bodyHealth = self.maxHealth * 0.5
    self.phase = 'split_two'
    self:spawnHeads(2, true)
    if self.onScreenShake then
      self.onScreenShake(10, 'split_two')
    end
  elseif self.phase == 'body_after_two' and self.bodyHealth <= self.maxHealth * 0.25 then
    self.bodyHealth = self.maxHealth * 0.25
    self.phase = 'split_four'
    self:spawnHeads(4, true)
    if self.onScreenShake then
      self.onScreenShake(13, 'split_four')
    end
  elseif self.phase == 'body_after_four' and self.bodyHealth <= self.maxHealth * 0.125 then
    self.bodyHealth = self.maxHealth * 0.125
    self.phase = 'body_recovery'
    self.bodyInvulnerabilityTimer = recoveryDuration
    self.heads = {}
  elseif self.phase == 'body_final' and self.bodyHealth <= 0 then
    self:beginFinalPhase()
  end

  if self.phase ~= 'final' then
    self.health = self.bodyHealth
  end
  return false
end

function TheGeometric:getTargets()
  local targets = {}
  if self.alive and (self.phase == 'final' or self.bodyAlive) then
    targets[#targets + 1] = self
  end
  if self.phase ~= 'body_recovery' and self.phase ~= 'body_final' and self.phase ~= 'final' then
    for _, head in ipairs(self.heads) do
      if head.alive then
        targets[#targets + 1] = head
      end
    end
  end
  return targets
end

function TheGeometric:getWallRadius()
  return self.radius * FINAL_WALL_RADIUS_FACTOR
end

-- Push out of every solid and bounce off its surface. Returns true if anything was hit.
function TheGeometric:resolveSolids(solids)
  local radius = self:getWallRadius()
  local hit = false
  for _ = 1, 3 do -- extra passes settle corners where two props meet
    local pushedThisPass = false
    for _, solid in ipairs(solids) do
      local nx, ny, depth = circleRectPush(self.x, self.y, radius, solid)
      if nx then
        self.x = self.x + nx * (depth + 0.01)
        self.y = self.y + ny * (depth + 0.01)
        local into = self.finalVx * nx + self.finalVy * ny
        if into < 0 then -- only reflect when moving into the surface
          self.finalVx = self.finalVx - 2 * into * nx
          self.finalVy = self.finalVy - 2 * into * ny
        end
        hit, pushedThisPass = true, true
      end
    end
    if not pushedThisPass then
      break
    end
  end
  return hit
end

-- Nearest spot where the head's wall hitbox touches no prop (and is inside the room).
function TheGeometric:findFreeSpot(solids)
  local radius = self:getWallRadius() + 6
  local minX, maxX = self.radius, self.world.width - self.radius
  local minY, maxY = self.radius, self.world.height - self.radius
  local bestX, bestY, bestDistance

  local function consider(x, y)
    x = math.max(minX, math.min(maxX, x))
    y = math.max(minY, math.min(maxY, y))
    if not overlapsAnySolid(x, y, radius, solids) then
      local dx, dy = x - self.x, y - self.y
      local distance = dx * dx + dy * dy
      if not bestDistance or distance < bestDistance then
        bestX, bestY, bestDistance = x, y, distance
      end
    end
  end

  consider(self.world.width / 2, self.world.height / 2)
  for ring = 1, 10 do
    for step = 0, 15 do
      local angle = step * math.pi / 8
      consider(self.x + math.cos(angle) * ring * 48, self.y + math.sin(angle) * ring * 48)
    end
  end
  return bestX, bestY
end

-- Failsafe: first try to slip out (ghost through props toward open floor);
-- if that doesn't work, snap to the nearest free spot.
function TheGeometric:unstick(solids)
  self.unstickCount = (self.unstickCount or 0) + 1
  self.overlapFrames = 0
  local freeX, freeY = self:findFreeSpot(solids)

  if self.unstickCount >= 2 and freeX then
    self.x, self.y = freeX, freeY
    self.unstickCount = 0
    self.ghostTimer = 0.2
    return
  end

  self.ghostTimer = GHOST_DURATION
  local targetX = freeX or self.world.width / 2
  local targetY = freeY or self.world.height / 2
  local dx, dy = targetX - self.x, targetY - self.y
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance < 24 then -- already at the spot: head for the room centre instead
    dx, dy = self.world.width / 2 - self.x, self.world.height / 2 - self.y
    distance = math.sqrt(dx * dx + dy * dy)
  end
  if distance < 1 then
    dx, dy, distance = 1, -1, math.sqrt(2)
  end
  local speed = math.sqrt(self.finalVx * self.finalVx + self.finalVy * self.finalVy)
  self.finalVx = dx / distance * speed
  self.finalVy = dy / distance * speed
end

function TheGeometric:updateFinalMovement(dt, solids)
  solids = solids or self.lastSolids or {}
  self.lastSolids = solids
  self.ghostTimer = math.max(0, (self.ghostTimer or 0) - dt)
  local ghost = self.ghostTimer > 0
  local wallRadius = self:getWallRadius()

  -- First final frame (or after loading a save): get out of any prop we spawned inside.
  if not self.finalPlaced then
    self.finalPlaced = true
    if overlapsAnySolid(self.x, self.y, wallRadius, solids) then
      local freeX, freeY = self:findFreeSpot(solids)
      if freeX then
        self.x, self.y = freeX, freeY
      end
    end
  end

  local minX, maxX = self.radius, self.world.width - self.radius
  local minY, maxY = self.radius, self.world.height - self.radius
  local stepCount = math.max(
    1,
    math.ceil(math.max(math.abs(self.finalVx), math.abs(self.finalVy)) * dt / 8)
  )
  local step = dt / stepCount
  local stillOverlapping = false

  for _ = 1, stepCount do
    self.x = self.x + self.finalVx * step
    self.y = self.y + self.finalVy * step
    if not ghost then
      self:resolveSolids(solids)
    end
    -- Room bounds last, so they always win.
    if self.x < minX then
      self.x = minX + (minX - self.x)
      self.finalVx = math.abs(self.finalVx)
    elseif self.x > maxX then
      self.x = maxX - (self.x - maxX)
      self.finalVx = -math.abs(self.finalVx)
    end
    if self.y < minY then
      self.y = minY + (minY - self.y)
      self.finalVy = math.abs(self.finalVy)
    elseif self.y > maxY then
      self.y = maxY - (self.y - maxY)
      self.finalVy = -math.abs(self.finalVy)
    end
    if not ghost and overlapsAnySolid(self.x, self.y, wallRadius, solids) then
      stillOverlapping = true
    end
  end

  -- Stuck detection: still overlapping after resolution, or barely moving.
  self.overlapFrames = stillOverlapping and (self.overlapFrames or 0) + 1 or 0
  self.stuckTimer = (self.stuckTimer or 0) + dt
  local stuck = self.overlapFrames >= 4
  if self.stuckTimer >= STUCK_CHECK_INTERVAL then
    self.stuckTimer = 0
    local anchorX, anchorY = self.stuckAnchorX or self.x, self.stuckAnchorY or self.y
    local dx, dy = self.x - anchorX, self.y - anchorY
    if dx * dx + dy * dy < STUCK_MIN_TRAVEL * STUCK_MIN_TRAVEL and not ghost then
      stuck = true
    elseif not stuck then
      self.unstickCount = 0 -- moving normally again
    end
    self.stuckAnchorX, self.stuckAnchorY = self.x, self.y
  end
  if stuck then
    self:unstick(solids)
  end
  self.moving = true
end

function TheGeometric:update(dt, player, walls)
  if not self.alive then
    return
  end

  self.animationTime = self.animationTime + dt
  self.contactCooldown = math.max(0, self.contactCooldown - dt)
  for index = #self.headShatters, 1, -1 do
    local shatter = self.headShatters[index]
    shatter.timer = shatter.timer - dt
    if shatter.timer <= 0 then
      table.remove(self.headShatters, index)
    end
  end
  for _, head in ipairs(self.heads) do
    head.hitFlashTimer = math.max(0, (head.hitFlashTimer or 0) - dt)
  end
  if self.phase == 'final' then
    self.finalShakeTimer = (self.finalShakeTimer or 0) + dt
    while self.finalShakeTimer >= 0.12 do
      self.finalShakeTimer = self.finalShakeTimer - 0.12
      if self.onScreenShake then
        self.onScreenShake(2.5, 'final_bounce')
      end
    end
  end
  if self.phase == 'body_recovery' then
    self.bodyInvulnerabilityTimer = math.max(0, self.bodyInvulnerabilityTimer - dt)
    if self.bodyInvulnerabilityTimer <= 0 then
      self.phase = 'body_final'
    end
  end

  if self.phase == 'final' then
    self:updateFinalMovement(dt, walls)
  else
    local offsetX, offsetY = player.x - self.x, player.y - self.y
    local distance = math.sqrt(offsetX * offsetX + offsetY * offsetY)
    local playerRadius = math.max(player.width, player.height) / 2
    local collisionDistance = self.radius + playerRadius
    local stoppingDistance = collisionDistance - 4
    self.moving = distance > stoppingDistance

    if self.moving and distance > 0 then
      local movement = math.min(self.speed * dt, distance - stoppingDistance)
      self.x = self.x + offsetX / distance * movement
      self.y = self.y + offsetY / distance * movement
      if math.abs(offsetX) > math.abs(offsetY) then
        self.facing = offsetX < 0 and 'left' or 'right'
      else
        self.facing = 'forward'
      end
    end

    local boundary = self.radius
    self.x = math.max(boundary, math.min(self.world.width - boundary, self.x))
    self.y = math.max(boundary, math.min(self.world.height - boundary, self.y))
    self.headOrbitAngle = self.headOrbitAngle + dt * (self.shieldActive and 1.8 or 1.1)
    self:updateHeadPositions()

    offsetX, offsetY = player.x - self.x, player.y - self.y
    if offsetX * offsetX + offsetY * offsetY <= collisionDistance * collisionDistance
        and self.contactCooldown <= 0 then
      player:takeDamage(10)
      self.contactCooldown = 1
    end
  end

  if self.phase == 'final' then
    local offsetX, offsetY = player.x - self.x, player.y - self.y
    local playerRadius = math.max(player.width, player.height) / 2
    local contactDistance = self.radius + playerRadius
    if offsetX * offsetX + offsetY * offsetY <= contactDistance * contactDistance
        and self.contactCooldown <= 0 then
      player:takeDamage(10)
      self.contactCooldown = 0.65
    end
  end
end

function TheGeometric:getFrame()
  if self.phase == 'final' then
    return self.animationTime % 1.5 < 0.12 and 'headForwardBlink' or 'headForward'
  end
  if self.moving then
    return math.floor(self.animationTime / 0.18) % 2 == 0 and 'bodyWalk' or 'bodyWalkAlt'
  end
  if self.facing == 'right' or self.facing == 'left' then
    return self.animationTime % 4 < 0.14 and 'headRightBlink' or 'headRight'
  end
  return self.animationTime % 4 < 0.14 and 'headForwardBlink' or 'headForward'
end

return TheGeometric