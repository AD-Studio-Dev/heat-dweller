-- Scar enemy behavior and state.
local Enemy = {}
Enemy.__index = Enemy
local Wet = require('wet')

function Enemy.new(config)
  config = config or {}

  return setmetatable({
    kind = config.kind or 'scar',
    x = config.x or 1100,
    y = config.y or 600,
    width = 64,
    height = 64,
    health = config.health or 5.5,
    damage = config.damage or 0.5,
    speed = config.speed or 90,
    aggroRadius = config.aggroRadius or 260,
    contactRadius = config.contactRadius or 52,
    attackCooldown = 0,
    attackInterval = config.attackInterval or 0.75,
    aggravated = false,
    animationTime = 0,
    alive = true,
    state = 'idle',
    attackTimer = config.attackTimer or 3.2,
    windupTimer = 0,
    dashTimer = 0,
    dashDirectionX = 0,
    dashDirectionY = 0,
    dashDistance = config.dashDistance or 220,
    dashSpeed = config.dashSpeed or 430,
    currentTargetX = 0,
    currentTargetY = 0,
  }, Enemy)
end

function Enemy:update(dt, player)
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
    self.attackCooldown = math.max(0, self.attackCooldown - dt)

    if self.state == 'idle' then
      self.attackTimer = self.attackTimer - dt
      if distance > self.contactRadius and distance > 0 then
        self.x = self.x + distanceX / distance * self.speed * speedScale * dt * 0.6
        self.y = self.y + distanceY / distance * self.speed * speedScale * dt * 0.6
      end

      if self.attackTimer <= 0 then
        self.state = 'windup'
        self.windupTimer = 0.2
        self.currentTargetX = player.x
        self.currentTargetY = player.y
      end
    elseif self.state == 'windup' then
      self.windupTimer = self.windupTimer - dt
      if self.windupTimer <= 0 then
        local dashTargetX = self.currentTargetX
        local dashTargetY = self.currentTargetY
        local dashDx = dashTargetX - self.x
        local dashDy = dashTargetY - self.y
        local dashDistance = math.sqrt(dashDx * dashDx + dashDy * dashDy)
        if dashDistance > 0 then
          self.dashDirectionX = dashDx / dashDistance
          self.dashDirectionY = dashDy / dashDistance
        else
          self.dashDirectionX = 0
          self.dashDirectionY = 0
        end
        self.state = 'dashing'
        self.dashTimer = 0.72
      end
    elseif self.state == 'dashing' then
      local step = self.dashSpeed * dt
      self.x = self.x + self.dashDirectionX * step
      self.y = self.y + self.dashDirectionY * step
      self.dashTimer = self.dashTimer - dt
      if self.dashTimer <= 0 then
        self.state = 'recovering'
        self.dashDirectionX = 0
        self.dashDirectionY = 0
        self.windupTimer = 0.2
      end

      if distance <= self.contactRadius and self.attackCooldown <= 0 then
        player:takeDamage(self.damage)
        self.attackCooldown = self.attackInterval
      end
    elseif self.state == 'recovering' then
      self.windupTimer = self.windupTimer - dt
      if self.windupTimer <= 0 then
        self.state = 'idle'
        self.attackTimer = math.random(3, 4)
      end
    end
  end
end

function Enemy:getFrame()
  if not self.aggravated then
    return 'idle_0'
  end

  if self.state == 'idle' then
    return 'idle_0'
  end

  if self.state == 'windup' then
    if self.windupTimer > 0.1 then
      return 'scream_1'
    end
    return 'scream_2'
  end

  if self.state == 'dashing' then
    local frameIndex = 3 + math.floor((self.animationTime * 10) % 6)
    return 'scream_' .. math.min(frameIndex, 8)
  end

  if self.state == 'recovering' then
    return 'scream_2'
  end

  return 'idle_0'
end

return Enemy