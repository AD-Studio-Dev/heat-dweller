-- Standalone Spider enemy used by rooms and the Crawler.
local Spider = {}
Spider.__index = Spider
local Wet = require('wet')

function Spider.new(config)
  config = config or {}

  return setmetatable({
    kind = 'spider',
    x = config.x or 800,
    y = config.y or 600,
    width = 64,
    height = 64,
    health = config.health or 7,
    damage = config.damage or 0.5,
    speed = config.speed or 105,
    aggroRadius = 300,
    contactRadius = 48,
    attackCooldown = 0,
    attackInterval = 0.75,
    aggravated = false,
    animationTime = 0,
    alive = true,
  }, Spider)
end

function Spider:update(dt, player)
  if not self.alive then
    return
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
    if distance > self.contactRadius and distance > 0 then
      self.x = self.x + distanceX / distance * self.speed * speedScale * dt
      self.y = self.y + distanceY / distance * self.speed * speedScale * dt
    end

    self.attackCooldown = math.max(0, self.attackCooldown - dt)
    if distance <= self.contactRadius and self.attackCooldown <= 0 then
      player:takeDamage(self.damage)
      self.attackCooldown = self.attackInterval
    end
  end
end

function Spider:getFrame()
  return math.floor(self.animationTime / 0.1) % 2 + 1
end

return Spider