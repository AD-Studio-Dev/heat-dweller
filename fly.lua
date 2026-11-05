-- A small homing enemy that periodically commits to a straight dash.
local Fly = {}
Fly.__index = Fly
local Wet = require('wet')

Fly.imagePath = 'resources/gfx/enemies/spritesheets/enemies_003_fly.png'
Fly.frames = {
  appear = {
    { x = 0, y = 0, w = 32, h = 32, duration = 0.1 },
    { x = 32, y = 0, w = 32, h = 32, duration = 0.1 },
    { x = 64, y = 0, w = 32, h = 32, duration = 0.1 },
    { x = 96, y = 0, w = 32, h = 32, duration = 0.1 },
  },
  idle = {
    { x = 0, y = 32, w = 32, h = 32, duration = 0.035 },
    { x = 32, y = 32, w = 32, h = 32, duration = 0.035 },
  },
}

function Fly.load()
  if Fly.image then
    return
  end

  Fly.image = love.graphics.newImage(Fly.imagePath)
  Fly.image:setFilter('nearest', 'nearest')
  local imageWidth, imageHeight = Fly.image:getDimensions()

  for _, animation in pairs(Fly.frames) do
    for _, frame in ipairs(animation) do
      frame.quad = love.graphics.newQuad(
        frame.x, frame.y, frame.w, frame.h, imageWidth, imageHeight
      )
    end
  end
end

function Fly:new(x, y)
  if not Fly.image then
    Fly.load()
  end

  return setmetatable({
    kind = 'fly',
    x = x or 0,
    y = y or 0,
    width = 40,
    height = 40,
    health = 5,
    damage = 0.5,
    speed = 285,
    acceleration = 900,
    drag = 0.35,
    velocityX = 0,
    velocityY = 0,
    contactRadius = 20,
    attackCooldown = 0,
    attackInterval = 0.75,
    alive = true,
    state = 'appearing',
    animationName = 'appear',
    animationFrame = 1,
    animationTimer = 0,
    dashCooldown = 5,
    dashDuration = 0.32,
    dashSpeed = 560,
    recoveryDuration = 0.55,
    stateTimer = 0,
    dashDirectionX = 0,
    dashDirectionY = 0,
    driftAngle = math.random() * math.pi * 2,
    driftTargetX = nil,
    driftTargetY = nil,
    driftTimer = 0,
  }, Fly)
end

function Fly:updateAnimation(dt)
  local frames = Fly.frames[self.animationName]
  self.animationTimer = self.animationTimer + dt

  while self.animationTimer >= frames[self.animationFrame].duration do
    self.animationTimer = self.animationTimer - frames[self.animationFrame].duration
    if self.animationName == 'appear' and self.animationFrame == #frames then
      self.animationName = 'idle'
      self.animationFrame = 1
      self.state = 'tracking'
      break
    end
    self.animationFrame = self.animationFrame % #frames + 1
  end
end

function Fly:updateDrift(dt, world)
  local margin = math.max(self.width, self.height) / 2
  local targetReached = self.driftTargetX
    and math.sqrt((self.driftTargetX - self.x) ^ 2 + (self.driftTargetY - self.y) ^ 2) <= 48

  if self.driftTimer <= 0 or targetReached then
    self.driftTargetX = math.random(margin, world.width - margin)
    self.driftTargetY = math.random(margin, world.height - margin)
    self.driftTimer = math.random(2, 4)
  end

  self.driftTimer = self.driftTimer - dt
  local targetX = self.driftTargetX - self.x
  local targetY = self.driftTargetY - self.y
  local targetDistance = math.sqrt(targetX * targetX + targetY * targetY)
  if targetDistance > 0 then
    self.driftAngle = math.atan2(targetY, targetX)
    return targetX / targetDistance, targetY / targetDistance
  end
  return 0, 0
end

function Fly:applyMovementForces(dt, directionX, directionY, maximumSpeed, world)
  local dragFactor = math.exp(-self.drag * dt)
  self.velocityX = self.velocityX * dragFactor + directionX * self.acceleration * dt
  self.velocityY = self.velocityY * dragFactor + directionY * self.acceleration * dt

  local velocity = math.sqrt(self.velocityX * self.velocityX + self.velocityY * self.velocityY)
  if velocity > maximumSpeed then
    local scale = maximumSpeed / velocity
    self.velocityX = self.velocityX * scale
    self.velocityY = self.velocityY * scale
  end

  local halfWidth = self.width / 2
  local halfHeight = self.height / 2
  self.x = math.max(halfWidth, math.min(world.width - halfWidth, self.x + self.velocityX * dt))
  self.y = math.max(halfHeight, math.min(world.height - halfHeight, self.y + self.velocityY * dt))
  if self.x == halfWidth and self.velocityX < 0
      or self.x == world.width - halfWidth and self.velocityX > 0 then
    self.velocityX = 0
  end
  if self.y == halfHeight and self.velocityY < 0
      or self.y == world.height - halfHeight and self.velocityY > 0 then
    self.velocityY = 0
  end
end

function Fly:update(dt, player, world)
  if not self.alive then
    return
  end
  local speedScale = Wet.update(self, dt)

  local wasAppearing = self.state == 'appearing'
  self:updateAnimation(dt)
  if wasAppearing then
    self.velocityX = 0
    self.velocityY = 0
    return
  end

  local distanceX = player.x - self.x
  local distanceY = player.y - self.y
  local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY)

  if self.state ~= 'appearing' then
    self.dashCooldown = self.dashCooldown - dt
  end

  local directionX, directionY = 0, 0
  local maximumSpeed = self.speed * speedScale
  if self.state == 'tracking' then
    if self.dashCooldown <= 0 then
      if distance > 0 then
        self.dashDirectionX = distanceX / distance
        self.dashDirectionY = distanceY / distance
      else
        self.dashDirectionX = 0
        self.dashDirectionY = 0
      end
      self.state = 'dashing'
      self.stateTimer = self.dashDuration
      self.dashCooldown = 5
    else
      directionX, directionY = self:updateDrift(dt, world)
    end
  end

  if self.state == 'dashing' then
    directionX = self.dashDirectionX
    directionY = self.dashDirectionY
    maximumSpeed = self.dashSpeed * speedScale
    self.stateTimer = self.stateTimer - dt
    if self.stateTimer <= 0 then
      self.state = 'recovering'
      self.stateTimer = self.recoveryDuration
    end
  elseif self.state == 'recovering' then
    self.stateTimer = self.stateTimer - dt
    if self.stateTimer <= 0 then
      self.state = 'tracking'
    end
  end

  self:applyMovementForces(dt, directionX, directionY, maximumSpeed, world)

  distanceX = player.x - self.x
  distanceY = player.y - self.y
  distance = math.sqrt(distanceX * distanceX + distanceY * distanceY)
  self.attackCooldown = math.max(0, self.attackCooldown - dt)
  if distance <= self.contactRadius and self.attackCooldown <= 0 then
    player:takeDamage(self.damage)
    self.attackCooldown = self.attackInterval
  end
end

function Fly:draw(camera)
  if not self.alive then
    return
  end

  camera = camera or { x = 0, y = 0 }
  local screenX = math.floor(self.x - camera.x)
  local screenY = math.floor(self.y - camera.y)

  local frame = Fly.frames[self.animationName][self.animationFrame]
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(Fly.image, frame.quad, screenX, screenY, 0, 1.25, 1.25, 16, 16)
  love.graphics.setColor(1, 1, 1, 1)
end

return Fly
