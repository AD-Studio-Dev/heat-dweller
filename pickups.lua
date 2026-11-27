-- Consumable pickups (Dollars, Flames, Screwdrivers) and placed Flame bombs.
-- Kept out of main.lua, which is near the 200 top-level local limit.
local Pickups = {}

-- Tuning ---------------------------------------------------------------------
Pickups.ROOM_REWARD_CHANCE = 0.60 -- per cleared combat room
Pickups.ROOM_REWARD_WEIGHTS = { -- must add up to 1
  { kind = 'dollar', weight = 0.55 },
  { kind = 'flame', weight = 0.225 },
  { kind = 'screwdriver', weight = 0.225 },
}
-- Every Dollar pickup is worth $1. A Dollar drop is sometimes 2 or 3 of them.
Pickups.DOLLAR_CLUSTER_CHANCE = 0.40
Pickups.DOLLAR_CLUSTER_MIN, Pickups.DOLLAR_CLUSTER_MAX = 2, 3
-- Room-clear Dollars per floor. The minimum is reached by forcing Dollar drops in
-- the last few uncleared combat rooms, so it needs the whole floor to be cleared.
Pickups.FLOOR_DOLLAR_MIN, Pickups.FLOOR_DOLLAR_MAX = 6, 10
Pickups.SHOP_STOCK = {
  { kind = 'flame', price = 3 },
  { kind = 'screwdriver', price = 3 },
}
Pickups.SHOP_BUY_RANGE = 60
Pickups.MAX_COUNT = 99

Pickups.FUSE = 1.5            -- seconds from placing to detonation
Pickups.PLACE_COOLDOWN = 0.35
Pickups.BLAST_RADIUS = 112    -- enemies (plus their own size) and Matthew
Pickups.BREAK_RADIUS = 96     -- box tiles this close are destroyed
Pickups.BLAST_DAMAGE = 40
Pickups.SELF_DAMAGE = 20      -- one heart; 0 makes Flames harmless to Matthew
local BLAST_SECONDS = 0.35
local TILE = 64

local STAT_KEYS = { dollar = 'dollars', flame = 'flames', screwdriver = 'screwdrivers' }
local LABELS = { dollar = 'DOLLAR', flame = 'FLAME', screwdriver = 'SCREWDRIVER' }

function Pickups.label(kind)
  return LABELS[kind] or kind
end

-- Adds one consumable. Returns false for a kind that isn't a consumable.
function Pickups.give(stats, kind)
  local key = STAT_KEYS[kind]
  if not key then
    return false
  end
  stats[key] = math.min(Pickups.MAX_COUNT, (stats[key] or 0) + 1)
  return true
end

-- Runs saved before Screwdrivers existed stored them as `keys`.
function Pickups.migrateStats(stats)
  if stats.keys then
    stats.screwdrivers = math.min(Pickups.MAX_COUNT, (stats.screwdrivers or 0) + stats.keys)
    stats.keys = nil
  end
end

