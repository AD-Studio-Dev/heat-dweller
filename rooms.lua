-- Procedural room graphs for the supported run floors.
local Rooms = {}

Rooms.floorTypes = {
  'basement',
  'living_room',
  'kitchen',
  'bedroom',
  'attic',
  'roof',
  'sky',
}

local floorNames = {
  basement = 'Basement',
  living_room = 'Living Room',
  kitchen = 'Kitchen',
  bedroom = 'Bedroom',
  attic = 'Attic',
  roof = 'Roof',
  sky = 'The Sky',
}

-- Wall palettes for the stone frame drawn around every room (renderer.lua,
-- Renderer:drawRoomFrame). `face` is the brick colour, `mortar` the joints and
-- depth shading, `cap` the lit top surface of the wall (derived from `face`
-- when omitted) and `glow` an optional pulsing overlay {r, g, b, a}.
-- Add an entry here when a new floor type is added; unknown floors fall back
-- to the basement look. `cellar` and `burning_basement` are ready for when
-- those floors exist.
Rooms.wallThemes = {
  basement = { face = { 0.31, 0.32, 0.33 }, mortar = { 0.08, 0.085, 0.09 } },
  cellar = { face = { 0.24, 0.28, 0.35 }, mortar = { 0.06, 0.075, 0.1 } },
  burning_basement = {
    face = { 0.46, 0.2, 0.12 }, mortar = { 0.14, 0.04, 0.03 }, glow = { 1, 0.4, 0.08, 0.2 },
  },
  living_room = { face = { 0.46, 0.24, 0.2 }, mortar = { 0.14, 0.07, 0.06 } },
  kitchen = { face = { 0.5, 0.55, 0.46 }, mortar = { 0.22, 0.25, 0.2 } },
  bedroom = { face = { 0.42, 0.3, 0.5 }, mortar = { 0.14, 0.09, 0.18 } },
  attic = { face = { 0.45, 0.33, 0.2 }, mortar = { 0.16, 0.1, 0.06 } },
  roof = { face = { 0.27, 0.36, 0.47 }, mortar = { 0.08, 0.11, 0.15 } },
  sky = { face = { 0.75, 0.87, 0.96 }, mortar = { 0.5, 0.64, 0.76 }, glow = { 1, 1, 1, 0.07 } },
}

-- Special rooms recolour their floor's walls (multiplied per channel).
local roomWallTints = {
  shop = { 1.25, 0.95, 0.55 },
  deal = { 0.95, 0.5, 1.0 },
}

local wallThemeCache = {}

-- Returns { face, mortar, cap, glow } for a floor type, optionally tinted for
-- a special room type ('shop', 'deal'). Results are cached; don't modify them.
function Rooms.getWallTheme(floorType, roomType)
  local key = tostring(floorType) .. '|' .. tostring(roomType)
  local cached = wallThemeCache[key]
  if cached then
    return cached
  end

  local base = Rooms.wallThemes[floorType] or Rooms.wallThemes.basement
  local tint = roomWallTints[roomType] or { 1, 1, 1 }
  local function tinted(color)
    return {
      math.min(1, color[1] * tint[1]),
      math.min(1, color[2] * tint[2]),
      math.min(1, color[3] * tint[3]),
    }
  end
  local face = tinted(base.face)
  local theme = {
    face = face,
    mortar = tinted(base.mortar),
    cap = base.cap and tinted(base.cap)
      or { math.min(1, face[1] * 1.3 + 0.03), math.min(1, face[2] * 1.3 + 0.03), math.min(1, face[3] * 1.3 + 0.03) },
    glow = base.glow,
  }
  wallThemeCache[key] = theme
  return theme
end

local directions = {
  { name = 'up', dx = 0, dy = -1, opposite = 'down' },
  { name = 'down', dx = 0, dy = 1, opposite = 'up' },
  { name = 'left', dx = -1, dy = 0, opposite = 'right' },
  { name = 'right', dx = 1, dy = 0, opposite = 'left' },
}

