-- The Remote: a held, close-range "spirit sword" style weapon (item id 29).
--
-- While Matthew owns the Remote, his sweat shots are replaced by a quick melee
-- swing in the aimed direction. Every successful hit is counted; at 30 hits the
-- weapon becomes "empowered" (yellow tint and glow, drawn in renderer.lua) and
-- every hit after that has a 20% chance to zap the enemy, freezing it in place.
--
-- This module holds the state and the rules. main.lua wires it in:
--   * Player's onShootSweat calls Remote:swing()
--   * love.update calls Remote:update() with the room's targets
--   * enemies with zapTimer > 0 skip their update (frozen) in main.lua
--   * Renderer:drawRemote() draws the weapon in Matthew's hand
---@diagnostic disable: undefined-global
local Knockback = require('knockback')

local Remote = {}
Remote.__index = Remote

Remote.ITEM_ID = 29             -- id in resources/items.xml
Remote.COUCH_CHANCE = 0.5       -- chance a searched Living Room couch holds the Remote
Remote.SEARCH_DISTANCE = 80     -- px from the couch's edge the player can search from
Remote.EMPOWER_HITS = 30        -- hits needed to empower the weapon
Remote.ZAP_CHANCE = 0.2         -- per-hit chance to zap once empowered
Remote.ZAP_DURATION = 1.5       -- seconds a zapped enemy stays frozen
Remote.DAMAGE_MULTIPLIER = 1    -- times the player's damage per hit
Remote.REACH = 104              -- px from Matthew's centre the blade reaches
Remote.ARC_HALF = math.rad(65)  -- half-angle of the swing arc
Remote.SWING_DURATION = 0.16    -- seconds a swing stays active
Remote.KNOCKBACK_STRENGTH = 240 -- sweat shots use knockback.lua's default of 180, so this is ~33% harder

local DIRECTIONS = {
  left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 },
}

function Remote.new()
  local remote = setmetatable({}, Remote)
  remote:reset()
  return remote
end

-- New run: no hits, not empowered, nothing swinging.
function Remote:reset()
  self.hits = 0
  self.empowered = false
  self.swings = {}
end

-- Call after loading `hits` from a save.
function Remote:refreshEmpowered()
  self.empowered = self.hits >= self.EMPOWER_HITS
end

function Remote:clearSwings()
  self.swings = {}
end

