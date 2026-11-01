-- The Crawler follows the room perimeter and enters a repeating rush cycle.
local Crawler = {}
Crawler.__index = Crawler
local Wet = require('wet')

local function randomizedDuration(baseDuration)
  local shortestDuration = 0.25
  local maximumShortening = math.min(3, math.max(0, baseDuration - shortestDuration))
  return baseDuration + (math.random() * (maximumShortening + 3) - maximumShortening)
end

function Crawler.new(world)
  local margin = world.tileSize * 0.8
  local points = {
    { x = margin, y = margin },
    { x = world.width - margin, y = margin },
    { x = world.width - margin, y = world.height - margin },
    { x = margin, y = world.height - margin },
  }
  local perimeterLength = 0
  for index, point in ipairs(points) do
    local nextPoint = points[index % #points + 1]
    local distanceX = nextPoint.x - point.x
    local distanceY = nextPoint.y - point.y
    perimeterLength = perimeterLength + math.sqrt(distanceX * distanceX + distanceY * distanceY)
  end

  return setmetatable({
    points = points,
    pathIndex = 1,
    x = points[1].x,
    y = points[1].y,
    lastX = points[1].x,
    lastY = points[1].y,
    speed = 110,
    width = 96,
    height = 96,
    health = 320,
    maxHealth = 320,
    alive = true,
    animationTime = 0,
    babySpawnTimer = 0,
    babySpawned = false,
    phase = 1,
    phaseState = 'perimeter',
    phaseStateTimer = 0,
    perimeterLength = perimeterLength,
    rushBaseDuration = math.min(perimeterLength / 2400, 0.5),
    rushSpeed = perimeterLength / math.min(perimeterLength / 2400, 0.5),
    ragePauseBaseDuration = 1,
    chargeBaseDuration = 2,
    recoveryBaseDuration = 10,
    rushDistanceRemaining = 0,
  }, Crawler)
end

function Crawler:beginPhaseTwo()
  if not self.alive or self.phase >= 2 then
    return
  end

  self.phase = 2
  self.phaseState = 'rage_pause'
  self.phaseStateTimer = randomizedDuration(self.ragePauseBaseDuration)
end

function Crawler:moveAlongPerimeter(distance)
  local remaining = distance

  while remaining > 0 do
    local nextIndex = self.pathIndex % #self.points + 1
    local target = self.points[nextIndex]
    local distanceX = target.x - self.x
    local distanceY = target.y - self.y
    local segmentDistance = math.sqrt(distanceX * distanceX + distanceY * distanceY)

    if segmentDistance <= remaining then
      self.x = target.x
      self.y = target.y
      self.pathIndex = nextIndex
      remaining = remaining - segmentDistance
    else
      self.x = self.x + distanceX / segmentDistance * remaining
      self.y = self.y + distanceY / segmentDistance * remaining
      remaining = 0
    end
  end
end

function Crawler:update(dt)
  if not self.alive then
    return
  end
  local speedScale = Wet.update(self, dt)

  self.lastX, self.lastY = self.x, self.y
  self.animationTime = self.animationTime + dt
  self.babySpawnTimer = self.babySpawnTimer + dt
  local shouldSummonBaby = false
  if not self.babySpawned and self.babySpawnTimer >= 5 then
    self.babySpawned = true
    shouldSummonBaby = true
  end

  if self.phaseState == 'perimeter' then
    self:moveAlongPerimeter(self.speed * speedScale * dt)
  else
    local remainingTime = dt
    while remainingTime > 1e-9 do
      if self.phaseState == 'rage_pause' or self.phaseState == 'charging'
          or self.phaseState == 'exhausted' then
        local elapsed = math.min(remainingTime, self.phaseStateTimer)
        self.phaseStateTimer = self.phaseStateTimer - elapsed
        remainingTime = remainingTime - elapsed
        if self.phaseStateTimer <= 1e-9 then
          self.phaseStateTimer = 0
          if self.phaseState == 'rage_pause' then
            self.phaseState = 'charging'
            self.phaseStateTimer = randomizedDuration(self.chargeBaseDuration)
          elseif self.phaseState == 'charging' or self.phaseState == 'exhausted' then
            self.phaseState = 'wall_running'
            self.rushDistanceRemaining = self.perimeterLength
            local rushDuration = randomizedDuration(self.rushBaseDuration)
            self.rushSpeed = self.perimeterLength / rushDuration
          end
        else
          break
        end
      elseif self.phaseState == 'wall_running' then
        local distance = math.min(self.rushSpeed * speedScale * remainingTime, self.rushDistanceRemaining)
        local elapsed = distance / (self.rushSpeed * speedScale)
        self:moveAlongPerimeter(distance)
        self.rushDistanceRemaining = self.rushDistanceRemaining - distance
        remainingTime = remainingTime - elapsed
        if self.rushDistanceRemaining <= 1e-9 then
          self.rushDistanceRemaining = 0
          self.phaseState = 'exhausted'
          self.phaseStateTimer = randomizedDuration(self.recoveryBaseDuration)
        else
          break
        end
      else
        break
      end
    end
  end

  return shouldSummonBaby
end

function Crawler:getFrame()
  local frame = math.floor(self.animationTime / 0.1) % 2
  local nextIndex = self.pathIndex % #self.points + 1
  local target = self.points[nextIndex]
  if math.abs(target.y - self.y) > math.abs(target.x - self.x) then
    return 3 + frame
  end
  return 1 + frame
end

function Crawler:isInvulnerable()
  return self.phaseState == 'wall_running'
end

return Crawler