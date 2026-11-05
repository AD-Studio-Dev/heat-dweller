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

local function makeLayout(random, floorType)
  local pattern = random(1, 4)
  local walls
  if pattern == 1 then
    walls = {
      { x = random(320, 480), y = random(200, 280), width = 80, height = 240 },
      { x = random(1040, 1200), y = random(680, 760), width = 80, height = 240 },
    }
  elseif pattern == 2 then
    walls = {
      { x = random(560, 720), y = random(200, 280), width = 320, height = 80 },
      { x = random(560, 720), y = random(840, 920), width = 320, height = 80 },
    }
  elseif pattern == 3 then
    walls = {
      { x = random(640, 720), y = random(320, 400), width = 160, height = 400 },
    }
  else
    walls = {
      { x = random(360, 440), y = random(360, 440), width = 160, height = 160 },
      { x = random(1000, 1080), y = random(720, 800), width = 160, height = 160 },
    }
  end

  local layout = {
    floor = floorType,
    pattern = pattern,
    walls = walls,
    obstacles = {},
    decorations = {},
  }

  local function obstacle(x, y, width, height, style)
    local item = { x = x, y = y, width = width, height = height, style = style }
    layout.obstacles[#layout.obstacles + 1] = item
    layout.decorations[#layout.decorations + 1] = item
  end

  if floorType == 'living_room' then
    obstacle(270, 200, 240, 110, 'couch')
    obstacle(900, 650, 150, 110, 'table')
  elseif floorType == 'kitchen' then
    obstacle(240, 180, 280, 90, 'counter')
    obstacle(900, 680, 260, 90, 'cabinet')
  elseif floorType == 'bedroom' then
    obstacle(270, 170, 300, 150, 'bed')
    obstacle(900, 650, 170, 100, 'dresser')
  elseif floorType == 'attic' then
    obstacle(260, 210, 130, 270, 'crate')
    obstacle(930, 580, 130, 240, 'crate')
    layout.decorations[#layout.decorations + 1] = { type = 'cobweb', x = 70, y = 70 }
    layout.decorations[#layout.decorations + 1] = { type = 'cobweb', x = 1210, y = 70 }
    layout.decorations[#layout.decorations + 1] = { type = 'rafter', y = 150 }
    layout.decorations[#layout.decorations + 1] = { type = 'rafter', y = 810 }
  elseif floorType == 'roof' then
    layout.decorations[#layout.decorations + 1] = { type = 'roof_edge' }
  elseif floorType == 'sky' then
    obstacle(260, 250, 180, 34, 'cloud_platform')
    obstacle(830, 620, 210, 34, 'cloud_platform')
    layout.decorations[#layout.decorations + 1] = { type = 'cloud', x = 200, y = 600, scale = 1.4 }
    layout.decorations[#layout.decorations + 1] = { type = 'cloud', x = 1050, y = 300, scale = 1.8 }
  end

  if floorType == 'attic' then
    for _, wall in ipairs(layout.walls) do
      wall.width = math.max(64, math.floor(wall.width * 0.72))
      wall.height = math.max(64, math.floor(wall.height * 0.78))
    end
  end

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
    { 400, 330 }, { 640, 330 }, { 880, 330 },
    { 400, 600 }, { 640, 600 }, { 880, 600 },
    { 520, 470 }, { 760, 470 },
  }
  local free = {}
  for _, slot in ipairs(slots) do
    if not touchesRect(slot[1], slot[2], 90, layout and layout.walls)
        and not touchesRect(slot[1], slot[2], 90, layout and layout.obstacles) then
      free[#free + 1] = slot
    end
  end
  if #free == 0 then
    free[1] = { 160, 160 }
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

local function makeEnemies(random, floorType, layout)
  local enemyTypesByFloor = {
    basement = { 'scar', 'spider', 'fly', 'centipede' },
    living_room = { 'scar', 'spider', 'centipede' },
    kitchen = { 'scar', 'fly', 'centipede' },
    bedroom = { 'scar', 'spider', 'centipede' },
    attic = { 'spider', 'fly', 'centipede' },
    roof = { 'scar', 'fly', 'centipede' },
    sky = { 'stationaryangel' }, -- The Sky's only enemy; never listed on any other floor.
  }
  local enemyTypes = enemyTypesByFloor[floorType] or enemyTypesByFloor.basement

  if floorType == 'sky' then
    return makeSkyEnemies(random, layout)
  end
  local minimumCount = (floorType == 'sky' or floorType == 'roof') and 3 or 2
  local count = random(minimumCount, 4)
  local enemies = {}
  for _ = 1, count do
    local x = random(240, 1040)
    local y = random(220, 740)
    enemies[#enemies + 1] = {
      type = enemyTypes[random(1, #enemyTypes)],
      x = x,
      y = y,
    }
  end

  if floorType == 'living_room' and random() < 0.2 then
    return {
      { type = 'scar', x = 360, y = 300 },
      { type = 'spider', x = 920, y = 300 },
      { type = 'spider', x = 640, y = 720 },
    }
  end

  return enemies
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

  return rooms
end

return Rooms