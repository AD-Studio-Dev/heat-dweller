-- Lil' Snake follows Matthew while a sampled trail keeps its body segmented.
local LilSnake = {}
LilSnake.__index = LilSnake
local Wet = require('wet')

LilSnake.frameData = {
  headRight = { x = 0, y = 0, w = 48, h = 48, duration = 0.1 },
  headRightFlick = { x = 48, y = 0, w = 48, h = 48, duration = 0.1 },
  headUp = { x = 96, y = 0, w = 48, h = 48, duration = 0.1 },
  headUpFlick = { x = 144, y = 0, w = 48, h = 48, duration = 0.1 },
  bodyUp = { x = 192, y = 0, w = 48, h = 48, duration = 0.1 },
  bodyUpAlt = { x = 0, y = 48, w = 48, h = 48, duration = 0.1 },
  bodyDown = { x = 48, y = 48, w = 48, h = 48, duration = 0.1 },
  bodyDownAlt = { x = 96, y = 48, w = 48, h = 48, duration = 0.1 },
  bodyRight = { x = 144, y = 48, w = 48, h = 48, duration = 0.1 },
  bodyRightAlt = { x = 192, y = 48, w = 48, h = 48, duration = 0.1 },
}

function LilSnake.load()
  if LilSnake.image then
    return
  end

  LilSnake.image = love.graphics.newImage('resources/gfx/bosses/spritesheets/boss_002_lilsnake.png')
  LilSnake.image:setFilter('nearest', 'nearest')
  local imageWidth, imageHeight = LilSnake.image:getDimensions()
  LilSnake.frames = {}

  for name, frame in pairs(LilSnake.frameData) do
    frame.quad = love.graphics.newQuad(
      frame.x, frame.y, frame.w, frame.h, imageWidth, imageHeight
    )
    LilSnake.frames[name] = frame
  end
end