function Remote:getActiveSwing()
  return self.swings[#self.swings]
end

-- Starts a swing. Direction can be numbers (x, y), a direction name, or a table.
-- Returns true when a swing started.
function Remote:swing(player, directionX, directionY)
  if type(directionX) == 'string' then
    local named = DIRECTIONS[directionX]
    if not named then
      return false
    end
    directionX, directionY = named[1], named[2]
  elseif type(directionX) == 'table' then
    local source = directionX
    directionX, directionY = source.x or source[1], source.y or source[2]
  end
  directionX, directionY = directionX or 0, directionY or 0
  local length = math.sqrt(directionX * directionX + directionY * directionY)
  if length == 0 then
    return false
  end

  -- No cooldown: every click / press starts a swing immediately.
  directionX, directionY = directionX / length, directionY / length
  self.swings[#self.swings + 1] = {
    dirX = directionX,
    dirY = directionY,
    elapsed = 0,
    duration = self.SWING_DURATION,
    hit = {}, -- each target is struck at most once per swing
  }
  return true
end

-- True when `target` is inside the swing's arc. Big targets count when they
-- overlap Matthew, and their size widens the arc so edges can be hit.
local function inSwing(self, swing, originX, originY, target)
  local dx, dy = target.x - originX, target.y - originY
  local distance = math.sqrt(dx * dx + dy * dy)
  local radius = math.max(target.width or 40, target.height or 40) / 2
  if distance <= radius + 24 then
    return true
  end
  if distance > self.REACH + radius then
    return false
  end
  local cosine = (dx * swing.dirX + dy * swing.dirY) / distance
  local half = self.ARC_HALF + math.asin(math.min(1, radius / distance))
  return cosine >= math.cos(half)
end

-- Same damage rules as sweat_projectile.lua. Returns true when the target died.
local function applyDamage(target, amount)
  local defeated
  if target.takeDamage then
    defeated = target:takeDamage(amount) and true or false
  else
    target.health = math.max(0, target.health - amount)
    if target.onDamaged then
      target.onDamaged()
    end
    if target.health == 0 then
      target.alive = false
      defeated = true
    end
  end
  if defeated and target.onDeath then
    target.onDeath()
  end
  return defeated
end

-- One successful hit: damage, count it, then (if already empowered) roll the zap.
function Remote:strike(target, swing, damage, zappable)
  local wasEmpowered = self.empowered -- the hit that empowers the Remote cannot zap
  local defeated = applyDamage(target, damage * self.DAMAGE_MULTIPLIER)

  self.hits = self.hits + 1
  if not self.empowered and self.hits >= self.EMPOWER_HITS then
    self.empowered = true
  end

  if defeated then
    return true
  end

  if wasEmpowered and zappable[target] and math.random() < self.ZAP_CHANCE then
    target.zapTimer = self.ZAP_DURATION -- main.lua freezes enemies while this is > 0
  end
  if (target.zapTimer or 0) <= 0 then
    Knockback.apply(target, swing.dirX, swing.dirY, self.KNOCKBACK_STRENGTH)
  end
  return false
end

-- Ages the active swings and applies their hits.
--   targets   every living thing a swing can hit
--   zappable  set { [enemy] = true } of regular enemies (bosses are never frozen)
--   damage    the player's current damage
-- Returns the list of targets this update defeated.
function Remote:update(dt, player, targets, zappable, damage)
  local defeated = {}
  local originX, originY = player.x, player.y - 8

  for index = #self.swings, 1, -1 do
    local swing = self.swings[index]
    swing.elapsed = swing.elapsed + dt
    for _, target in ipairs(targets) do
      if target.alive and not swing.hit[target]
          and inSwing(self, swing, originX, originY, target) then
        swing.hit[target] = true
        -- Shielded or otherwise invulnerable targets are not a successful hit.
        if not (target.isInvulnerable and target:isInvulnerable()) then
          if self:strike(target, swing, damage, zappable) then
            defeated[#defeated + 1] = target
          end
        end
      end
    end
    if swing.elapsed >= swing.duration then
      table.remove(self.swings, index)
    end
  end

  return defeated
end

-- Electric crackle over every zapped enemy. Draw after the enemies.
function Remote.drawZaps(enemies, camera)
  local time = love.timer.getTime()
  for _, enemy in ipairs(enemies or {}) do
    local timer = enemy.zapTimer or 0
    if timer > 0 and enemy.alive then
      local x = math.floor(enemy.x - camera.x)
      local y = math.floor(enemy.y - camera.y)
      local radius = math.max(enemy.width or 64, enemy.height or 64) / 2
      local fade = math.min(1, timer / 0.3) -- fades out over the last 0.3 s
      local flicker = 0.6 + 0.4 * math.sin(time * 40)

      love.graphics.setColor(1, 0.95, 0.4, 0.22 * fade * flicker)
      love.graphics.circle('fill', x, y, radius)

      love.graphics.setColor(1, 0.97, 0.6, 0.9 * fade)
      love.graphics.setLineWidth(2)
      for bolt = 1, 3 do
        local baseAngle = time * 6 + bolt * 2.1
        local previousX = x + math.cos(baseAngle) * radius * 0.2
        local previousY = y + math.sin(baseAngle) * radius * 0.2
        for segment = 1, 4 do
          local angle = baseAngle + (math.random() - 0.5) * 0.9
          local distance = radius * (0.2 + 0.25 * segment)
          local nextX = x + math.cos(angle) * distance
          local nextY = y + math.sin(angle) * distance
          love.graphics.line(previousX, previousY, nextX, nextY)
          previousX, previousY = nextX, nextY
        end
      end
      love.graphics.setLineWidth(1)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Remote