local function roomKey(x, y)
  return string.format('%d:%d', x, y)
end

local function makeRandom(seed)
  local state = math.floor(seed) % 2147483647
  if state <= 0 then
    state = state + 2147483646
  end
  return function(minimum, maximum)
    state = state * 48271 % 2147483647
    if minimum then
      return minimum + state % (maximum - minimum + 1)
    end
    return state / 2147483647
  end
end

-- Every room is a 21 x 11 tile grid (1344 x 704 px, 64 px tiles).
-- The outer ring of tiles is the stone wall frame (see renderer.lua).
-- Walls/obstacles stay inside the playable interior (tile columns 1-19, rows 1-9),
-- off the center lane the player spawns in, and clear of all four doorways.
local TILE = 64
Rooms.TILE, Rooms.WIDTH, Rooms.HEIGHT = TILE, 21 * TILE, 11 * TILE

-- Box blocks are whole-tile rectangles: the collision box is exactly the area the
-- boxes are drawn over (main.lua draws one box per tile cell of this rectangle).
local function tileRect(col, row, cols, rows)
  return { x = col * TILE, y = row * TILE, width = cols * TILE, height = rows * TILE, solid = true }
end

local function overlaps(a, b, pad)
  return a.x < b.x + b.width + pad and b.x < a.x + a.width + pad
    and a.y < b.y + b.height + pad and b.y < a.y + a.height + pad
end

-- Density limits. None of this draws a random number, so seeded floors keep the same
-- room graph, enemy placement and layout rolls; only over-full layouts get trimmed.
local MAX_BEDS_PER_ROOM = 1
-- Most box tiles (1 tile = 64 x 64 px) one room may contain, by floor. A room is 19 x 9
-- walkable tiles, so boxes alone take at most about 5% of it (2% to 5%).
local MAX_BOX_TILES = { default = 8, living_room = 6, kitchen = 6, bedroom = 4 }
local BOSS_ROOM_MAX_BOX_TILES = 4 -- boss rooms: room to dodge and fight

local function boxTiles(rect)
  return (rect.width / TILE) * (rect.height / TILE)
end

-- Shrinks (then, only if a block is a single tile, drops) the biggest box blocks until
-- the room is within its tile budget. Shrinking cuts the longer side by one tile from
-- the far end, so blocks stay on the tile grid and inside the room.
local function limitBoxDensity(layout, floorType, maxTiles)
  maxTiles = maxTiles or MAX_BOX_TILES[floorType] or MAX_BOX_TILES.default
  local walls = layout.walls
  while true do
    local total, biggest, biggestIndex = 0, nil, nil
    for index, wall in ipairs(walls) do
      total = total + boxTiles(wall)
      if not biggest or boxTiles(wall) >= boxTiles(biggest) then
        biggest, biggestIndex = wall, index
      end
    end
    if total <= maxTiles or not biggest then
      return
    end
    if biggest.width > TILE and biggest.width > biggest.height then
      biggest.width = biggest.width - TILE
    elseif biggest.height > TILE then
      biggest.height = biggest.height - TILE
    elseif biggest.width > TILE then
      biggest.width = biggest.width - TILE
    else
      table.remove(walls, biggestIndex)
    end
  end
end

