local TheStuffing = {}
TheStuffing.__index = TheStuffing

local function clamp(value, minimum, maximum)
  return math.min(maximum, math.max(minimum, value))
end

function TheStuffing.new(world)
  local spawnX = world.width / 2
  local spawnY = world.height * 0.36
  return setmetatable({
    kind = 'stuffing',
    x = spawnX,
    y = spawnY,
    spawnX = spawnX,
    spawnY = spawnY,
    width = 256,
    height = 256,
    radius = 140,
    health = 420,
    maxHealth = 420,
    alive = true,
    world = world,
    animationTime = 0,
    phase = 1,
    charred = false,
    suctioning = true,
    attackTimer = 0,
    stateTimer = 5.5,
    pullStrength = 980,
    projectileTimer = 0,
    patternMode = 0,
    projectiles = {},
  }, TheStuffing)
end

function TheStuffing:beginPhaseTwo()
  if self.phase >= 2 then
    return
  end

  self.phase = 2
  self.charred = true
  self.width = 256
  self.height = 256
  self.radius = 160
  self.pullStrength = 1420
  self.projectileTimer = 0
  self.stateTimer = 5.5
  self.suctioning = true
end

function TheStuffing:takeDamage(amount)
  if not self.alive then
    return false
  end

  self.health = math.max(0, self.health - amount)
  if self.health <= self.maxHealth * 0.5 and self.phase == 1 then
    self:beginPhaseTwo()
  end
  if self.health <= 0 then
    self.alive = false
    return true
  end
  return false
end

local function getDirectionalResistance(player, directionX, directionY)
  local resistance = 0
  if love.keyboard.isDown('a', 'left') and directionX > 0 then
    resistance = resistance + 1
  end
  if love.keyboard.isDown('d', 'right') and directionX < 0 then
    resistance = resistance + 1
  end
  if love.keyboard.isDown('w', 'up') and directionY > 0 then
    resistance = resistance + 1
  end
  if love.keyboard.isDown('s', 'down') and directionY < 0 then
    resistance = resistance + 1
  end
  return math.min(0.85, resistance * 0.28)
end

function TheStuffing:fireProjectile(player)
  local offsetX = player.x - self.x
  local offsetY = player.y - self.y
  local distance = math.sqrt(offsetX * offsetX + offsetY * offsetY)
  if distance <= 0.001 then
    offsetX, offsetY = 1, 0
    distance = 1
  end

  local speed = self.phase == 2 and 290 or 210
  local count = self.phase == 2 and 5 or 3
  local directMode = self.patternMode % 2 == 0
  self.patternMode = self.patternMode + 1

  if directMode then
    local angle = math.atan2(offsetY, offsetX)
    self.projectiles[#self.projectiles + 1] = {
      x = self.x,
      y = self.y,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      radius = 12,
      alive = true,
      lifetime = 4,
    }
    return
  end

  local baseAngle = math.atan2(offsetY, offsetX)
  local spread = self.phase == 2 and 0.52 or 0.34
  for index = 0, count - 1 do
    local angle = baseAngle - spread * ((count - 1) / 2) + spread * index
    self.projectiles[#self.projectiles + 1] = {
      x = self.x,
      y = self.y,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      radius = 12,
      alive = true,
      lifetime = 4,
    }
  end
end

function TheStuffing:update(dt, player, walls)
  if not self.alive then
    return
  end

  self.animationTime = self.animationTime + dt
  self.stateTimer = self.stateTimer - dt
  self.projectileTimer = self.projectileTimer - dt

  for index = #self.projectiles, 1, -1 do
    local projectile = self.projectiles[index]
    projectile.x = projectile.x + projectile.vx * dt
    projectile.y = projectile.y + projectile.vy * dt
    projectile.lifetime = projectile.lifetime - dt
    local dx = player.x - projectile.x
    local dy = player.y - projectile.y
    local hitDistance = dx * dx + dy * dy
    if projectile.lifetime <= 0 or hitDistance <= 28 * 28 then
      if hitDistance <= 28 * 28 then
        player:takeDamage(self.phase == 2 and 10 or 7)
      end
      table.remove(self.projectiles, index)
    end
  end

  if self.phase == 1 and self.health <= self.maxHealth * 0.5 then
    self:beginPhaseTwo()
  end

  if self.stateTimer <= 0 then
    if self.suctioning then
      self.suctioning = false
      self.stateTimer = self.phase == 2 and 1.1 or 1.5
    else
      self.suctioning = true
      self.stateTimer = self.phase == 2 and 5.8 or 5.2
      self.projectileTimer = 0
    end
  end

  self.x = self.spawnX
  self.y = self.spawnY

  if self.suctioning then
    local dx = self.x - player.x
    local dy = self.y - player.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local activeDistance = self.radius + 170

    if distance > 0 and distance < activeDistance then
      local directionX = dx / distance
      local directionY = dy / distance
      local resistance = getDirectionalResistance(player, directionX, directionY)

      local distanceFalloff = math.max(0.24, 1 - (distance / activeDistance))
      local basePull = self.pullStrength * 0.42
      local pull = basePull * distanceFalloff * dt * (1.0 - resistance)
      if self.phase == 2 then
        pull = pull * 1.2
      end

      player.x = player.x + directionX * pull
      player.y = player.y + directionY * pull
      player.x = clamp(player.x, 56, self.world.width - 56)
      player.y = clamp(player.y, 56, self.world.height - 56)
    end

    if self.projectileTimer <= 0 then
      self:fireProjectile(player)
      self.projectileTimer = 0.5
    end
  end

  self.x = clamp(self.x, 140, self.world.width - 140)
  self.y = clamp(self.y, 120, self.world.height - 110)
end

return TheStuffing
