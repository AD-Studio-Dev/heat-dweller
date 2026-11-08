-- Room transition controller (Binding of Isaac style).
--
-- Two phases, driven by update(dt):
--   'slide' - the camera pans from the old room to the new one with an ease in/out
--             (SLIDE_DURATION seconds). The old and new rooms are drawn side by side.
--   'grace' - the new room sits frozen for GRACE_DURATION seconds (0.4 s) before play
--             resumes. Nothing is updated during this window: no player input, no
--             enemy AI or attacks, no projectiles.
--
-- This module only keeps time and does the maths. main.lua owns the game state: it
-- sets gameState = 'room_transition' while this is active, skips every gameplay update,
-- and switches to transition.nextState when update() reports that it has finished.
local RoomTransition = {}
RoomTransition.__index = RoomTransition

RoomTransition.SLIDE_DURATION = 0.3
RoomTransition.GRACE_DURATION = 0.05

-- Unit vector the camera travels in when leaving through a given door.
local TRAVEL = {
  right = { 1, 0 },
  left = { -1, 0 },
  down = { 0, 1 },
  up = { 0, -1 },
}

local function easeInOutCubic(t)
  if t < 0.5 then
    return 4 * t * t * t
  end
  local u = -2 * t + 2
  return 1 - u * u * u / 2
end

local function round(value)
  return math.floor(value + 0.5)
end

function RoomTransition.new()
  return setmetatable({
    active = false,
    phase = 'idle', -- 'idle' | 'slide' | 'grace'
    timer = 0,
    direction = 'right',
    nextState = 'playing', -- gameState to switch to when the grace period ends
  }, RoomTransition)
end

-- direction: the door that was used ('up', 'down', 'left', 'right').
-- nextState: what gameState to enter afterwards ('playing', or 'boss_intro').
function RoomTransition:start(direction, nextState)
  self.active = true
  self.phase = 'slide'
  self.timer = 0
  self.direction = TRAVEL[direction] and direction or 'right'
  self.nextState = nextState or 'playing'
end

-- Advances the transition. Returns true on the frame it finishes (and also when
-- called while nothing is running, so callers can never get stuck).
function RoomTransition:update(dt)
  if not self.active then
    return true
  end

  self.timer = self.timer + dt
  if self.phase == 'slide' and self.timer >= RoomTransition.SLIDE_DURATION then
    self.phase = 'grace'
    self.timer = 0 -- the grace window is always a full GRACE_DURATION
  end
  if self.phase == 'grace' and self.timer >= RoomTransition.GRACE_DURATION then
    self.active = false
    self.phase = 'idle'
    self.timer = 0
    return true
  end
  return false
end

function RoomTransition:isSliding()
  return self.active and self.phase == 'slide'
end

function RoomTransition:isGrace()
  return self.active and self.phase == 'grace'
end

-- Eased slide progress, 0 at the start and 1 once the camera has arrived.
function RoomTransition:getProgress()
  if self.phase == 'slide' then
    return easeInOutCubic(math.min(1, self.timer / RoomTransition.SLIDE_DURATION))
  end
  return 1
end

-- Where to draw the old and the new room (whole pixels, so the pixel grid holds).
-- width/height is the size of one room view. Returns oldX, oldY, newX, newY.
function RoomTransition:getOffsets(width, height)
  local travel = TRAVEL[self.direction]
  local progress = self:getProgress()
  return round(-travel[1] * progress * width),
    round(-travel[2] * progress * height),
    round(travel[1] * (1 - progress) * width),
    round(travel[2] * (1 - progress) * height)
end

return RoomTransition