local function makeLayout(random, floorType)
  local pattern = random(1, 4)
  local walls
  if pattern == 1 then -- two 1x3 pillars
    walls = { tileRect(random(3, 7), random(1, 3), 1, 3), tileRect(random(13, 17), random(5, 7), 1, 3) }
  elseif pattern == 2 then -- two 5x1 bars, above and below the center lane
    walls = { tileRect(random(3, 13), 3, 5, 1), tileRect(random(3, 13), 7, 5, 1) }
  elseif pattern == 3 then -- one 2x4 block on the right
    walls = { tileRect(random(14, 16), random(2, 4), 2, 4) }
  else -- two 2x2 blocks
    walls = { tileRect(random(3, 7), random(2, 4), 2, 2), tileRect(random(13, 16), random(5, 7), 2, 2) }
  end

  local layout = {
    floor = floorType,
    pattern = pattern,
    walls = walls,
    obstacles = {},
    decorations = {},
  }

  local bedCount = 0
  local function obstacle(x, y, width, height, style)
    if style == 'bed' then -- never more than MAX_BEDS_PER_ROOM beds in one room
      if bedCount >= MAX_BEDS_PER_ROOM then
        return
      end
      bedCount = bedCount + 1
    end
    -- Furniture (bed, couch, ...) is solid over its whole drawn rectangle: the bed's
    -- 256 x 128 px (4 x 2 tiles) frame and mattress included.
    local item = { x = x, y = y, width = width, height = height, style = style, solid = true }
    layout.obstacles[#layout.obstacles + 1] = item
    layout.decorations[#layout.decorations + 1] = item
  end

  if floorType == 'living_room' then
    obstacle(160, 160, 240, 96, 'couch')
    obstacle(960, 448, 128, 96, 'table')
  elseif floorType == 'kitchen' then
    obstacle(160, 160, 256, 80, 'counter')
    obstacle(896, 512, 256, 80, 'cabinet')
  elseif floorType == 'bedroom' then
    obstacle(160, 160, 256, 128, 'bed')
    obstacle(960, 512, 128, 80, 'dresser')
  elseif floorType == 'attic' then
    obstacle(160, 128, 96, 128, 'crate')
    obstacle(960, 448, 96, 160, 'crate')
    layout.decorations[#layout.decorations + 1] = { type = 'cobweb', x = 70, y = 70 }
    layout.decorations[#layout.decorations + 1] = { type = 'cobweb', x = Rooms.WIDTH - 70, y = 70 }
    layout.decorations[#layout.decorations + 1] = { type = 'rafter', y = 110 }
    layout.decorations[#layout.decorations + 1] = { type = 'rafter', y = Rooms.HEIGHT - 110 }
  elseif floorType == 'roof' then
    layout.decorations[#layout.decorations + 1] = { type = 'roof_edge' }
  elseif floorType == 'sky' then
    obstacle(96, 100, 160, 34, 'cloud_platform')
    obstacle(1040, 560, 180, 34, 'cloud_platform')
    layout.decorations[#layout.decorations + 1] = { type = 'cloud', x = 150, y = 520, scale = 1.4 }
    layout.decorations[#layout.decorations + 1] = { type = 'cloud', x = 1100, y = 200, scale = 1.8 }
  end

  if floorType == 'attic' then -- smaller blocks, still snapped to whole tiles
    for _, wall in ipairs(layout.walls) do
      wall.width = math.max(TILE, math.floor(wall.width * 0.72 / TILE + 0.5) * TILE)
      wall.height = math.max(TILE, math.floor(wall.height * 0.78 / TILE + 0.5) * TILE)
    end
  end

  -- Drop any wall that would sit on top of (or flush against) a furniture obstacle.
  for index = #layout.walls, 1, -1 do
    for _, item in ipairs(layout.obstacles) do
      if overlaps(layout.walls[index], item, 32) then
        table.remove(layout.walls, index)
        break
      end
    end
  end

  limitBoxDensity(layout, floorType)

  return layout
end

local MAX_ANGELS_PER_ROOM = 4 -- keep in sync with StationaryAngel.MAX_PER_ROOM

-- True when a circle of `clearance` px around (x, y) touches any rectangle.
local function touchesRect(x, y, clearance, rects)
  for _, rect in ipairs(rects or {}) do
    local closestX = math.max(rect.x, math.min(x, rect.x + rect.width))
    local closestY = math.max(rect.y, math.min(y, rect.y + rect.height))
    local offsetX, offsetY = x - closestX, y - closestY
    if offsetX * offsetX + offsetY * offsetY < clearance * clearance then
      return true
    end
  end
  return false
end

-- Stationary Angels never move, so they must not sit inside a wall or obstacle
-- (shots couldn't reach them and the room would never clear).
local function makeSkyEnemies(random, layout)
  local slots = {
    { 480, 224 }, { 672, 224 }, { 864, 224 },
    { 480, 480 }, { 672, 480 }, { 864, 480 },
    { 576, 352 }, { 768, 352 },
  }
  local free = {}
  for _, slot in ipairs(slots) do
    if not touchesRect(slot[1], slot[2], 90, layout and layout.walls)
        and not touchesRect(slot[1], slot[2], 90, layout and layout.obstacles) then
      free[#free + 1] = slot
    end
  end
  if #free == 0 then
    free[1] = { Rooms.WIDTH / 2, Rooms.HEIGHT / 2 }
  end

  -- Weighted toward fewer angels: 1 (33%), 2 (33%), 3 (17%), 4 (17%).
  local countChoices = { 1, 1, 2, 2, 3, 4 }
  local count = math.min(
    countChoices[random(1, #countChoices)], MAX_ANGELS_PER_ROOM, #free
  )

  local enemies = {}
  for index = 1, count do
    local slot = table.remove(free, random(1, #free))
    enemies[index] = {
      type = 'stationaryangel',
      x = slot[1],
      y = slot[2],
      startDelay = (index - 1) * 1.0, -- staggers the angels' first bursts
    }
  end
  return enemies
end

-- Ground enemies spawn on tile centers in the middle of the room (tile columns
-- 3-17, rows 3-7 = x 224-1120, y 224-480): inside the 960x640 room, away from the
-- doorways the player arrives through, and not on any wall or obstacle.
local function randomSpawn(random, layout)
  local x, y
  for _ = 1, 12 do
    x = random(3, 17) * TILE + TILE / 2
    y = random(3, 7) * TILE + TILE / 2
    if not touchesRect(x, y, 48, layout.walls) and not touchesRect(x, y, 48, layout.obstacles) then
      break
    end
  end
  return x, y
end

local function makeEnemies(random, floorType, layout)
  local enemyTypesByFloor = {
    basement = { 'scar', 'spider', 'fly', 'centipede', 'breathless', 'panicker', 'puffer', 'aimless', 'linked' },
    living_room = { 'scar', 'spider', 'centipede', 'breathless', 'panicker', 'puffer', 'aimless', 'linked' },
    kitchen = { 'scar', 'fly', 'centipede', 'breathless', 'panicker', 'puffer', 'aimless', 'linked' },
    bedroom = { 'scar', 'spider', 'centipede', 'breathless', 'panicker', 'puffer', 'aimless', 'linked' },
    attic = { 'spider', 'fly', 'centipede', 'breathless', 'panicker', 'puffer', 'aimless', 'linked' },
    roof = { 'scar', 'fly', 'centipede', 'breathless', 'panicker', 'puffer', 'aimless', 'linked' },
    sky = { 'stationaryangel' }, -- The Sky's only enemy; never listed on any other floor.
  }
  local enemyTypes = enemyTypesByFloor[floorType] or enemyTypesByFloor.basement

  if floorType == 'sky' then
    return makeSkyEnemies(random, layout)
  end
  local minimumCount = (floorType == 'sky' or floorType == 'roof') and 3 or 2
  local special = floorType == 'living_room' and random() < 0.2
  local fixedTypes = special and { 'scar', 'spider', 'spider' } or nil
  local count = fixedTypes and #fixedTypes or random(minimumCount, 4)
  local enemies = {}
  for index = 1, count do
    local x, y = randomSpawn(random, layout)
    enemies[index] = {
      type = fixedTypes and fixedTypes[index] or enemyTypes[random(1, #enemyTypes)],
      x = x,
      y = y,
    }
  end

  return enemies
end

-- Every rectangle in a layout that blocks movement: box blocks (layout.walls) plus
-- furniture (layout.obstacles). Collision is rectangle based, not a cell grid, because
-- furniture sits on pixel positions (the bed at x = 160 is not tile aligned); a cell flag
-- grid would mark partial tiles and over- or under-block it. This list is what the player
-- and enemies collide with. Projectiles keep their own rule and still use layout.walls.
function Rooms.solidRects(layout)
  local solids = {}
  for _, wall in ipairs(layout.walls or {}) do
    if wall.solid ~= false then
      solids[#solids + 1] = wall
    end
  end
  for _, item in ipairs(layout.obstacles or {}) do
    if item.solid ~= false then
      solids[#solids + 1] = item
    end
  end
  return solids
end

function Rooms.generate(maxRooms, floorType, seed, floorIndex)
  maxRooms = math.max(3, math.min(maxRooms or 15, 20))
  floorType = floorType or 'basement'
  assert(floorNames[floorType], 'Unsupported floor type: ' .. tostring(floorType))
  if floorIndex ~= nil then
    assert(Rooms.floorTypes[floorIndex] == floorType,
      'Floor index does not match floor type: ' .. tostring(floorIndex))
  end
  seed = seed or os.time()
  local random = makeRandom(seed)
  for _ = 1, 4 do random() end -- warm up the LCG so nearby seeds don't give similar floors
  local rooms = {}
  local occupied = {}
  local frontier = {}

  local start = {
    id = 1,
    name = floorNames[floorType] .. ' Entrance',
    roomType = 'start',
    gridX = 0,
    gridY = 0,
    connections = {},
    layout = makeLayout(random, floorType),
    enemies = {},
    explored = false,
    cleared = true,
  }
  rooms[1] = start
  occupied[roomKey(0, 0)] = 1

  for _, direction in ipairs(directions) do
    table.insert(frontier, { room = start, direction = direction })
  end

  while #rooms < maxRooms and #frontier > 0 do
    local frontierIndex = random(1, #frontier)
    local entry = table.remove(frontier, frontierIndex)
    local parent = entry.room
    local direction = entry.direction
    local gridX = parent.gridX + direction.dx
    local gridY = parent.gridY + direction.dy
    local key = roomKey(gridX, gridY)

    if not occupied[key] then
      -- Built first so enemy placement can avoid this room's walls and obstacles.
      -- (Same random-number order as before: layout, then enemies.)
      local layout = makeLayout(random, floorType)
      local room = {
        id = #rooms + 1,
        name = floorNames[floorType] .. ' Room ' .. (#rooms + 1),
        roomType = 'combat',
        gridX = gridX,
        gridY = gridY,
        connections = {},
        layout = layout,
        enemies = makeEnemies(random, floorType, layout),
        explored = false,
        cleared = false,
      }
      rooms[room.id] = room
      occupied[key] = room.id
      parent.connections[direction.name] = room.id
      room.connections[direction.opposite] = parent.id

      for _, nextDirection in ipairs(directions) do
        if nextDirection.name ~= direction.opposite then
          table.insert(frontier, { room = room, direction = nextDirection })
        end
      end
    end
  end

  -- TODO: Replace this furthest-node rule with authored boss/special-room placement.
  local bossRoom = rooms[1]
  local furthestDistance = -1
  for _, room in ipairs(rooms) do
    local distance = math.abs(room.gridX) + math.abs(room.gridY)
    if distance > furthestDistance then
      bossRoom = room
      furthestDistance = distance
    end
  end

  local bossTypes
  if floorType == 'basement' or floorType == 'living_room' then
    bossTypes = { 'crawler', 'lilsnake' }
  elseif floorType == 'bedroom' then
    bossTypes = { 'stuffing' }
  else
    bossTypes = { 'geometric' }
  end
  bossRoom.bossType = bossTypes[random(1, #bossTypes)]
  limitBoxDensity(bossRoom.layout, floorType, BOSS_ROOM_MAX_BOX_TILES)
  bossRoom.roomType = 'boss'
  local bossNames = {
    crawler = 'Crawler Nest',
    lilsnake = "Lil' Snake Den",
    geometric = 'Geometric Core',
    stuffing = 'The Stuffing',
  }
  bossRoom.name = bossNames[bossRoom.bossType]
  bossRoom.boss = true
  bossRoom.enemies = { { type = bossRoom.bossType } }

  local shopCandidates = {}
  for _, room in ipairs(rooms) do
    if room ~= bossRoom and room.id ~= 1 then
      table.insert(shopCandidates, room)
    end
  end
  local shopRoom = shopCandidates[random(1, #shopCandidates)]
  shopRoom.shop = true
  shopRoom.roomType = 'shop'
  shopRoom.name = 'Shop'
  shopRoom.cleared = true
  shopRoom.enemies = {}

  local itemCandidates = {}
  for _, room in ipairs(rooms) do
    if room ~= bossRoom and room ~= shopRoom and room.id ~= 1 then
      itemCandidates[#itemCandidates + 1] = room
    end
  end
  if #itemCandidates > 0 then
    local itemRoom = itemCandidates[random(1, #itemCandidates)]
    itemRoom.itemRoom = true
    itemRoom.roomType = 'item'
    itemRoom.name = 'Forgotten Cache'
    itemRoom.cleared = true
    itemRoom.enemies = {}
  end

  local dealDirections = {
    { name = 'up', dx = 0, dy = -1, opposite = 'down' },
    { name = 'right', dx = 1, dy = 0, opposite = 'left' },
    { name = 'down', dx = 0, dy = 1, opposite = 'up' },
    { name = 'left', dx = -1, dy = 0, opposite = 'right' },
  }
  local dealDirection
  for _, direction in ipairs(dealDirections) do
    if not occupied[roomKey(bossRoom.gridX + direction.dx, bossRoom.gridY + direction.dy)] then
      dealDirection = direction
      break
    end
  end
  if dealDirection then
    local dealRoom = {
      id = #rooms + 1,
      name = 'Cultist Deal',
      roomType = 'deal',
      gridX = bossRoom.gridX + dealDirection.dx,
      gridY = bossRoom.gridY + dealDirection.dy,
      connections = { [dealDirection.opposite] = bossRoom.id },
      layout = makeLayout(random, floorType),
      enemies = {},
      explored = false,
      cleared = true,
      cultistDeal = true,
    }
    rooms[dealRoom.id] = dealRoom
    occupied[roomKey(dealRoom.gridX, dealRoom.gridY)] = dealRoom.id
    bossRoom.connections[dealDirection.name] = dealRoom.id
    bossRoom.dealDirection = dealDirection.name
    bossRoom.dealRoomId = dealRoom.id
  end

  for _, room in ipairs(rooms) do
    room.doors = {}
    for direction, connectedId in pairs(room.connections) do
      room.doors[direction] = { roomId = connectedId, locked = false }
    end
  end

  -- Each Shop / Item room gets exactly ONE special doorway: the one toward its
  -- lowest-numbered neighbour (closest to the start, i.e. the main path). Both
  -- sides of that doorway are tagged, so it looks special from outside and inside;
  -- every other doorway stays a normal door.
  for _, room in ipairs(rooms) do
    local kind = (room.roomType == 'shop' or room.roomType == 'item') and room.roomType or nil
    if kind then
      local bestDirection, bestId
      for direction, connectedId in pairs(room.connections) do
        if not bestId or connectedId < bestId then
          bestDirection, bestId = direction, connectedId
        end
      end
      if bestDirection then
        room.doors[bestDirection].kind = kind
        local neighbour = rooms[bestId]
        for direction, connectedId in pairs(neighbour.connections) do
          if connectedId == room.id then
            neighbour.doors[direction].kind = kind
          end
        end
      end
    end
  end

  return rooms
end

return Rooms