function LilSnake.new(world)
  LilSnake.load()

  local x = world.width / 2
  local y = world.height / 2
  local segmentSpacing = 64
  local trailSampleSpacing = 8
  local segments = 12
  local trail = { { x = x, y = y, lengthToNext = 0 } }
  for index = 1, (segments + 1) * math.ceil(segmentSpacing / trailSampleSpacing) + 2 do
    trail[#trail].lengthToNext = trailSampleSpacing
    trail[#trail + 1] = {
      x = x + index * trailSampleSpacing,
      y = y,
      lengthToNext = 0,
    }
  end

  return setmetatable({
    kind = 'lilsnake',
    x = x,
    y = y,
    width = 96,
    height = 96,
    health = 180,
    maxHealth = 180,
    speed = 180,
    alive = true,
    animationTimer = 0,
    animationFrame = 1,
    facing = 'left',
    trail = trail,
    trailSampleSpacing = trailSampleSpacing,
    trailDistance = 0,
    segmentSpacing = segmentSpacing,
    segmentCount = segments,
    world = world,
    locomotionDirectionX = -1,
    locomotionDirectionY = 0,
    locomotionTurnTimer = 0,
    holeSpawnTimer = 0,
    holes = {},
  }, LilSnake)
end

function LilSnake:getTrailPosition(distanceBehind)
  local remaining = distanceBehind
  for index = 1, #self.trail - 1 do
    local first = self.trail[index]
    local second = self.trail[index + 1]
    local segmentLength = first.lengthToNext
    if not segmentLength then
      segmentLength = math.sqrt((second.x - first.x) ^ 2 + (second.y - first.y) ^ 2)
      first.lengthToNext = segmentLength
    end
    if remaining <= segmentLength then
      local progress = segmentLength > 0 and remaining / segmentLength or 0
      return {
        x = first.x + (second.x - first.x) * progress,
        y = first.y + (second.y - first.y) * progress,
      }
    end
    remaining = remaining - segmentLength
  end
  local last = self.trail[#self.trail]
  return { x = last.x, y = last.y }
end

function LilSnake:normalizeTrail()
  for index = 1, #self.trail - 1 do
    local first = self.trail[index]
    local second = self.trail[index + 1]
    if not first.lengthToNext then
      first.lengthToNext = math.sqrt((second.x - first.x) ^ 2 + (second.y - first.y) ^ 2)
    end
  end
end

function LilSnake:getSegmentPosition(index)
  return self:getTrailPosition(self.segmentSpacing * index)
end

function LilSnake:recordHeadMovement(distance)
  if distance <= 0 then
    return
  end

  table.insert(self.trail, 1, {
    x = self.x,
    y = self.y,
    lengthToNext = distance,
  })
  local maximumHistoryLength = self.segmentCount * self.segmentSpacing + self.segmentSpacing
  local historyLength = 0
  for index = 1, #self.trail - 1 do
    historyLength = historyLength + self.trail[index].lengthToNext
  end
  while historyLength > maximumHistoryLength and #self.trail > 2 do
    historyLength = historyLength - self.trail[#self.trail - 1].lengthToNext
    table.remove(self.trail)
  end
  self.trailDistance = 0
end

local function getCardinalDirection(offsetX, offsetY)
  if math.abs(offsetX) >= math.abs(offsetY) then
    return offsetX < 0 and -1 or 1, 0
  end
  return 0, offsetY < 0 and -1 or 1
end

function LilSnake:chooseLocomotionDirection(player)
  local offsetX, offsetY = player.x - self.x, player.y - self.y
  local directionX, directionY = self.locomotionDirectionX, self.locomotionDirectionY
  if offsetX ~= 0 or offsetY ~= 0 then
    local targetX, targetY = getCardinalDirection(offsetX, offsetY)
    if math.random() < 0.65 then
      directionX, directionY = targetX, targetY
    else
      local alternatives
      if directionX ~= 0 then
        alternatives = { { directionX, 0 }, { 0, -1 }, { 0, 1 } }
      else
        alternatives = { { 0, directionY }, { -1, 0 }, { 1, 0 } }
      end
      local choice = alternatives[math.random(1, #alternatives)]
      directionX, directionY = choice[1], choice[2]
    end
  end

  self.locomotionDirectionX, self.locomotionDirectionY = directionX, directionY
  self.locomotionTurnTimer = 0.45 + math.random() * 0.65
  return directionX, directionY
end

function LilSnake:spawnFloorHole(player)
  local radius = 30
  local safeDistance = radius + math.max(player.width, player.height) / 2 + 12
  local playerOffsetX, playerOffsetY = player.x - self.x, player.y - self.y
  if playerOffsetX * playerOffsetX + playerOffsetY * playerOffsetY < safeDistance * safeDistance then
    return
  end

  for _, hole in ipairs(self.holes) do
    local offsetX, offsetY = hole.x - self.x, hole.y - self.y
    local minimumDistance = radius * 2 + 12
    if offsetX * offsetX + offsetY * offsetY < minimumDistance * minimumDistance then
      return
    end
  end

  self.holes[#self.holes + 1] = {
    x = self.x,
    y = self.y,
    radius = radius,
    lifetime = 20,
  }
end

function LilSnake:updateFloorHoles(dt)
  for index = #self.holes, 1, -1 do
    local hole = self.holes[index]
    hole.lifetime = (hole.lifetime or 20) - dt
    if hole.lifetime <= 0 then
      table.remove(self.holes, index)
    end
  end
end

function LilSnake:update(dt, player)
  self:updateFloorHoles(dt)
  if not self.alive then
    return
  end
  local speedScale = Wet.update(self, dt)

  self:normalizeTrail()
  self.animationTimer = self.animationTimer + dt
  self.locomotionTurnTimer = self.locomotionTurnTimer - dt
  local frameDuration = LilSnake.frameData.headRight.duration
  while self.animationTimer >= frameDuration do
    self.animationTimer = self.animationTimer - frameDuration
    self.animationFrame = self.animationFrame % 2 + 1
  end

  if self.locomotionTurnTimer <= 0 then
    self:chooseLocomotionDirection(player)
  end
  local directionX, directionY = self.locomotionDirectionX, self.locomotionDirectionY
  if directionX ~= 0 then
    self.facing = directionX < 0 and 'left' or 'right'
  else
    self.facing = directionY < 0 and 'up' or 'down'
  end

  local oldX, oldY = self.x, self.y
  local movement = self.speed * speedScale * dt
  local boundary = math.max(self.width, self.height) / 2
  self.x = math.max(boundary, math.min(self.world.width - boundary, self.x + directionX * movement))
  self.y = math.max(boundary, math.min(self.world.height - boundary, self.y + directionY * movement))
  local distanceMoved = math.abs(self.x - oldX) + math.abs(self.y - oldY)
  self:recordHeadMovement(distanceMoved)

  if distanceMoved > 0 then
    self.holeSpawnTimer = self.holeSpawnTimer + dt
  else
    self.holeSpawnTimer = 0
  end
  if self.holeSpawnTimer >= 2 - 1e-9 then
    self.holeSpawnTimer = self.holeSpawnTimer - 2
    self:spawnFloorHole(player)
  end
end

-- Returns 'head', 'body' or nil depending on what part of the snake overlaps
-- the player.
function LilSnake:touchesPlayer(player)
  local playerRadius = player.width * 0.3
  local headReach = self.width * 0.38 + playerRadius
  local offsetX, offsetY = player.x - self.x, player.y - self.y
  if offsetX * offsetX + offsetY * offsetY <= headReach * headReach then
    return 'head'
  end

  local bodyReach = 28 + playerRadius
  for index = 1, self.segmentCount do
    local segment = self:getSegmentPosition(index)
    local segmentX, segmentY = player.x - segment.x, player.y - segment.y
    if segmentX * segmentX + segmentY * segmentY <= bodyReach * bodyReach then
      return 'body'
    end
  end
  return nil
end

local function getBodyFrame(direction, frame)
  if direction == 'up' then
    return frame == 1 and LilSnake.frames.bodyUp or LilSnake.frames.bodyUpAlt
  elseif direction == 'down' then
    return frame == 1 and LilSnake.frames.bodyDown or LilSnake.frames.bodyDownAlt
  end
  return frame == 1 and LilSnake.frames.bodyRight or LilSnake.frames.bodyRightAlt
end

function LilSnake:draw(camera)
  if not self.alive then
    return
  end
  local shakeX, shakeY = 0, 0
  if self.deathSequence then
    shakeX = math.random(-4, 4)
    shakeY = math.random(-4, 4)
  end
  local animationFrame = self.animationFrame
  local frameName
  if self.facing == 'up' or self.facing == 'down' then
    frameName = animationFrame == 1 and 'headUp' or 'headUpFlick'
  else
    frameName = animationFrame == 1 and 'headRight' or 'headRightFlick'
  end

  local headScaleX = self.facing == 'left' and -2 or 2
  local headScaleY = self.facing == 'down' and -2 or 2
  love.graphics.setColor(1, 1, 1, 1)

  for index = self.segmentCount, 1, -1 do
    local segment = self:getSegmentPosition(index)
    local previous = self:getSegmentPosition(math.max(1, index - 1))
    local directionX = previous.x - segment.x
    local directionY = previous.y - segment.y
    local direction
    if math.abs(directionX) >= math.abs(directionY) then
      direction = directionX < 0 and 'left' or 'right'
    else
      direction = directionY < 0 and 'up' or 'down'
    end
    local body = getBodyFrame(direction, animationFrame)
    local bodyScaleX = direction == 'left' and -1.5 or 1.5
    love.graphics.draw(
      LilSnake.image,
      body.quad,
      math.floor(segment.x - camera.x + shakeX),
      math.floor(segment.y - camera.y + shakeY),
      0,
      bodyScaleX,
      1.5,
      24,
      24
    )
  end

  love.graphics.draw(
    LilSnake.image,
    LilSnake.frames[frameName].quad,
    math.floor(self.x - camera.x + shakeX),
    math.floor(self.y - camera.y + shakeY),
    0,
    headScaleX,
    headScaleY,
    24,
    24
  )

  love.graphics.setColor(1, 1, 1, 1)
end

return LilSnake