local function rollKind(random)
  local roll, total = random(), 0
  for _, entry in ipairs(Pickups.ROOM_REWARD_WEIGHTS) do
    total = total + entry.weight
    if roll < total then
      return entry.kind
    end
  end
  return Pickups.ROOM_REWARD_WEIGHTS[#Pickups.ROOM_REWARD_WEIGHTS].kind
end

-- The reward for clearing `room` (already marked cleared): returns kind, count, or nil
-- for no drop. `rooms` is the whole floor; each room remembers the Dollars it dropped
-- in `rewardDollars`, which is saved with the run. `random` defaults to math.random.
function Pickups.planRoomReward(rooms, room, random)
  random = random or math.random
  local dropped, roomsLeft = 0, 0
  for _, other in ipairs(rooms) do
    dropped = dropped + (other.rewardDollars or 0)
    if other.roomType == 'combat' and not other.cleared then
      roomsLeft = roomsLeft + 1
    end
  end

  local kind, count = nil, 0
  if random() < Pickups.ROOM_REWARD_CHANCE then
    kind, count = rollKind(random), 1
    if kind == 'dollar' and random() < Pickups.DOLLAR_CLUSTER_CHANCE then
      count = random(Pickups.DOLLAR_CLUSTER_MIN, Pickups.DOLLAR_CLUSTER_MAX)
    end
  end

  -- Dollars this room must give so the rooms still left (counted at $2 each) can
  -- cover the rest of the floor minimum.
  local owed = math.min(Pickups.DOLLAR_CLUSTER_MAX,
    Pickups.FLOOR_DOLLAR_MIN - dropped - roomsLeft * 2)
  if owed > 0 and (kind ~= 'dollar' or count < owed) then
    kind, count = 'dollar', owed
  end

  if kind == 'dollar' then
    local allowed = Pickups.FLOOR_DOLLAR_MAX - dropped
    if allowed <= 0 then -- floor is at its Dollar limit: drop something else
      return random() < 0.5 and 'flame' or 'screwdriver', 1
    end
    count = math.min(count, allowed)
    room.rewardDollars = count
  end
  if not kind then
    return nil
  end
  return kind, count
end

local function circleTouchesRect(x, y, radius, rx, ry, width, height)
  local closestX = math.max(rx, math.min(x, rx + width))
  local closestY = math.max(ry, math.min(y, ry + height))
  local dx, dy = x - closestX, y - closestY
  return dx * dx + dy * dy < radius * radius
end

-- The free spot closest to (x, y), so a reward never lands inside a box or furniture.
function Pickups.findOpenSpot(x, y, solids)
  for ring = 0, 5 do
    for step = 0, (ring == 0 and 0 or 7) do
      local angle = step * math.pi / 4
      local spotX = x + math.cos(angle) * ring * TILE
      local spotY = y + math.sin(angle) * ring * TILE
      local blocked = false
      for _, rect in ipairs(solids or {}) do
        if circleTouchesRect(spotX, spotY, 24, rect.x, rect.y, rect.width, rect.height) then
          blocked = true
          break
        end
      end
      if not blocked then
        return spotX, spotY
      end
    end
  end
  return x, y
end

-- Shop stock lives on the room table, so it is saved with the run.
function Pickups.makeShopStock(centerX, y)
  local stock = {}
  local spacing = 180
  local left = centerX - spacing * (#Pickups.SHOP_STOCK - 1) / 2
  for index, entry in ipairs(Pickups.SHOP_STOCK) do
    stock[index] = {
      kind = entry.kind,
      price = entry.price,
      x = left + (index - 1) * spacing,
      y = y,
      purchased = false,
    }
  end
  return stock
end

function Pickups.stockInRange(stock, x, y)
  for _, entry in ipairs(stock or {}) do
    local dx, dy = x - entry.x, y - entry.y
    if not entry.purchased and dx * dx + dy * dy <= Pickups.SHOP_BUY_RANGE ^ 2 then
      return entry
    end
  end
  return nil
end

-- Destroys every box tile within `radius`. A damaged block is replaced in place by
-- 1x1 rectangles for its surviving tiles, so collision and drawing stay in step.
-- Furniture (layout.obstacles) is never passed in and never breaks.
function Pickups.breakBoxes(walls, x, y, radius)
  local broken = {}
  for index = #(walls or {}), 1, -1 do
    local wall = walls[index]
    local columns = math.max(1, math.floor(wall.width / TILE + 0.5))
    local rows = math.max(1, math.floor(wall.height / TILE + 0.5))
    local cellWidth, cellHeight = wall.width / columns, wall.height / rows
    local survivors, hit = {}, false
    for column = 0, columns - 1 do
      for row = 0, rows - 1 do
        local cellX, cellY = wall.x + column * cellWidth, wall.y + row * cellHeight
        if circleTouchesRect(x, y, radius, cellX, cellY, cellWidth, cellHeight) then
          hit = true
          broken[#broken + 1] = { x = cellX + cellWidth / 2, y = cellY + cellHeight / 2 }
        else
          survivors[#survivors + 1] = {
            x = cellX, y = cellY, width = cellWidth, height = cellHeight, solid = wall.solid,
          }
        end
      end
    end
    if hit then
      table.remove(walls, index)
      for _, survivor in ipairs(survivors) do
        walls[#walls + 1] = survivor
      end
    end
  end
  return broken
end

-- Placed Flames ---------------------------------------------------------------
local Bombs = {}
Bombs.__index = Bombs

function Pickups.newBombs()
  return setmetatable({ placed = {}, blasts = {}, cooldown = 0 }, Bombs)
end

function Bombs:clear()
  self.placed, self.blasts, self.cooldown = {}, {}, 0
end

-- Drops a lit Flame where Matthew stands and spends one from his count.
function Bombs:place(player)
  local stats = player.stats
  if self.cooldown > 0 or stats.health <= 0 or (stats.flames or 0) <= 0 then
    return false
  end
  stats.flames = stats.flames - 1
  self.cooldown = Pickups.PLACE_COOLDOWN
  self.placed[#self.placed + 1] = { x = player.x, y = player.y, fuse = Pickups.FUSE }
  return true
end

local function targetReach(target)
  if target.radius then
    return target.radius
  end
  if target.width and target.height then
    return math.min(target.width, target.height) / 2
  end
  return 24
end

-- context = { player, walls, targets = function() -> list, damage = function(target, amount),
--             onExplode = function() (optional) }
function Bombs:explode(bomb, context)
  local radius = Pickups.BLAST_RADIUS
  for _, target in ipairs(context.targets()) do
    local dx, dy = target.x - bomb.x, target.y - bomb.y
    local reach = radius + targetReach(target)
    if dx * dx + dy * dy <= reach * reach then
      context.damage(target, Pickups.BLAST_DAMAGE)
    end
  end

  local player = context.player
  local dx, dy = player.x - bomb.x, player.y - bomb.y
  if Pickups.SELF_DAMAGE > 0 and dx * dx + dy * dy <= radius * radius then
    player:takeDamage(Pickups.SELF_DAMAGE)
  end

  local debris = Pickups.breakBoxes(context.walls, bomb.x, bomb.y, Pickups.BREAK_RADIUS)
  -- Other lit Flames caught in the blast go off almost at once.
  for _, other in ipairs(self.placed) do
    local ox, oy = other.x - bomb.x, other.y - bomb.y
    if ox * ox + oy * oy <= radius * radius then
      other.fuse = math.min(other.fuse, 0.1)
    end
  end

  self.blasts[#self.blasts + 1] = { x = bomb.x, y = bomb.y, age = 0, debris = debris }
  if context.onExplode then
    context.onExplode()
  end
end

function Bombs:update(dt, context)
  self.cooldown = math.max(0, self.cooldown - dt)
  for index = #self.blasts, 1, -1 do
    local blast = self.blasts[index]
    blast.age = blast.age + dt
    if blast.age >= BLAST_SECONDS then
      table.remove(self.blasts, index)
    end
  end
  local due = {}
  for index = #self.placed, 1, -1 do
    local bomb = self.placed[index]
    bomb.fuse = bomb.fuse - dt
    if bomb.fuse <= 0 then
      due[#due + 1] = table.remove(self.placed, index)
    end
  end
  for _, bomb in ipairs(due) do
    self:explode(bomb, context)
  end
end

function Bombs:draw(camera, renderer)
  for _, bomb in ipairs(self.placed) do
    local x, y = math.floor(bomb.x - camera.x), math.floor(bomb.y - camera.y)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse('fill', x, y + 16, 14, 5)
    -- Blinks faster as the fuse runs down.
    local burned = Pickups.FUSE - math.max(0, bomb.fuse)
    local flash = math.floor(burned * (5 + burned * 8)) % 2 == 1
    renderer:drawPickupIcon('flame', x, y, 1, flash and { 1, 0.45, 0.45 } or nil)
  end
  for _, blast in ipairs(self.blasts) do
    local progress = blast.age / BLAST_SECONDS
    local x, y = math.floor(blast.x - camera.x), math.floor(blast.y - camera.y)
    local radius = Pickups.BLAST_RADIUS * (0.45 + 0.55 * progress)
    love.graphics.setColor(0.95, 0.35, 0.08, 0.65 * (1 - progress))
    love.graphics.circle('fill', x, y, radius)
    love.graphics.setColor(1, 0.85, 0.3, 0.9 * (1 - progress))
    love.graphics.circle('fill', x, y, radius * 0.55)
    love.graphics.setColor(0.45, 0.28, 0.14, 1 - progress)
    for _, piece in ipairs(blast.debris) do
      for shard = 0, 3 do
        local angle = shard * math.pi / 2 + math.pi / 4
        love.graphics.rectangle('fill',
          piece.x - camera.x + math.cos(angle) * progress * 40 - 5,
          piece.y - camera.y + math.sin(angle) * progress * 40 - 5, 10, 10)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Pickups