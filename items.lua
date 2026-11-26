-- Collectible item data, sprites, animation, and pickup handling.
---@diagnostic disable: undefined-global
local Items = {}
Items.__index = Items

local itemDataPath = 'resources/items.xml'
local activeActions = {
  playdough_platform = true,
  cake = true,
  molotov = true,
  charger = true,
  duality = true,
  snowman = true,
  cultist_oath = true,
  bread = true,
  mallet = true,
}
local statDisplay = {
  damage = { label = 'Damage', precision = 1 },
  speed = { label = 'Speed', precision = 1 },
  health = { label = 'Max Health', precision = 1 },
  luck = { label = 'Luck', precision = 1 },
  keys = { label = 'Keys', precision = 0 },
  fireRate = { label = 'Fire Rate', precision = 1 },
  size = { label = 'Size', precision = 1 },
}

local function decodeXml(value)
  local entities = {
    amp = '&',
    quot = '"',
    apos = "'",
    lt = '<',
    gt = '>',
  }
  return (value:gsub('&([%a]+);', function(entity)
    return entities[entity] or error('Unknown XML entity &' .. entity .. '; in ' .. itemDataPath)
  end))
end

local function parseItemDefinitions(xml)
  local definitions = {}
  local pools = {}
  local numericAttributes = {
    id = true,
    quality = true,
    shop_price = true,
    bob_speed = true,
    bob_height = true,
    damage = true,
    health = true,
    speed = true,
    luck = true,
    keys = true,
    firerate = true,
    sizeup = true,
    cooldown = true,
    timedcooldown = true,
  }
  local attributeNames = {
    shop_price = 'shopPrice',
    bob_speed = 'bobSpeed',
    bob_height = 'bobHeight',
    active_effect = 'activeEffect',
    active_action = 'activeAction',
    timedcooldown = 'timedCooldown',
  }
  local effectNames = {
    damage = 'damage',
    health = 'health',
    speed = 'speed',
    luck = 'luck',
    keys = 'keys',
    firerate = 'fireRate',
    sizeup = 'size',
  }

  for attributes in xml:gmatch('<item%s+(.-)/%s*>') do
    local item = { effects = {}, pools = {} }
    local foundAttributes = {}
    for key, value in attributes:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
      foundAttributes[key] = true
      value = decodeXml(value)
      if effectNames[key] then
        local amount = tonumber(value)
        if not amount then
          error('Invalid numeric item effect ' .. key .. ' for item ' .. tostring(item.id))
        end
        item.effects[effectNames[key]] = amount
      elseif key == 'itempool' then
        for pool in value:gmatch('[^,]+') do
          pool = pool:match('^%s*(.-)%s*$')
          if pool ~= '' then
            item.pools[pool] = true
            pools[pool] = pools[pool] or {}
          end
        end
      else
        local field = attributeNames[key] or key
        if numericAttributes[key] then
          item[field] = tonumber(value) or value
        else
          item[field] = value
        end
      end
    end

    if not foundAttributes.id or not foundAttributes.name or not foundAttributes.description
        or not foundAttributes.image or not foundAttributes.itempool then
      error('Item definition in ' .. itemDataPath
        .. ' must include id, name, description, image, and itempool attributes.')
    end
    if type(item.id) ~= 'number' or item.id % 1 ~= 0 then
      error('Item definition has an invalid numeric id in ' .. itemDataPath)
    end
    item.imagePath = item.image
    item.image = nil
    item.sprite = nil
    item.type = item.type and item.type:lower()
    item.quality = tonumber(item.quality) or item.quality
    if item.type == 'active' then
      if not item.activeAction or not item.activeEffect then
        error('Active item ' .. item.id .. ' must define active_action and active_effect.')
      end
      if not activeActions[item.activeAction] then
        error('Active item ' .. item.id .. ' has unknown action ' .. item.activeAction .. '.')
      end
      item.cooldown = item.cooldown or item.timedCooldown
      if type(item.cooldown) ~= 'number' or item.cooldown < 0 then
        error('Active item ' .. item.id .. ' must define a non-negative cooldown.')
      end
    end
    if next(item.effects) == nil then
      item.effects = nil
    end
    if definitions[item.id] then
      error('Duplicate item id ' .. item.id .. ' in ' .. itemDataPath)
    end
    definitions[item.id] = item
    for pool in pairs(item.pools) do
      pools[pool][#pools[pool] + 1] = item.id
    end
  end

  if not next(definitions) then
    error('No <item> definitions found in ' .. itemDataPath)
  end
  return definitions, pools
end

function Items.new()
  local self = setmetatable({
    active = {},
    inventory = {},
    definitions = {},
    pools = {},
    heldActive = nil,
    cooldownRemaining = 0,
    statNotifications = {},
  }, Items)
  self.notificationFont = love.graphics.newFont('resources/font/smallfont.ttf', 18)
  self.pickupSound = love.audio.newSource('resources/sfx/find_item.wav', 'static')

  local xml, readError = love.filesystem.read(itemDataPath)
  if not xml then
    error('Unable to read ' .. itemDataPath .. ': ' .. tostring(readError))
  end
  self.definitions, self.pools = parseItemDefinitions(xml)

  for _, definition in pairs(self.definitions) do
    if love.filesystem.getInfo(definition.imagePath) then
      definition.image = love.graphics.newImage(definition.imagePath)
      definition.image:setFilter('nearest', 'nearest')
      definition.sprite = definition.image
    else
      print('Item ' .. definition.id .. ' (' .. definition.name
        .. ') references missing sprite ' .. definition.imagePath)
    end
  end

  return self
end

function Items:spawn(itemId, x, y)
  local definition = self.definitions[itemId]
  if not definition then
    return false
  end
  if not definition.image then
    error('Cannot spawn item ' .. itemId .. ': missing sprite ' .. definition.imagePath)
  end

  table.insert(self.active, {
    definition = definition,
    x = x,
    baseY = y,
    timer = math.random() * 10,
  })
  return true
end

function Items:getPoolItem(pool)
  local poolItems = self.pools[pool] or {}
  local availableItems = {}
  for _, itemId in ipairs(poolItems) do
    if self.definitions[itemId].image then
      availableItems[#availableItems + 1] = itemId
    end
  end
  if #availableItems == 0 then
    error('No item definitions with loaded sprites are available in the "'
      .. tostring(pool) .. '" pool.')
  end
  local itemId = availableItems[math.random(#availableItems)]
  return self.definitions[itemId]
end

function Items:makeOffer(pool, x, y)
  local definition = self:getPoolItem(pool)
  return {
    definition = definition,
    x = x,
    baseY = y,
    timer = math.random() * 10,
    purchased = false,
  }
end

function Items:acquire(definition, player)
  assert(definition, 'Cannot acquire an undefined item.')
  local before = {}
  if player then
    for stat, display in pairs(statDisplay) do
      before[stat] = stat == 'speed' and player.speed
        or stat == 'health' and player.stats.maxHealth
        or player.stats[stat]
    end
  end
  self.inventory[definition.id] = (self.inventory[definition.id] or 0) + 1

  if definition.type == 'active' then
    assert(definition.image, 'Cannot equip active item without a loaded sprite: ' .. definition.name)
    assert(definition.activeAction, 'Active item is missing its behavior: ' .. definition.name)
    self.heldActive = definition
    self.cooldownRemaining = 0
  elseif player then
    player:applyItem(definition)
  end

  if player and definition.type == 'passive' then
    local changes = {}
    for stat, display in pairs(statDisplay) do
      local after = stat == 'speed' and player.speed
        or stat == 'health' and player.stats.maxHealth
        or player.stats[stat]
      local delta = after and before[stat] and after - before[stat] or 0
      if delta ~= 0 then
        changes[#changes + 1] = {
          label = display.label,
          text = string.format('%+.' .. display.precision .. 'f %s', delta, display.label),
          positive = delta > 0,
        }
      end
    end
    table.sort(changes, function(first, second)
      return first.label < second.label
    end)
    for index, change in ipairs(changes) do
      self.statNotifications[#self.statNotifications + 1] = {
        x = player.x,
        y = player.y - 32,
        text = change.text,
        positive = change.positive,
        timer = 1.1,
        delay = (index - 1) * 0.12,
      }
    end
  end

  if self.onAcquired then
    self.onAcquired(definition)
  end
end

function Items:rerollPassiveInventory(player, x, y)
  local passiveCounts = {}
  local passiveTotal = 0
  local candidates = {}
  for id, count in pairs(self.inventory) do
    local definition = self.definitions[id]
    if definition and definition.type == 'passive' and count > 0 then
      passiveCounts[id] = count
      passiveTotal = passiveTotal + count
    end
  end
  if passiveTotal == 0 then
    return self:spawnFloorReward(x, y)
  end

  for _, definition in pairs(self.definitions) do
    if definition.type == 'passive' and definition.image then
      candidates[#candidates + 1] = definition
    end
  end
  if #candidates == 0 then
    error('Duality cannot reroll passive items: no passive item sprites are available.')
  end

  local rerolledCounts = {}
  for oldId, count in pairs(passiveCounts) do
    local oldDefinition = self.definitions[oldId]
    local poolCandidates = {}
    for _, candidate in ipairs(candidates) do
      for pool in pairs(oldDefinition.pools) do
        if candidate.pools[pool] then
          poolCandidates[#poolCandidates + 1] = candidate
          break
        end
      end
    end
    if #poolCandidates == 0 then
      poolCandidates = candidates
    end
    for _ = 1, count do
      local definition = poolCandidates[math.random(#poolCandidates)]
      rerolledCounts[definition.id] = (rerolledCounts[definition.id] or 0) + 1
    end
  end
  for id in pairs(passiveCounts) do
    self.inventory[id] = nil
  end
  for id, count in pairs(rerolledCounts) do
    self.inventory[id] = (self.inventory[id] or 0) + count
  end

  local stats = player.stats
  local dollars = stats.dollars
  local health = stats.health
  stats.damage = 20
  stats.maxHealth = 60
  stats.health = math.min(health, stats.maxHealth)
  stats.luck = 0
  stats.keys = 0
  stats.fireRate = 0
  stats.size = 1
  stats.dollars = dollars
  player.speed = player.baseSpeed
  player.activeEffects = {}
  for id, count in pairs(self.inventory) do
    local definition = self.definitions[id]
    if definition and definition.type == 'passive' then
      for _ = 1, count do
        player:applyItem(definition)
      end
    end
  end
  return true
end

function Items:spawnFloorReward(x, y)
  local definition = self:getPoolItem('floor_reward')
  return self:spawn(definition.id, x, y)
end

function Items:update(dt, player, onPickup)
  self.cooldownRemaining = math.max(0, self.cooldownRemaining - dt)
  for index = #self.statNotifications, 1, -1 do
    local notification = self.statNotifications[index]
    notification.delay = math.max(0, notification.delay - dt)
    if notification.delay == 0 then
      notification.timer = notification.timer - dt
      if notification.timer <= 0 then
        table.remove(self.statNotifications, index)
      end
    end
  end
  for index = #self.active, 1, -1 do
    local item = self.active[index]
    item.timer = item.timer + dt

    local distanceX = player.x - item.x
    local distanceY = player.y - item.baseY
    local pickupDistance = math.max(player.width, player.height) / 2 + 20

    if distanceX * distanceX + distanceY * distanceY <= pickupDistance * pickupDistance then
      self:acquire(item.definition, player)
      if onPickup then
        onPickup(item.definition)
      end
      self.pickupSound:stop()
      self.pickupSound:play()
      table.remove(self.active, index)
    end
  end
end

function Items:drawStatNotifications(camera)
  local visibleIndex = 0
  for _, notification in ipairs(self.statNotifications) do
    if notification.delay == 0 then
      visibleIndex = visibleIndex + 1
      local progress = 1 - notification.timer / 1.1
      local alpha = math.min(1, progress / 0.18, notification.timer / 0.3)
      alpha = alpha * alpha * (3 - 2 * alpha)
      progress = progress * progress * (3 - 2 * progress)
      local x = notification.x - camera.x
      local y = notification.y - camera.y - progress * 58 - (visibleIndex - 1) * 26
      love.graphics.setFont(self.notificationFont)
      if notification.positive then
        love.graphics.setColor(0.38, 1, 0.42, alpha)
      else
        love.graphics.setColor(1, 0.3, 0.27, alpha)
      end
      love.graphics.printf(notification.text, x - 130, y, 260, 'center')
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Items:isPickupSoundPlaying()
  return self.pickupSound:isPlaying()
end

function Items:draw(camera)
  for _, item in ipairs(self.active) do
    local definition = item.definition
    local image = definition and definition.image
    if not image or type(image.getWidth) ~= 'function'
        or type(image.getHeight) ~= 'function' then
      error('Cannot draw active item: missing or invalid sprite for '
        .. tostring(definition and definition.name or 'unknown item'))
    else
      local offsetY = math.sin(item.timer * definition.bobSpeed) * definition.bobHeight
      local screenX = math.floor(item.x - camera.x)
      local screenY = math.floor(item.baseY - camera.y + offsetY)

      love.graphics.setColor(0, 0, 0, 0.3)
      love.graphics.ellipse('fill', screenX, math.floor(item.baseY - camera.y + 12), 14, 5)

      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        image,
        screenX,
        screenY,
        0,
        1,
        1,
        image:getWidth() / 2,
        image:getHeight() / 2
      )
    end
  end
end

function Items:getInventoryItems()
  local inventoryItems = {}
  for id in pairs(self.inventory) do
    local definition = self.definitions[id]
    if definition then
      inventoryItems[#inventoryItems + 1] = definition
    end
  end
  table.sort(inventoryItems, function(first, second)
    return first.id < second.id
  end)
  return inventoryItems
end

return Items