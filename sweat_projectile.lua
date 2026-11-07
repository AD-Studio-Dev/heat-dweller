local SweatProjectile = {}
local Knockback = require('knockback')

local projectileSpeed = 480
local projectileRadius = 7
local maxRange = 540
local splashDuration = 0.13

function SweatProjectile.new(x, y, directionX, directionY)
  local length = math.sqrt(directionX * directionX + directionY * directionY)
  if length == 0 then
    return nil
  end

  directionX = directionX / length
  directionY = directionY / length
  local angle = math.atan2(directionY, directionX)

  return {
    x = x + directionX * 12,
    y = y - 22 + directionY * 10,
    vx = math.cos(angle) * projectileSpeed,
    vy = math.sin(angle) * projectileSpeed,
    angle = angle,
    distance = 0,
    alive = true,
  }
end

local function hitsWall(x, y, walls, world)
  if x < projectileRadius or y < projectileRadius
      or x > world.width - projectileRadius or y > world.height - projectileRadius then
    return true
  end

  for _, wall in ipairs(walls) do
    if x + projectileRadius >= wall.x and x - projectileRadius <= wall.x + wall.width
        and y + projectileRadius >= wall.y and y - projectileRadius <= wall.y + wall.height then
      return true
    end
  end
  return false
end

local function collidingTarget(x, y, targets)
  for _, target in ipairs(targets) do
    if target.alive then
      local passThrough = target.projectilePassThroughWhenInvulnerable
        and target.isInvulnerable and target:isInvulnerable()
      if not passThrough then
        local dx = target.x - x
        local dy = target.y - y
        local targetRadius = math.max(target.width or 40, target.height or 40) / 2
        local hitRadius = targetRadius + projectileRadius
        if dx * dx + dy * dy <= hitRadius * hitRadius then
          return target
        end
      end
    end
  end
end

local function spawnSplash(splashes, x, y)
  splashes[#splashes + 1] = { x = x, y = y, elapsed = 0 }
end

function SweatProjectile.updateAll(projectiles, splashes, dt, targets, walls, world, damage)
  local defeated = {}

  for index = #projectiles, 1, -1 do
    local projectile = projectiles[index]
    local speed = math.sqrt(projectile.vx * projectile.vx
      + projectile.vy * projectile.vy)
    local stepCount = math.max(1, math.ceil(speed * dt / 5))
    local step = dt / stepCount
    local impactTarget

    for _ = 1, stepCount do
      local moveX = projectile.vx * step
      local moveY = projectile.vy * step
      projectile.x = projectile.x + moveX
      projectile.y = projectile.y + moveY
      projectile.distance = projectile.distance + math.sqrt(moveX * moveX + moveY * moveY)
      local hitWall = hitsWall(projectile.x, projectile.y, walls, world)
      impactTarget = collidingTarget(projectile.x, projectile.y, targets)

      if hitWall or impactTarget then
        if impactTarget and not hitWall then
          local defeatedTarget
          if impactTarget.takeDamage then
            defeatedTarget = impactTarget:takeDamage(damage)
          else
            impactTarget.health = math.max(0, impactTarget.health - damage)
            if impactTarget.onDamaged then
              impactTarget.onDamaged()
            end
            if impactTarget.health == 0 then
              impactTarget.alive = false
              defeatedTarget = true
            end
          end
          if defeatedTarget then
            defeated[#defeated + 1] = impactTarget
            if impactTarget.onDeath then
              impactTarget.onDeath()
            end
          else
            -- Shove the enemy along the shot's direction; smaller enemies fly farther.
            Knockback.apply(impactTarget, projectile.vx, projectile.vy)
          end
        end
        spawnSplash(splashes, projectile.x, projectile.y)
        break
      end

      if projectile.distance >= maxRange then
        break
      end
    end

    if impactTarget or projectile.distance >= maxRange
        or hitsWall(projectile.x, projectile.y, walls, world) then
      table.remove(projectiles, index)
    end
  end

  for index = #splashes, 1, -1 do
    splashes[index].elapsed = splashes[index].elapsed + dt
    if splashes[index].elapsed >= splashDuration then
      table.remove(splashes, index)
    end
  end

  return defeated
end

function SweatProjectile.getSplashProgress(splash)
  return math.max(0, 1 - splash.elapsed / splashDuration)
end

return SweatProjectile