-- A ground enemy that can split into smaller versions after a timed interval.
local Centipede = {}
Centipede.__index = Centipede
local Wet = require('wet')

function Centipede.new(config)
  config = config or {}
  local scale = config.scale or 1
  local baseWidth = 56 * scale
  local baseHeight = 56 * scale
  return setmetatable({
    kind = 'centipede',
    x = config.x or 800,
    y = config.y or 600,
    width = baseWidth,
    height = baseHeight,
    scale = scale,
    health = config.health or 10,
    maxHealth = config.maxHealth or config.health or 8,
    damage = config.damage or 0.7,
    speed = config.speed or 180,
    aggroRadius = 360,
    contactRadius = 28 * scale,
    attackCooldown = 0,
    attackInterval = 0.75,
    aggravated = false,
    animationTime = 0,
    alive = true,
    splitTimer = 0,
    splitInterval = 5,
    splitChance = config.splitChance or 0.5,
    can_split = config.can_split ~= false,
  }, Centipede)
end

function Centipede:update(dt, player)
  if not self.alive then
    return nil
  end

  local speedScale = Wet.update(self, dt)
  local distanceX = player.x - self.x
  local distanceY = player.y - self.y
  local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY)

  if not self.aggravated and distance <= self.aggroRadius then
    self.aggravated = true
    self.animationTime = 0
  end

  if self.aggravated then
    self.animationTime = self.animationTime + dt
    self.splitTimer = self.splitTimer + dt

    if distance > 0 then
      self.vx = (distanceX / distance) * self.speed * speedScale
      self.vy = (distanceY / distance) * self.speed * speedScale
    else
      self.vx = 0
      self.vy = 0
    end

    if distance > self.contactRadius and distance > 0 then
      self.x = self.x + self.vx * dt
      self.y = self.y + self.vy * dt
    end

    self.attackCooldown = math.max(0, self.attackCooldown - dt)
    if distance <= self.contactRadius and self.attackCooldown <= 0 then
      player:takeDamage(self.damage)
      self.attackCooldown = self.attackInterval
    end

    if self.can_split and self.splitTimer >= self.splitInterval then
      self.splitTimer = 0
      if math.random() < self.splitChance then
        self.alive = false
        local childScale = 0.5
        local childHealth = math.max(1, self.health * 0.5)
        return {
          Centipede.new({
            x = self.x - 24,
            y = self.y,
            health = childHealth,
            maxHealth = childHealth,
            speed = self.speed * 0.96,
            scale = childScale,
            can_split = false,
            splitChance = 0,
          }),
          Centipede.new({
            x = self.x + 24,
            y = self.y,
            health = childHealth,
            maxHealth = childHealth,
            speed = self.speed * 0.96,
            scale = childScale,
            can_split = false,
            splitChance = 0,
          }),
        }
      end
    end
  end

  return nil
end

return Centipede
