-- Baby Widow follows the same wall perimeter as the Crawler at a smaller scale.
local BabyWidow = {}
BabyWidow.__index = BabyWidow
local Wet = require('wet')

function BabyWidow.new(world, config)
  config = config or {}
  local margin = world.tileSize * 0.8
  local points = {
    { x = margin, y = margin },
    { x = world.width - margin, y = margin },
    { x = world.width - margin, y = world.height - margin },
    { x = margin, y = world.height - margin },
  }

  return setmetatable({
    points = points,
    pathIndex = 2,
    x = points[2].x,
    y = points[2].y,
    speed = config.speed or 135,
    width = 64,
    height = 64,
    health = config.health or 50,
    damage = config.damage or 0.35,
    contactRadius = 42,
    attackInterval = 0.9,
    aggravated = false,
    animationTime = 0,
    spiderSpawnTimer = 0,
    spiderSpawnCooldown = config.spiderSpawnCooldown or 10,
    attackCooldown = config.attackCooldown or 3.5,
    attackWindup = 0,
    attackWindupDuration = 0.65,
    alive = true,
    onDamaged = config.onDamaged,
    onDeath = config.onDeath,
    onAttackStart = config.onAttackStart,
    onAttackRelease = config.onAttackRelease,
  }, BabyWidow)
end

function BabyWidow:update(dt, player)
  if not self.alive then
    return 0
  end
  local speedScale = Wet.update(self, dt)

  self.animationTime = self.animationTime + dt

  if self.attackWindup > 0 then
    self.attackWindup = self.attackWindup - dt
    if self.attackWindup <= 0 then
      self.attackWindup = 0
      if self.onAttackRelease then
        self.onAttackRelease(player.x, player.y)
      end
    end
    return 0
  end

  self.attackCooldown = self.attackCooldown - dt
  if self.attackCooldown <= 0 then
    self.attackCooldown = 5.5
    self.attackWindup = self.attackWindupDuration
    if self.onAttackStart then
      self.onAttackStart()
    end
    return 0
  end

  self.spiderSpawnTimer = self.spiderSpawnTimer + dt
  local spawnedCount = 0
  while self.spiderSpawnTimer >= (self.spiderSpawnCooldown or 10) do
    self.spiderSpawnTimer = self.spiderSpawnTimer - (self.spiderSpawnCooldown or 10)
    spawnedCount = spawnedCount + 1
  end

  local remaining = self.speed * speedScale * dt
  while remaining > 0 do
    local nextIndex = self.pathIndex % #self.points + 1
    local target = self.points[nextIndex]
    local distanceX = target.x - self.x
    local distanceY = target.y - self.y
    local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY)

    if distance <= remaining then
      self.x = target.x
      self.y = target.y
      self.pathIndex = nextIndex
      remaining = remaining - distance
    else
      self.x = self.x + distanceX / distance * remaining
      self.y = self.y + distanceY / distance * remaining
      remaining = 0
    end
  end

  local distanceX = player.x - self.x
  local distanceY = player.y - self.y
  local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY)
  if distance <= self.contactRadius then
    self.attackCooldown = math.max(0, self.attackCooldown - dt)
    if self.attackCooldown <= 0 then
      player:takeDamage(self.damage)
      self.attackCooldown = self.attackInterval
    end
  end

  return spawnedCount
end

function BabyWidow:getFrame()
  return math.floor(self.animationTime / 0.1) % 2 + 1
end

return BabyWidow