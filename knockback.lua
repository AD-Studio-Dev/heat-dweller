-- Knockback for regular enemies hit by Matthew's sweat projectiles.
--
-- A hit adds a velocity impulse to the enemy. Update() slides the enemy along
-- that velocity and decays it, independently of the enemy's own AI, so scar
-- dashes, fly drifting and centipede chasing keep working untouched.
--
-- Size scaling: the impulse is multiplied by (REFERENCE_SIZE / size) ^ SIZE_EXPONENT,
-- clamped to [MIN_FACTOR, MAX_FACTOR], where size = max(width, height). Linear:
--   half-size centipede (28 px) -> x1.80 (clamped)   farthest
--   fly (40 px)                 -> x1.60
--   centipede (56 px)           -> x1.14
--   scar / spider (64 px)       -> x1.00             reference
--   a 128 px enemy              -> x0.50             resists
-- Only the kinds listed below can be knocked back: the stationary angel and the
-- bosses are scripted and are deliberately left alone.
local Knockback = {}

local REFERENCE_SIZE = 64
local SIZE_EXPONENT = 1.0
local MIN_FACTOR, MAX_FACTOR = 0.15, 1.8
local BASE_IMPULSE = 180   -- px/s given to a 64 px enemy (about 15 px of travel)
local DECAY = 12           -- per second; high = the shove snaps to a stop quickly
local MAX_SPEED = 320      -- stacked hits can never launch an enemy faster than this
local STACK_FRACTION = 0.4  -- a hit landing while already knocked back adds only this much
local STOP_SPEED = 5

Knockback.KINDS = { scar = true, spider = true, fly = true, centipede = true }

local function enemySize(enemy)
  return math.max(enemy.width or REFERENCE_SIZE, enemy.height or REFERENCE_SIZE)
end

-- Multiplier applied to the base impulse for an enemy of this size.
function Knockback.getSizeFactor(enemy)
  local factor = (REFERENCE_SIZE / enemySize(enemy)) ^ SIZE_EXPONENT
  return math.max(MIN_FACTOR, math.min(MAX_FACTOR, factor))
end

-- directionX/Y: direction of travel of whatever hit the enemy (need not be normalised).
function Knockback.apply(enemy, directionX, directionY, strength)
  if not enemy or not enemy.alive or not Knockback.KINDS[enemy.kind] then
    return false
  end
  local length = math.sqrt(directionX * directionX + directionY * directionY)
  if length == 0 then
    return false
  end

  local impulse = (strength or BASE_IMPULSE) * Knockback.getSizeFactor(enemy)
  -- Diminishing returns: while the enemy is still sliding, follow-up hits only
  -- add a fraction, so holding the fire button cannot build up a pin.
  local alreadyMoving = enemy.knockbackVX ~= nil or enemy.knockbackVY ~= nil
  if alreadyMoving then
    impulse = impulse * STACK_FRACTION
  end
  local velocityX = (enemy.knockbackVX or 0) + directionX / length * impulse
  local velocityY = (enemy.knockbackVY or 0) + directionY / length * impulse
  local speed = math.sqrt(velocityX * velocityX + velocityY * velocityY)
  if speed > MAX_SPEED then
    velocityX, velocityY = velocityX * MAX_SPEED / speed, velocityY * MAX_SPEED / speed
  end
  enemy.knockbackVX, enemy.knockbackVY = velocityX, velocityY
  return true
end

-- Call once per frame after the enemy's own update.
function Knockback.update(enemy, dt, world)
  local velocityX, velocityY = enemy.knockbackVX, enemy.knockbackVY
  if not velocityX or not enemy.alive then
    return
  end

  -- Keep the enemy inside the room (the inner face of the wall frame).
  local wall = world.wall or 0
  local halfWidth, halfHeight = (enemy.width or 0) / 2, (enemy.height or 0) / 2
  enemy.x = math.max(halfWidth + wall, math.min(world.width - halfWidth - wall, enemy.x + velocityX * dt))
  enemy.y = math.max(halfHeight + wall, math.min(world.height - halfHeight - wall, enemy.y + velocityY * dt))

  local damping = math.exp(-DECAY * dt)
  velocityX, velocityY = velocityX * damping, velocityY * damping
  if velocityX * velocityX + velocityY * velocityY < STOP_SPEED * STOP_SPEED then
    enemy.knockbackVX, enemy.knockbackVY = nil, nil
  else
    enemy.knockbackVX, enemy.knockbackVY = velocityX, velocityY
  end
end

return Knockback