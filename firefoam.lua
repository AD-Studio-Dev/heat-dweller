local Wet = require('wet')

local FireFoam = {}
FireFoam.__index = FireFoam

local directions = {
  right = { x = 1, y = 0 },
  left = { x = -1, y = 0 },
  down = { x = 0, y = 1 },
  up = { x = 0, y = -1 },
}

-- Fire Extinguisher damage per second, as a multiple of the player's damage stat.
-- Brimstone-style: much stronger than the sweat shot (~11.6 dps at base stats,
-- so 2.5 x 20 = 50 dps is roughly 4x), but nowhere near the old 15x (300 dps).
local DAMAGE_PER_SECOND_MULTIPLIER = 2.5

function FireFoam.new()
  return setmetatable({ beam = nil, animationTime = 0 }, FireFoam)
end

local function wallDistance(x, y, direction, world, walls, maximumDistance)
  local distance = maximumDistance
  if direction.x > 0 then
    distance = math.min(distance, world.width - x)
  elseif direction.x < 0 then
    distance = math.min(distance, x)
  elseif direction.y > 0 then
    distance = math.min(distance, world.height - y)
  else
    distance = math.min(distance, y)
  end

  for _, wall in ipairs(walls or {}) do
    local intersects
    local wallDistanceAlongRay
    if direction.x ~= 0 then
      intersects = y >= wall.y and y <= wall.y + wall.height
      wallDistanceAlongRay = direction.x > 0 and wall.x - x or wall.x + wall.width - x
      wallDistanceAlongRay = wallDistanceAlongRay * direction.x
    else
      intersects = x >= wall.x and x <= wall.x + wall.width
      wallDistanceAlongRay = direction.y > 0 and wall.y - y or wall.y + wall.height - y
      wallDistanceAlongRay = wallDistanceAlongRay * direction.y
    end
    if intersects and wallDistanceAlongRay >= 0 and wallDistanceAlongRay < distance then
      distance = wallDistanceAlongRay
    end
  end
  return math.max(0, distance)
end

function FireFoam:update(dt, player, equipped, directionName, targets, world, walls)
  if not equipped or not directionName or not player then
    self.beam = nil
    return {}
  end
  local direction = directions[directionName]
  if not direction then
    self.beam = nil
    return {}
  end

  self.animationTime = self.animationTime + dt
  local maximumDistance = 760
  local distance = wallDistance(player.x, player.y, direction, world, walls, maximumDistance)
  local nearestTarget
  local nearestTargetDistance = distance
  local beamWidth = 24
  for _, target in ipairs(targets) do
    if target and target.alive then
      local offsetX, offsetY = target.x - player.x, target.y - player.y
      local along = offsetX * direction.x + offsetY * direction.y
      local across = math.abs(offsetX * direction.y - offsetY * direction.x)
      local radius = math.max(target.width or 32, target.height or 32) * 0.5
      local invulnerable = target.isInvulnerable and target:isInvulnerable()
      if not invulnerable and along >= 0 and along <= nearestTargetDistance
          and across <= beamWidth + radius then
        nearestTarget = target
        nearestTargetDistance = along
      end
    end
  end

  local contact = nearestTarget ~= nil or distance < maximumDistance
  local beamDistance = nearestTarget and nearestTargetDistance or distance
  self.beam = {
    direction = directionName,
    distance = beamDistance,
    contact = contact,
    animationTime = self.animationTime,
  }

  local killed = {}
  if nearestTarget then
    nearestTarget.foamHitEffectTimer = math.max(0, (nearestTarget.foamHitEffectTimer or 0) - dt)
    if nearestTarget.foamHitEffectTimer <= 0 then
      Wet.apply(nearestTarget, 5)
      nearestTarget.foamHitEffectTimer = 0.3
      if nearestTarget.onDamaged then
        nearestTarget:onDamaged()
      end
    end
    local damagePerSecond = math.max(0, player.stats.damage) * DAMAGE_PER_SECOND_MULTIPLIER
    local defeatedTarget
    if nearestTarget.takeContinuousDamage then
      -- Targets with armor or hit stacking (the Stationary Angel) must not treat
      -- every frame of foam as a separate hit.
      defeatedTarget = nearestTarget:takeContinuousDamage(damagePerSecond * dt)
    elseif nearestTarget.takeDamage then
      defeatedTarget = nearestTarget:takeDamage(damagePerSecond * dt)
    else
      nearestTarget.health = nearestTarget.health - damagePerSecond * dt
      if nearestTarget.health <= 0 then
        nearestTarget.alive = false
        defeatedTarget = true
      end
    end
    if defeatedTarget then
      killed[#killed + 1] = nearestTarget
      if nearestTarget.onDeath then
        nearestTarget:onDeath()
      end
    end
  end
  return killed
end

return FireFoam