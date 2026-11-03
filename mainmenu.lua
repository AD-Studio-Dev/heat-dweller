-- Main menu with image title logo, additive embers and stronger feedback.
-- Drop-in replacement: same public API as the old MainMenu.
local MainMenu = {}
MainMenu.__index = MainMenu
local drawBackground
local drawScribble
local drawFlame
local drawLogo

local LOGO_PATH = 'resources/gfx/ui/stage/mainmenutitle.png'

local menuOptions = { 'NEW GAME', 'CONTINUE RUN', 'OPTIONS', 'EXTRAS', 'QUIT' }
local settingsOptions = { 'MUSIC VOLUME', 'SFX VOLUME', 'SCREEN SHAKE', 'BACK' }
local quitOptions = { 'YES, QUIT', 'NO, STAY' }

local HOT = { 1, 0.86, 0.5 }
local WARM = { 1, 0.68, 0.28 }
local DIM = { 0.66, 0.58, 0.47 }
local DISABLED = { 0.3, 0.26, 0.22 }

local function playSound(source)
  if source then
    source:stop()
    source:play()
  end
end

local function getImageDimensions(image)
  if not image or type(image.getWidth) ~= 'function'
      or type(image.getHeight) ~= 'function' then
    return nil, nil
  end
  local width, height = image:getWidth(), image:getHeight()
  if type(width) ~= 'number' or type(height) ~= 'number' or width <= 0 or height <= 0 then
    return nil, nil
  end
  return width, height
end

local function setNearestFilter(resource)
  if resource and type(resource.setFilter) == 'function' then
    resource:setFilter('nearest', 'nearest')
  end
end

-- Loads the title logo and finds the visible (non-transparent, non-white)
-- area so the empty padding around the letters doesn't affect scaling.
local function loadLogo(path)
  if not love.filesystem.getInfo(path) then
    return nil
  end
  local imageOk, image = pcall(love.graphics.newImage, path)
  if not imageOk or not image then
    return nil
  end
  image:setFilter('linear', 'linear') -- soft shadow/gradient: do NOT use nearest

  local imageWidth, imageHeight = image:getWidth(), image:getHeight()
  local minX, minY, maxX, maxY = imageWidth, imageHeight, 0, 0
  local dataOk, data = pcall(love.image.newImageData, path)
  if dataOk and data then
    local step = 2
    for y = 0, imageHeight - 1, step do
      for x = 0, imageWidth - 1, step do
        local r, g, b, a = data:getPixel(x, y)
        local isWhite = r > 0.96 and g > 0.96 and b > 0.96
        if a > 0.04 and not isWhite then
          if x < minX then minX = x end
          if x > maxX then maxX = x end
          if y < minY then minY = y end
          if y > maxY then maxY = y end
        end
      end
    end
  end
  if maxX <= minX or maxY <= minY then
    minX, minY, maxX, maxY = 0, 0, imageWidth - 1, imageHeight - 1
  end
  local pad = 6
  minX = math.max(0, minX - pad)
  minY = math.max(0, minY - pad)
  maxX = math.min(imageWidth - 1, maxX + pad)
  maxY = math.min(imageHeight - 1, maxY + pad)
  local width, height = maxX - minX + 1, maxY - minY + 1
  return {
    image = image,
    quad = love.graphics.newQuad(minX, minY, width, height, imageWidth, imageHeight),
    width = width,
    height = height,
  }
end

function MainMenu.new(renderer, switchSound, selectSound, cancelSound)
  local menu = setmetatable({
    renderer = renderer,
    switchSound = switchSound,
    selectSound = selectSound,
    cancelSound = cancelSound,
    titleFont = love.graphics.newFont(
      'resources/font/bigfont.ttf',
      math.max(36, math.min(64, love.graphics.getWidth() * 0.075))
    ),
    optionFont = love.graphics.newFont(
      'resources/font/bigfont.ttf',
      math.max(22, math.min(30, love.graphics.getHeight() * 0.055))
    ),
    logo = loadLogo(LOGO_PATH),
    selection = 1,
    cursorY = 0,
    animationTime = 0,
    screen = 'title',
    transitionTimer = 0,
    transitionDuration = 0.3,
    transitionDirection = 0,
    flashTimer = 0,
    flashDuration = 0.22,
    navigationHistory = {},
    backInputCooldown = 0,
    stageBackground = love.graphics.newImage('resources/gfx/ui/stage/mainmenustage.png'),
    pauseSelection = 1,
    pauseScreen = 'main',
    pauseFrameCanvas = nil,
    pauseCaptureDirty = true,
    pendingBinding = nil,
    pauseStickDirection = 0,
    itemSelectorOpen = false,
    itemSelectorQuery = '',
    itemSelectorIndex = 1,
    itemSelectorScroll = 0,
    itemSelectorItems = {},
    itemSelectorMessage = nil,
    leftStickDirection = 0,
    leftStickHorizontalDirection = 0,
    itemSelection = 1,
    optionY = {},
    hasSave = false,
    message = nil,
    musicVolume = 0.5,
    sfxVolume = 1,
    screenShakeEnabled = true,
    onSettingsChanged = nil,
    settingsSelection = 1,
    quitSelection = 2,
    extrasData = {},
    extrasPage = 1,
    extrasPageCount = 1,
    optionRects = {},
    hoveredSelection = nil,
    heatParticles = {},
  }, MainMenu)

  local screenWidth, screenHeight = love.graphics.getDimensions()
  for index = 1, 64 do
    local big = index % 7 == 0
    menu.heatParticles[index] = {
      x = (index * 73) % screenWidth,
      y = (index * 47) % screenHeight,
      size = big and (4 + index % 3) or (2 + index % 3),
      speed = (big and 26 or 12) + index % 22,
      alpha = (big and 0.7 or 0.35) + (index % 5) * 0.08,
      phase = index * 1.7,
    }
  end

  setNearestFilter(menu.stageBackground)
  setNearestFilter(menu.titleFont)
  setNearestFilter(menu.optionFont)
  setNearestFilter(menu.renderer.bigFont)
  setNearestFilter(menu.renderer.smallFont)
  setNearestFilter(menu.renderer.hudFont)
  return menu
end

----------------------------------------------------------------------
-- Admin item spawner
----------------------------------------------------------------------

function MainMenu:openItemSelector(items)
  self.itemSelectorOpen = true
  self.itemSelectorQuery = ''
  self.itemSelectorIndex = 1
  self.itemSelectorScroll = 0
  self.itemSelectorMessage = nil
  self:filterItemSelector(items)
end

function MainMenu:filterItemSelector(items)
  self.itemSelectorItems = {}
  local query = (self.itemSelectorQuery or ''):lower()
  for _, definition in pairs(items.definitions) do
    if query == '' or definition.name:lower():find(query, 1, true)
        or tostring(definition.id):find(query, 1, true) then
      self.itemSelectorItems[#self.itemSelectorItems + 1] = definition
    end
  end
  table.sort(self.itemSelectorItems, function(first, second)
    return first.id < second.id
  end)
  self.itemSelectorIndex = math.min(
    self.itemSelectorIndex,
    math.max(1, #self.itemSelectorItems)
  )
  self.itemSelectorScroll = math.min(
    self.itemSelectorScroll,
    math.max(0, #self.itemSelectorItems - 1)
  )
end

function MainMenu:moveItemSelector(delta)
  local itemCount = #self.itemSelectorItems
  if itemCount == 0 then
    return
  end
  self.itemSelectorIndex = (self.itemSelectorIndex - 1 + delta) % itemCount + 1
  local visibleRows = math.max(1, math.floor((love.graphics.getHeight() - 220) / 48))
  if self.itemSelectorIndex <= self.itemSelectorScroll then
    self.itemSelectorScroll = self.itemSelectorIndex - 1
  elseif self.itemSelectorIndex > self.itemSelectorScroll + visibleRows then
    self.itemSelectorScroll = self.itemSelectorIndex - visibleRows
  end
end

function MainMenu:itemSelectorKeypressed(key, items, player)
  if key == 'escape' or key == 'f7' then
    self.itemSelectorOpen = false
    return 'close'
  elseif key == 'up' then
    self:moveItemSelector(-1)
  elseif key == 'down' then
    self:moveItemSelector(1)
  elseif key == 'pageup' then
    self:moveItemSelector(-8)
  elseif key == 'pagedown' then
    self:moveItemSelector(8)
  elseif key == 'backspace' then
    self.itemSelectorQuery = self.itemSelectorQuery:sub(1, -2)
    self:filterItemSelector(items)
  elseif key == 'return' or key == 'kpenter' then
    local definition = self.itemSelectorItems[self.itemSelectorIndex]
    if definition then
      if definition.type == 'active' and not definition.image then
        self.itemSelectorMessage = 'This active item has no loaded icon and cannot be equipped.'
      else
        items:acquire(definition, player)
        self.itemSelectorMessage = definition.name .. ' granted.'
      end
    end
  end
end

function MainMenu:itemSelectorTextinput(text, items)
  if not self.itemSelectorOpen or not text:match('^[%w%s%p]+$') then
    return
  end
  self.itemSelectorQuery = self.itemSelectorQuery .. text:lower()
  self:filterItemSelector(items)
end

function MainMenu:itemSelectorClick(x, y, items, player)
  local screenWidth, screenHeight = love.graphics.getDimensions()
  local panelWidth, panelHeight = math.min(880, screenWidth - 48), math.min(680, screenHeight - 48)
  local panelX, panelY = (screenWidth - panelWidth) / 2, (screenHeight - panelHeight) / 2
  local listWidth = panelWidth * 0.55
  local rowHeight = 48
  local listTop = panelY + 106
  local row = math.floor((y - listTop) / rowHeight) + 1
  local index = self.itemSelectorScroll + row
  local visibleRows = math.max(1, math.floor((panelHeight - 142) / rowHeight))
  if x >= panelX and x <= panelX + listWidth and y >= listTop
      and row <= visibleRows
      and index >= 1 and index <= #self.itemSelectorItems then
    self.itemSelectorIndex = index
    self:itemSelectorKeypressed('return', items, player)
  end
end

function MainMenu:drawItemSelector(items)
  if not self.itemSelectorOpen then
    return
  end
  love.graphics.setShader()
  local screenWidth, screenHeight = love.graphics.getDimensions()
  local panelWidth, panelHeight = math.min(880, screenWidth - 48), math.min(680, screenHeight - 48)
  local panelX, panelY = (screenWidth - panelWidth) / 2, (screenHeight - panelHeight) / 2
  local listWidth = panelWidth * 0.55
  local rowHeight = 48
  local visibleRows = math.max(1, math.floor((panelHeight - 142) / rowHeight))
  self.itemSelectorScroll = math.min(
    self.itemSelectorScroll,
    math.max(0, #self.itemSelectorItems - visibleRows)
  )

  love.graphics.setColor(0.015, 0.02, 0.025, 0.9)
  love.graphics.rectangle('fill', 0, 0, screenWidth, screenHeight)
  love.graphics.setColor(0.08, 0.055, 0.045, 0.98)
  love.graphics.rectangle('fill', panelX, panelY, panelWidth, panelHeight, 8, 8)
  love.graphics.setColor(0.84, 0.49, 0.2, 1)
  love.graphics.rectangle('line', panelX, panelY, panelWidth, panelHeight, 8, 8)
  love.graphics.setFont(self.renderer.bigFont)
  love.graphics.printf('ADMIN ITEM SPAWNER', panelX + 20, panelY + 14, panelWidth - 40, 'center')
  love.graphics.setFont(self.renderer.smallFont)
  love.graphics.setColor(1, 0.84, 0.58, 1)
  love.graphics.print('Search: ' .. (self.itemSelectorQuery ~= '' and self.itemSelectorQuery or '_'), panelX + 24, panelY + 56)
  love.graphics.print('Type to filter  |  Enter: grant  |  F7 / Esc: close', panelX + 24, panelY + 78)
  love.graphics.setColor(0.47, 0.31, 0.18, 0.8)
  love.graphics.line(panelX + listWidth, panelY + 106, panelX + listWidth, panelY + panelHeight - 18)

  for visibleIndex = 1, visibleRows do
    local itemIndex = self.itemSelectorScroll + visibleIndex
    local definition = self.itemSelectorItems[itemIndex]
    if definition then
      local rowY = panelY + 106 + (visibleIndex - 1) * rowHeight
      if itemIndex == self.itemSelectorIndex then
        love.graphics.setColor(0.48, 0.24, 0.08, 0.75)
        love.graphics.rectangle('fill', panelX + 12, rowY, listWidth - 24, rowHeight - 2, 3, 3)
      end
      local imageWidth, imageHeight = getImageDimensions(definition.image)
      if imageWidth and imageHeight then
        local scale = math.min(32 / imageWidth, 32 / imageHeight)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(definition.image, panelX + 20, rowY + 5, 0, scale, scale)
      else
        love.graphics.setColor(0.35, 0.33, 0.3, 1)
        love.graphics.rectangle('line', panelX + 20, rowY + 7, 28, 28)
        love.graphics.print('?', panelX + 29, rowY + 11)
      end
      love.graphics.setColor(1, 0.93, 0.78, 1)
      love.graphics.print(string.format('#%d  %s', definition.id, definition.name), panelX + 60, rowY + 5)
      love.graphics.setColor(0.85, 0.67, 0.47, 1)
      love.graphics.print((definition.type == 'active' and 'ACTIVE' or 'PASSIVE')
        .. '  |  ' .. (items.inventory[definition.id] and 'Owned x' .. items.inventory[definition.id] or 'Not owned'),
        panelX + 60, rowY + 25)
    end
  end

  local selected = self.itemSelectorItems[self.itemSelectorIndex]
  if selected then
    local detailX = panelX + listWidth + 22
    local detailWidth = panelWidth - listWidth - 42
    love.graphics.setFont(self.renderer.bigFont)
    love.graphics.setColor(1, 0.83, 0.51, 1)
    love.graphics.printf(selected.name, detailX, panelY + 122, detailWidth, 'center')
    local imageWidth, imageHeight = getImageDimensions(selected.image)
    if imageWidth and imageHeight then
      local scale = math.min(112 / imageWidth, 112 / imageHeight)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        selected.image,
        detailX + (detailWidth - imageWidth * scale) / 2,
        panelY + 170,
        0,
        scale,
        scale
      )
    end
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.setColor(0.91, 0.84, 0.73, 1)
    love.graphics.printf(string.format('ID %d  |  %s', selected.id,
      selected.type == 'active' and 'Active Item' or 'Passive Item'),
      detailX, panelY + 292, detailWidth, 'center')
    love.graphics.printf(selected.description or '', detailX + 8, panelY + 330, detailWidth - 16, 'left')
  end

  if self.itemSelectorMessage then
    love.graphics.setColor(1, 0.77, 0.33, 1)
    love.graphics.printf(self.itemSelectorMessage, panelX + 18, panelY + panelHeight - 38, panelWidth - 36, 'center')
  end
  love.graphics.setColor(1, 1, 1, 1)
end

----------------------------------------------------------------------
-- Pause menu
----------------------------------------------------------------------

function MainMenu:openPause()
  self.pauseSelection = 1
  self.pauseScreen = 'main'
  self.pauseCaptureDirty = true
  self.pendingBinding = nil
  self.pauseStickDirection = 0
  self.itemSelection = 1
  self.backInputCooldown = 0
end

function MainMenu:updatePause(dt)
  self.animationTime = self.animationTime + dt
  local height = love.graphics.getHeight()
  local targetY = height * 0.52 + (self.pauseSelection - 1) * 52
  if self.cursorY == 0 then
    self.cursorY = targetY
  else
    self.cursorY = self.cursorY + (targetY - self.cursorY) * math.min(1, dt * 12)
  end
end

local pauseOptions = { 'RESUME', 'ITEMS', 'OPTIONS', 'QUIT TO MAIN MENU' }
local remappableBindings = {
  { key = 'moveUp', label = 'MOVE UP' },
  { key = 'moveDown', label = 'MOVE DOWN' },
  { key = 'moveLeft', label = 'MOVE LEFT' },
  { key = 'moveRight', label = 'MOVE RIGHT' },
  { key = 'attackUp', label = 'ATTACK UP' },
  { key = 'attackDown', label = 'ATTACK DOWN' },
  { key = 'attackLeft', label = 'ATTACK LEFT' },
  { key = 'attackRight', label = 'ATTACK RIGHT' },
  { key = 'interact', label = 'INTERACT' },
}

function MainMenu:pauseKeypressed(key, input)
  if self.pendingBinding then
    if key == 'escape' then
      self.pendingBinding = nil
    elseif key == 'p' then
      return
    else
      local previousBinding = input.bindings[self.pendingBinding]
      for binding, assignedKey in pairs(input.bindings) do
        if binding ~= self.pendingBinding and assignedKey == key then
          input.bindings[binding] = previousBinding
          break
        end
      end
      input.bindings[self.pendingBinding] = key
      self.pendingBinding = nil
      playSound(self.selectSound)
    end
    return
  end

  local returningFromPauseSubmenu = (key == 'escape' or key == 'backspace')
    and (self.pauseScreen == 'options' or self.pauseScreen == 'items')
  if returningFromPauseSubmenu and self.backInputCooldown > 0 then
    return
  end

  if self.pauseScreen == 'options' then
    local selectionCount = #remappableBindings + 1
    if key == 'up' or key == 'w' then
      self.pauseSelection = (self.pauseSelection - 2) % selectionCount + 1
      playSound(self.switchSound)
    elseif key == 'down' or key == 's' then
      self.pauseSelection = self.pauseSelection % selectionCount + 1
      playSound(self.switchSound)
    elseif key == 'escape' or key == 'backspace' then
      self.pauseScreen = 'main'
      self.pauseSelection = 3
      self.backInputCooldown = 0.28
      playSound(self.cancelSound or self.switchSound)
    elseif key == 'return' or key == 'space' then
      if self.pauseSelection == selectionCount then
        self.pauseScreen = 'main'
        self.pauseSelection = 3
      else
        self.pendingBinding = remappableBindings[self.pauseSelection].key
      end
    end
    return
  end

  if self.pauseScreen == 'items' then
    local itemCount = #(self.pauseItems or {})
    if key == 'up' or key == 'w' then
      self.itemSelection = itemCount > 0 and (self.itemSelection - 2) % itemCount + 1 or 1
      playSound(self.switchSound)
    elseif key == 'down' or key == 's' then
      self.itemSelection = itemCount > 0 and self.itemSelection % itemCount + 1 or 1
      playSound(self.switchSound)
    elseif key == 'escape' or key == 'backspace' then
      self.pauseScreen = 'main'
      self.pauseSelection = 2
      self.backInputCooldown = 0.28
      playSound(self.cancelSound or self.switchSound)
    end
    return
  end

  if key == 'up' or key == 'w' then
    self.pauseSelection = (self.pauseSelection - 2) % #pauseOptions + 1
    playSound(self.switchSound)
  elseif key == 'down' or key == 's' then
    self.pauseSelection = self.pauseSelection % #pauseOptions + 1
    playSound(self.switchSound)
  elseif key == 'return' or key == 'space' then
    playSound(self.selectSound)
    if self.pauseSelection == 1 then
      return 'resume'
    elseif self.pauseSelection == 2 then
      self.pauseScreen = 'items'
      self.itemSelection = 1
    elseif self.pauseSelection == 3 then
      self.pauseScreen = 'options'
      self.pauseSelection = 1
    else
      return 'quit_to_title'
    end
  end
end

function MainMenu:pauseGamepadpressed(button, input)
  if self.pendingBinding then
    return
  end
  if button == 'dpup' then
    self:pauseKeypressed('up', input)
  elseif button == 'dpdown' then
    self:pauseKeypressed('down', input)
  elseif button == 'a' or button == 'start' then
    self:pauseKeypressed('return', input)
  elseif button == 'b' then
    if self.pauseScreen == 'main' then
      if self.backInputCooldown > 0 then
        return
      end
      self.backInputCooldown = 0.28
      playSound(self.cancelSound or self.switchSound)
      return 'resume'
    end
    self:pauseKeypressed('escape', input)
  end
end

function MainMenu:pauseGamepadaxis(axis, value, input)
  if axis ~= 'lefty' then
    return
  end

  local direction = value < -0.6 and -1 or value > 0.6 and 1 or 0
  if direction ~= 0 and direction ~= self.pauseStickDirection then
    self:pauseGamepadpressed(direction < 0 and 'dpup' or 'dpdown', input)
  end
  self.pauseStickDirection = direction
end

function MainMenu:drawPause(input, items)
  love.graphics.setShader()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  if self.pauseFrameCanvas then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.pauseFrameCanvas, 0, 0, 0, 1, 1)
    love.graphics.setColor(0.03, 0.025, 0.028, 0.52)
    love.graphics.rectangle('fill', 0, 0, width, height)
  else
    drawBackground(width, height, self.animationTime, 0.84, nil, self.stageBackground)
    drawBackground(width, height, self.animationTime, 0.52, self.heatParticles, self.stageBackground)
  end
  local centerX = width / 2
  drawScribble('PAUSED', centerX, height * 0.18, self.titleFont, { 0.96, 0.84, 0.63 })

  local optionFont = self.optionFont
  if self.pauseScreen == 'main' then
    local cursorY
    for index, option in ipairs(pauseOptions) do
      local y = height * 0.46 + (index - 1) * 54
      local color = index == self.pauseSelection and HOT or DIM
      drawScribble(option, centerX, y, optionFont, color)
      if index == self.pauseSelection then
        cursorY = y
      end
    end
    drawFlame(centerX - 155, cursorY, self.animationTime)
  elseif self.pauseScreen == 'options' then
    drawScribble('OPTIONS - KEYBINDS', centerX, height * 0.13, self.renderer.bigFont, WARM)
    local firstY = height * 0.25
    for index, binding in ipairs(remappableBindings) do
      local y = firstY + (index - 1) * 31
      local selected = index == self.pauseSelection
      local label = binding.label .. '   ' .. (self.pendingBinding == binding.key
        and '[PRESS A KEY]' or string.upper(input.bindings[binding.key]))
      love.graphics.setColor(selected and 1 or 0.87, selected and 0.68 or 0.81, selected and 0.28 or 0.68, 1)
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.printf(label, centerX - 210, y, 420, 'center')
      if selected then
        drawFlame(centerX - 228, y + 7, self.animationTime)
      end
    end
    local backY = firstY + #remappableBindings * 31
    drawScribble('BACK', centerX, backY, self.renderer.bigFont, { 0.87, 0.81, 0.68 })
    if self.pauseSelection == #remappableBindings + 1 then
      drawFlame(centerX - 74, backY + 9, self.animationTime)
    end
    love.graphics.setColor(0.68, 0.55, 0.39, 0.9)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf(self.pendingBinding and 'PRESS A KEY TO BIND - ESC TO CANCEL' or 'UP / DOWN SELECT - ENTER REBIND - ESC BACK',
      0, height - 34, width, 'center')
  else
    self.pauseItems = {}
    for id, count in pairs(items and items.inventory or {}) do
      local definition = items.definitions[id]
      if definition then
        self.pauseItems[#self.pauseItems + 1] = { definition = definition, count = count }
      end
    end
    table.sort(self.pauseItems, function(first, second)
      return first.definition.id < second.definition.id
    end)
    self.itemSelection = math.max(1, math.min(self.itemSelection, #self.pauseItems))
    drawScribble('ITEMS', centerX, height * 0.12, self.renderer.bigFont, WARM)
    local listX = 34
    local listY = height * 0.22
    local listWidth = width * 0.42
    local rowHeight = math.min(58, (height * 0.62) / 8)
    local visibleRows = math.max(1, math.floor(height * 0.62 / rowHeight))
    local firstIndex = math.max(1, math.min(
      self.itemSelection - math.floor(visibleRows / 2),
      #self.pauseItems - visibleRows + 1
    ))
    firstIndex = math.max(1, firstIndex)
    love.graphics.setColor(0.045, 0.028, 0.022, 0.9)
    love.graphics.rectangle('fill', listX, listY, listWidth, visibleRows * rowHeight, 8, 8)
    for row = 0, visibleRows - 1 do
      local index = firstIndex + row
      local entry = self.pauseItems[index]
      if not entry then break end
      local rowTop = listY + row * rowHeight
      if index == self.itemSelection then
        love.graphics.setColor(0.34, 0.2, 0.09, 0.95)
        love.graphics.rectangle('fill', listX + 4, rowTop + 2, listWidth - 8, rowHeight - 4, 5, 5)
      end
      local imageWidth, imageHeight = getImageDimensions(entry.definition.image)
      if imageWidth and imageHeight then
        local iconScale = math.min(36 / imageWidth, 36 / imageHeight)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(entry.definition.image, listX + 12, rowTop + (rowHeight - 36) / 2, 0, iconScale, iconScale)
      end
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.setColor(0.95, 0.87, 0.73, 1)
      love.graphics.printf(entry.definition.name .. (entry.count > 1 and '  x' .. entry.count or ''),
        listX + 58, rowTop + (rowHeight - self.renderer.smallFont:getHeight()) / 2,
        listWidth - 68, 'left')
    end

    local selected = self.pauseItems[self.itemSelection]
    local detailX = listX + listWidth + 24
    local detailWidth = width - detailX - 34
    love.graphics.setColor(0.045, 0.028, 0.022, 0.9)
    love.graphics.rectangle('fill', detailX, listY, detailWidth, visibleRows * rowHeight, 8, 8)
    if selected then
      local definition = selected.definition
      local imageWidth, imageHeight = getImageDimensions(definition.image)
      if imageWidth and imageHeight then
        local iconScale = math.min(112 / imageWidth, 112 / imageHeight)
        local iconWidth = imageWidth * iconScale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(definition.image, detailX + (detailWidth - iconWidth) / 2, listY + 16, 0, iconScale, iconScale)
      end
      local contentY = listY + 142
      love.graphics.setFont(self.renderer.bigFont)
      love.graphics.setColor(1, 0.78, 0.39, 1)
      love.graphics.printf(definition.name, detailX + 16, contentY, detailWidth - 32, 'center')
      contentY = contentY + self.renderer.bigFont:getHeight() + 12
      local modifiers = {}
      for stat, amount in pairs(definition.effects or {}) do
        modifiers[#modifiers + 1] = string.format('%s %+.1f', stat, amount)
      end
      table.sort(modifiers)
      if definition.activeEffect then
        modifiers[#modifiers + 1] = string.format('Cooldown: %s s', tostring(definition.cooldown or definition.timedCooldown or 0))
      end
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.setColor(0.55, 0.94, 0.58, 1)
      love.graphics.printf(#modifiers > 0 and table.concat(modifiers, '  |  ') or 'No stat modifiers',
        detailX + 16, contentY, detailWidth - 32, 'center')
      contentY = contentY + self.renderer.smallFont:getHeight() + 10
      love.graphics.setColor(0.92, 0.86, 0.75, 1)
      love.graphics.printf(definition.description or '', detailX + 20, contentY, detailWidth - 40, 'center')
      if definition.activeEffect then
        local _, descriptionLines = self.renderer.smallFont:getWrap(
          definition.description or '', detailWidth - 40
        )
        contentY = contentY + #descriptionLines * self.renderer.smallFont:getHeight() + 12
        love.graphics.setColor(0.98, 0.74, 0.4, 1)
        love.graphics.printf(definition.activeEffect, detailX + 20, contentY, detailWidth - 40, 'center')
      end
    else
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.setColor(0.82, 0.75, 0.62, 1)
      love.graphics.printf('No items collected yet.', detailX + 16, listY + 80, detailWidth - 32, 'center')
    end
    love.graphics.setColor(0.68, 0.55, 0.39, 0.9)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf('UP / DOWN SELECT - ESC BACK', 0, height - 34, width, 'center')
  end

  love.graphics.setColor(1, 1, 1, 1)
end

----------------------------------------------------------------------
-- Update / navigation
----------------------------------------------------------------------

function MainMenu:update(dt)
  self.animationTime = self.animationTime + dt
  self:updateTransition(dt)
  local screenWidth, screenHeight = love.graphics.getDimensions()
  for _, particle in ipairs(self.heatParticles) do
    particle.y = particle.y - particle.speed * dt
    particle.x = particle.x + math.sin(self.animationTime * 0.7 + particle.phase) * 10 * dt
    if particle.y < -8 then
      particle.y = screenHeight + 8
      particle.x = (particle.x + screenWidth * 0.618) % screenWidth
    end
  end

  if self.screen == 'main' then
    local targetY = screenHeight * 0.4 + (self.selection - 1) * 46
    if self.cursorY == 0 then
      self.cursorY = targetY
    else
      self.cursorY = self.cursorY + (targetY - self.cursorY) * math.min(1, dt * 12)
    end
  end
end

function MainMenu:resetNavigation(screen)
  self.navigationHistory = {}
  self.screen = screen or 'title'
  self.transitionTimer = 0
  self.transitionDirection = 0
  self.flashTimer = 0
  self.backInputCooldown = 0
end

function MainMenu:updateTransition(dt)
  self.transitionTimer = math.max(0, self.transitionTimer - dt)
  self.flashTimer = math.max(0, self.flashTimer - dt)
  self.backInputCooldown = math.max(0, self.backInputCooldown - dt)
end

function MainMenu:setScreen(screen, isBack)
  if self.screen ~= screen then
    if not isBack then
      self.navigationHistory[#self.navigationHistory + 1] = self.screen
      self.transitionDirection = 1
    else
      self.transitionDirection = -1
    end
    self.screen = screen
    self.transitionTimer = self.transitionDuration
    self.flashTimer = self.flashDuration
  end
end

function MainMenu:back()
  if self.backInputCooldown > 0 or self.screen == 'title' then
    return false
  end

  local previousScreen = self.navigationHistory[#self.navigationHistory]
  if previousScreen then
    self.navigationHistory[#self.navigationHistory] = nil
  elseif self.screen == 'main' then
    previousScreen = 'title'
  else
    previousScreen = 'main'
  end

  self:setScreen(previousScreen, true)
  self.backInputCooldown = 0.28
  playSound(self.cancelSound or self.switchSound)
  return true
end

function MainMenu:getTransitionOffset()
  if self.transitionTimer <= 0 then
    return 0, 0
  end
  local progress = self.transitionTimer / self.transitionDuration
  local easedProgress = progress * progress
  return -self.transitionDirection * 70 * easedProgress,
    self.transitionDirection * 44 * easedProgress
end

function MainMenu:drawTransitionOverlay(width, height)
  if self.transitionTimer > 0 then
    local progress = self.transitionTimer / self.transitionDuration
    love.graphics.setColor(0.01, 0.008, 0.006, progress * 0.3)
    love.graphics.rectangle('fill', 0, 0, width, height)
  end
  if self.flashTimer > 0 then
    -- quick heat flare that fades out
    local progress = self.flashTimer / self.flashDuration
    love.graphics.setBlendMode('add')
    love.graphics.setColor(1, 0.45, 0.12, progress * progress * 0.4)
    love.graphics.rectangle('fill', 0, 0, width, height)
    love.graphics.setBlendMode('alpha')
  end
end

function MainMenu:moveSelection(direction)
  if self.screen == 'main' then
    local nextSelection = (self.selection - 1 + direction) % #menuOptions + 1
    if nextSelection ~= self.selection then
      self.selection = nextSelection
      playSound(self.switchSound)
    end
  elseif self.screen == 'options' then
    self.settingsSelection = (self.settingsSelection - 1 + direction) % #settingsOptions + 1
    playSound(self.switchSound)
  elseif self.screen == 'quit' then
    self.quitSelection = (self.quitSelection - 1 + direction) % #quitOptions + 1
    playSound(self.switchSound)
  elseif self.screen == 'extras' then
    if direction ~= 0 then
      self.extrasPage = (self.extrasPage - 1 + direction) % self.extrasPageCount + 1
      playSound(self.switchSound)
    end
  else
    return
  end
end

function MainMenu:adjustSetting(direction, value)
  if self.settingsSelection == 1 then
    self.musicVolume = value or math.max(0, math.min(1, self.musicVolume + direction * 0.1))
    self.musicVolume = math.max(0, math.min(1, self.musicVolume))
  elseif self.settingsSelection == 2 then
    self.sfxVolume = value or math.max(0, math.min(1, self.sfxVolume + direction * 0.1))
    self.sfxVolume = math.max(0, math.min(1, self.sfxVolume))
  elseif self.settingsSelection == 3 then
    self.screenShakeEnabled = not self.screenShakeEnabled
  else
    return
  end
  if self.onSettingsChanged then
    self.onSettingsChanged(self.musicVolume, self.sfxVolume, self.screenShakeEnabled)
  end
  playSound(self.selectSound)
end

function MainMenu:confirm()
  if self.screen == 'title' then
    self:setScreen('main')
    self.selection = 1
    self.cursorY = 0
    playSound(self.selectSound)
    return
  end

  if self.screen == 'options' then
    if self.settingsSelection == 1 or self.settingsSelection == 2 then
      self:adjustSetting(1)
    elseif self.settingsSelection == 3 then
      self:adjustSetting(0)
    else
      self:back()
    end
    return
  end

  if self.screen == 'extras' then
    self:back()
    return
  elseif self.screen == 'quit' then
    if self.quitSelection == 1 then
      playSound(self.selectSound)
      return 'quit'
    end
    self:back()
    return
  end

  playSound(self.selectSound)
  self.flashTimer = self.flashDuration
  if self.selection == 1 then
    return 'new_game'
  elseif self.selection == 2 then
    return self.hasSave and 'continue_run' or nil
  elseif self.selection == 3 then
    self.settingsSelection = 1
    self:setScreen('options')
  elseif self.selection == 4 then
    self:setScreen('extras')
  else
    self:setScreen('quit')
    self.quitSelection = 2
  end
end

----------------------------------------------------------------------
-- Input
----------------------------------------------------------------------

function MainMenu:keypressed(key)
  if key == 'up' or key == 'w' then
    self:moveSelection(-1)
  elseif key == 'down' or key == 's' then
    self:moveSelection(1)
  elseif key == 'left' or key == 'a' then
    if self.screen == 'options' then
      if self.settingsSelection == 3 then
        self:adjustSetting(0)
      else
        self:adjustSetting(-1)
      end
    elseif self.screen == 'quit' then
      self.quitSelection = 1
      playSound(self.switchSound)
    elseif self.screen == 'extras' then
      self:moveSelection(-1)
    end
  elseif key == 'right' or key == 'd' then
    if self.screen == 'options' then
      if self.settingsSelection == 3 then
        self:adjustSetting(0)
      else
        self:adjustSetting(1)
      end
    elseif self.screen == 'quit' then
      self.quitSelection = 2
      playSound(self.switchSound)
    elseif self.screen == 'extras' then
      self:moveSelection(1)
    end
  elseif key == 'return' or key == 'space' then
    return self:confirm()
  elseif key == 'escape' or key == 'backspace' then
    self:back()
  end
end

function MainMenu:gamepadpressed(button)
  if button == 'dpup' or button == 'leftshoulder' then
    self:moveSelection(-1)
  elseif button == 'dpdown' or button == 'rightshoulder' then
    self:moveSelection(1)
  elseif button == 'dpleft' then
    if self.screen == 'options' then
      if self.settingsSelection == 3 then self:adjustSetting(0) else self:adjustSetting(-1) end
    elseif self.screen == 'quit' then
      self.quitSelection = 1
      playSound(self.switchSound)
    elseif self.screen == 'extras' then
      self:moveSelection(-1)
    end
  elseif button == 'dpright' then
    if self.screen == 'options' then
      if self.settingsSelection == 3 then self:adjustSetting(0) else self:adjustSetting(1) end
    elseif self.screen == 'quit' then
      self.quitSelection = 2
      playSound(self.switchSound)
    elseif self.screen == 'extras' then
      self:moveSelection(1)
    end
  elseif button == 'a' or button == 'start' then
    return self:confirm()
  elseif button == 'b' then
    self:back()
  end
end

function MainMenu:gamepadaxis(axis, value)
  if axis == 'lefty' then
    local direction = value < -0.6 and -1 or value > 0.6 and 1 or 0
    if direction ~= 0 and direction ~= self.leftStickDirection then
      self:moveSelection(direction)
    end
    self.leftStickDirection = direction
  elseif axis == 'leftx' and self.screen == 'options' then
    local direction = value < -0.6 and -1 or value > 0.6 and 1 or 0
    if direction ~= 0 and direction ~= self.leftStickHorizontalDirection then
      if self.settingsSelection == 3 then self:adjustSetting(0) else self:adjustSetting(direction) end
    end
    self.leftStickHorizontalDirection = direction
  end
end

function MainMenu:mousepressed(x, y)
  if self.screen == 'title' then
    self:setScreen('main')
    self.selection = 1
    self.cursorY = 0
    playSound(self.selectSound)
    return
  elseif self.screen == 'options' then
    for index, rect in ipairs(self.optionRects) do
      if x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height then
        self.settingsSelection = index
        if index == 1 or index == 2 then
          local sliderX = rect.x + rect.width * 0.55
          local sliderWidth = rect.width * 0.29
          local value = math.max(0, math.min(1, (x - sliderX) / sliderWidth))
          self:adjustSetting(0, value)
        else
          self:confirm()
        end
        return
      end
    end
    return
  elseif self.screen == 'quit' then
    local width, height = love.graphics.getDimensions()
    local centerX = width / 2
    local boxY = height * 0.43
    if y >= boxY + 92 and y <= boxY + 140
        and x >= centerX - 190 and x <= centerX + 190 then
      self.quitSelection = x < centerX and 1 or 2
      return self:confirm()
    end
    return
  elseif self.screen == 'extras' then
    self:back()
    return
  end

  for index, optionY in ipairs(self.optionY) do
    if math.abs(y - optionY) <= 24 and math.abs(x - love.graphics.getWidth() / 2) <= 220 then
      if self.selection == index then
        return self:confirm()
      end
      self.selection = index
      self.cursorY = optionY
      playSound(self.switchSound)
      return self:confirm()
    end
  end
end

function MainMenu:mousemoved(x, y)
  if self.screen == 'main' then
    for index, optionY in ipairs(self.optionY) do
      if math.abs(y - optionY) <= 24 and math.abs(x - love.graphics.getWidth() / 2) <= 220 then
        if self.selection ~= index then
          self.selection = index
          self.cursorY = optionY
          playSound(self.switchSound)
        end
        return
      end
    end
  elseif self.screen == 'options' then
    for index, rect in ipairs(self.optionRects) do
      if x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height
          and self.settingsSelection ~= index then
        self.settingsSelection = index
        playSound(self.switchSound)
        return
      end
    end
  elseif self.screen == 'quit' then
    local boxY = love.graphics.getHeight() * 0.43
    local centerX = love.graphics.getWidth() / 2
    if y >= boxY + 92 and y <= boxY + 140
        and x >= centerX - 190 and x <= centerX + 190 then
      local selection = x < love.graphics.getWidth() / 2 and 1 or 2
      if self.quitSelection ~= selection then
        self.quitSelection = selection
        playSound(self.switchSound)
      end
    end
  end
end

function MainMenu:setExtrasData(data)
  self.extrasData = data or {}
  local rowsPerColumn = math.max(1, math.floor((love.graphics.getHeight() * 0.27) / 24))
  self.extrasPageCount = math.max(1, math.ceil(#(self.extrasData.discoveredItems or {}) / (rowsPerColumn * 2)))
  self.extrasPage = math.min(self.extrasPage, self.extrasPageCount)
end

function MainMenu:drawCharacterSelectBackground(width, height)
  drawBackground(width, height, self.animationTime, 0.52, self.heatParticles, self.stageBackground)
  drawScribble(
    'CHOOSE YOUR DWELLER',
    width / 2,
    height * 0.075,
    self.renderer.bigFont,
    WARM
  )
end

----------------------------------------------------------------------
-- Drawing helpers
----------------------------------------------------------------------

drawBackground = function(width, height, time, backgroundAlpha, particles, stageImage)
  local imageWidth, imageHeight = getImageDimensions(stageImage)
  if imageWidth and imageHeight then
    local scale = math.max(width / imageWidth, height / imageHeight)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      stageImage,
      width / 2,
      height / 2,
      0,
      scale,
      scale,
      imageWidth / 2,
      imageHeight / 2
    )
  else
    love.graphics.setColor(0.035, 0.022, 0.018, 1)
    love.graphics.rectangle('fill', 0, 0, width, height)
  end

  -- darken, but less than before so the stage art still reads
  love.graphics.setColor(0.012, 0.009, 0.008, backgroundAlpha or 0.3)
  love.graphics.rectangle('fill', 0, 0, width, height)

  if particles then
    -- warm glow rising from the bottom of the screen
    love.graphics.setBlendMode('add')
    local bands = 14
    local bandHeight = height * 0.4 / bands
    local pulse = 0.85 + math.sin(time * 1.3) * 0.15
    for band = 0, bands - 1 do
      local fade = (1 - band / bands)
      love.graphics.setColor(0.9, 0.28, 0.05, fade * fade * 0.07 * pulse)
      love.graphics.rectangle('fill', 0, height - (band + 1) * bandHeight, width, bandHeight + 1)
    end

    -- embers: additive so they actually glow
    for _, particle in ipairs(particles) do
      local shimmer = 0.7 + math.sin(time * 3 + particle.phase) * 0.3
      local alpha = particle.alpha * shimmer
      love.graphics.setColor(1, 0.4, 0.1, alpha * 0.35)
      love.graphics.circle('fill', particle.x, particle.y, particle.size * 2.2)
      love.graphics.setColor(1, 0.72, 0.3, alpha)
      love.graphics.circle('fill', particle.x, particle.y, particle.size)
    end
    love.graphics.setBlendMode('alpha')
  end
end

drawScribble = function(text, centerX, y, font, color)
  love.graphics.setFont(font)
  local textWidth = font:getWidth(text)
  local x = centerX - textWidth / 2
  love.graphics.setColor(color[1], color[2], color[3], 0.32)
  love.graphics.print(text, x - 2, y + 1, -0.012)
  love.graphics.setColor(color)
  love.graphics.print(text, x + 1, y, 0.008)
  love.graphics.setColor(color[1] * 0.93, color[2] * 0.9, color[3] * 0.82, 0.78)
  love.graphics.print(text, x, y + 2, -0.004)
end

drawFlame = function(x, y, time)
  local sway = math.sin(time * 7) * 2
  local flicker = 0.85 + math.sin(time * 13) * 0.15
  love.graphics.setBlendMode('add')
  love.graphics.setColor(0.9, 0.3, 0.05, 0.22 * flicker)
  love.graphics.circle('fill', x, y, 24)
  love.graphics.setBlendMode('alpha')
  love.graphics.setColor(0.9, 0.25, 0.045, 0.28)
  love.graphics.ellipse('fill', x, y + 12, 20, 8)
  love.graphics.setColor(0.94, 0.31, 0.055, 1)
  love.graphics.polygon('fill',
    x, y + 13,
    x - 10 + sway, y + 2,
    x - 6, y - 10,
    x, y - 3,
    x + 7 - sway, y - 13,
    x + 10, y + 4
  )
  love.graphics.setColor(1, 0.72, 0.25, 1)
  love.graphics.polygon('fill',
    x, y + 8,
    x - 4, y + 1,
    x + 2, y - 7,
    x + 5, y + 3
  )
end

-- Draws the title logo (image) centered at centerX/centerY, fitted inside
-- maxWidth x maxHeight, with a flickering additive heat glow behind it.
-- Returns false if the logo image isn't available.
drawLogo = function(menu, centerX, centerY, maxWidth, maxHeight, glowAlpha)
  local logo = menu.logo
  if not logo then
    return false
  end
  local scale = math.min(maxWidth / logo.width, maxHeight / logo.height)
  local time = menu.animationTime
  local flicker = 0.85 + 0.15 * math.sin(time * 9) * math.sin(time * 3.7)
  local originX, originY = logo.width / 2, logo.height / 2

  love.graphics.setBlendMode('add')
  love.graphics.setColor(1, 0.3, 0.06, glowAlpha * 0.5 * flicker)
  love.graphics.draw(logo.image, logo.quad, centerX, centerY, 0, scale * 1.1, scale * 1.1, originX, originY)
  love.graphics.setColor(1, 0.42, 0.1, glowAlpha * flicker)
  love.graphics.draw(logo.image, logo.quad, centerX, centerY, 0, scale * 1.04, scale * 1.04, originX, originY)
  love.graphics.setBlendMode('alpha')

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(logo.image, logo.quad, centerX, centerY, 0, scale, scale, originX, originY)
  return true
end

local function drawSectionNavigation(menu, width, height)
  local sections = {
    { label = 'TITLE', screen = 'title' },
    { label = 'MAIN OPTIONS', screen = 'main' },
    { label = 'SETTINGS', screen = 'options' },
    { label = 'EXTRAS / STATS', screen = 'extras' },
  }
  local activeScreen = menu.screen == 'quit' and 'main' or menu.screen
  local navY = height * 0.19
  local slotWidth = math.min(210, (width - 40) / #sections)
  local startX = (width - slotWidth * #sections) / 2

  love.graphics.setFont(menu.renderer.smallFont)
  for index, section in ipairs(sections) do
    local x = startX + (index - 1) * slotWidth
    local selected = section.screen == activeScreen
    if selected then
      love.graphics.setColor(0.68, 0.24, 0.07, 0.35)
      love.graphics.rectangle('fill', x + 4, navY - 5, slotWidth - 8, 30, 5, 5)
      love.graphics.setColor(0.98, 0.49, 0.16, 0.9)
      love.graphics.rectangle('fill', x + 12, navY + 23, slotWidth - 24, 2)
    end
    love.graphics.setColor(
      selected and 1 or 0.75,
      selected and 0.72 or 0.62,
      selected and 0.38 or 0.48,
      selected and 1 or 0.82
    )
    love.graphics.printf(section.label, x, navY + 3, slotWidth, 'center')
  end
end

----------------------------------------------------------------------
-- Main draw
----------------------------------------------------------------------

function MainMenu:draw(input)
  love.graphics.setShader()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  local centerX = width / 2
  drawBackground(width, height, self.animationTime, nil, self.heatParticles, self.stageBackground)
  local offsetX, offsetY = self:getTransitionOffset()
  love.graphics.push()
  love.graphics.translate(offsetX, offsetY)

  if self.screen == 'title' then
    local logoY = height * 0.36 + math.sin(self.animationTime * 1.6) * 5
    local drewLogo = drawLogo(self, centerX, logoY, width * 0.56, height * 0.34, 0.22)
    if not drewLogo then
      -- fallback if the logo image is missing
      drawScribble('HEAT DWELLER', centerX, logoY - 30, self.titleFont, { 0.98, 0.84, 0.62 })
    end

    drawFlame(centerX - 238, height * 0.66, self.animationTime)
    drawFlame(centerX + 238, height * 0.66, self.animationTime + 0.7)
    love.graphics.setFont(self.optionFont)
    local pulse = 0.8 + math.sin(self.animationTime * 3) * 0.2
    love.graphics.setColor(1, 0.8, 0.42, pulse)
    love.graphics.printf('PRESS SPACE TO START', 0, height * 0.65, width, 'center')
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.setColor(0.75, 0.63, 0.49, 0.85)
    love.graphics.printf('KEYBOARD  /  RETRO GAMEPAD', 0, height - 42, width, 'center')
  else
    local headerY = height * 0.095
    local drewLogo = drawLogo(self, centerX, headerY, width * 0.3, height * 0.115, 0.16)
    if not drewLogo then
      drawScribble('HEAT DWELLER', centerX, height * 0.055, self.renderer.bigFont, { 0.96, 0.84, 0.63 })
    end
    drawSectionNavigation(self, width, height)
  end

  if self.screen == 'main' then
    drawScribble('MAIN OPTIONS', centerX, height * 0.285, self.renderer.bigFont, WARM)
    self.optionY = {}
    local optionTop = height * 0.4
    for index, option in ipairs(menuOptions) do
      local y = optionTop + (index - 1) * 46
      self.optionY[index] = y
      local selected = index == self.selection
      local color
      if index == 2 and not self.hasSave then
        color = DISABLED
      elseif selected then
        color = HOT
      else
        color = DIM
      end
      local hoverOffset = selected and math.sin(self.animationTime * 4) * 2 or 0
      if selected then
        local glow = 0.16 + math.sin(self.animationTime * 3) * 0.05
        love.graphics.setBlendMode('add')
        love.graphics.setColor(0.95, 0.31, 0.08, glow)
        love.graphics.rectangle('fill', centerX - 200, y - 6, 400, 38, 8, 8)
        love.graphics.setColor(0.95, 0.4, 0.1, glow * 0.7)
        love.graphics.rectangle('fill', centerX - 200, y + 28, 400, 3)
        love.graphics.setBlendMode('alpha')
      end
      love.graphics.push()
      love.graphics.translate(centerX + (selected and 6 or 0), y + hoverOffset)
      love.graphics.scale(selected and 1.08 or 1, selected and 1.08 or 1)
      drawScribble(option, 0, 0, self.optionFont, color)
      love.graphics.pop()
    end
    drawFlame(centerX - 205, self.cursorY == 0 and self.optionY[self.selection] or self.cursorY, self.animationTime)
    love.graphics.setColor(0.68, 0.55, 0.39, 0.82)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf('UP / DOWN / D-PAD - CHOOSE     ENTER / A - SELECT     ESC / B - BACK', 0, height - 42, width, 'center')
  elseif self.screen == 'options' then
    drawScribble('OPTIONS / SETTINGS', centerX, height * 0.285, self.renderer.bigFont, WARM)
    self.optionRects = {}
    local rowWidth = math.min(520, width - 48)
    local rowX = centerX - rowWidth / 2
    local rowTop = height * 0.37
    local rowHeight = math.min(52, height * 0.085)
    for index, option in ipairs(settingsOptions) do
      local y = rowTop + (index - 1) * (rowHeight + 12)
      local rect = { x = rowX, y = y - 4, width = rowWidth, height = rowHeight }
      self.optionRects[index] = rect
      local selected = index == self.settingsSelection
      if selected then
        love.graphics.setBlendMode('add')
        love.graphics.setColor(0.95, 0.31, 0.08, 0.2)
        love.graphics.rectangle('fill', rect.x, rect.y, rect.width, rect.height, 6, 6)
        love.graphics.setBlendMode('alpha')
      end
      love.graphics.setFont(self.renderer.smallFont)
      if selected then
        love.graphics.setColor(1, 0.86, 0.5, 1)
      else
        love.graphics.setColor(0.7, 0.62, 0.5, 1)
      end
      love.graphics.printf(option, rect.x + 14, y + 8, rowWidth * 0.45, 'left')
      if selected then
        drawFlame(rect.x - 14, y + rowHeight / 2, self.animationTime)
      end
      if index <= 2 then
        local value = index == 1 and self.musicVolume or self.sfxVolume
        local barX = rect.x + rowWidth * 0.55
        local barY = y + rowHeight * 0.48
        love.graphics.setColor(0.2, 0.13, 0.09, 1)
        love.graphics.rectangle('fill', barX, barY, rowWidth * 0.29, 10, 4, 4)
        love.graphics.setColor(0.96, 0.39, 0.11, 1)
        love.graphics.rectangle('fill', barX, barY, rowWidth * 0.29 * value, 10, 4, 4)
        love.graphics.setColor(0.95, 0.87, 0.73, 1)
        love.graphics.printf(string.format('%d%%', math.floor(value * 100 + 0.5)),
          barX + rowWidth * 0.3, y + 8, rowWidth * 0.12, 'right')
      elseif index == 3 then
        love.graphics.setColor(self.screenShakeEnabled and 0.55 or 0.65,
          self.screenShakeEnabled and 0.92 or 0.58, self.screenShakeEnabled and 0.53 or 0.5, 1)
        love.graphics.printf(self.screenShakeEnabled and 'ON' or 'OFF',
          rect.x + rowWidth * 0.55, y + 8, rowWidth * 0.4, 'right')
      end
    end
    love.graphics.setColor(0.68, 0.55, 0.39, 0.82)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf('LEFT / RIGHT ADJUST     ENTER TO TOGGLE     ESC / B BACK', 0, height - 42, width, 'center')
  elseif self.screen == 'extras' then
    drawScribble('EXTRAS / STATS', centerX, height * 0.285, self.renderer.bigFont, WARM)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.setColor(0.95, 0.87, 0.73, 1)
    love.graphics.printf('RUNS STARTED: ' .. tostring(self.extrasData.runsStarted or 0)
      .. '     BOSSES DEFEATED: ' .. tostring(self.extrasData.bossesDefeated or 0),
      24, height * 0.38, width - 48, 'center')
    love.graphics.printf('FAVORITE ITEM: ' .. tostring(self.extrasData.favoriteItem or 'NONE YET'),
      24, height * 0.43, width - 48, 'center')
    love.graphics.setColor(1, 0.68, 0.28, 1)
    love.graphics.printf('DISCOVERED ITEMS', 24, height * 0.51, width - 48, 'center')
    love.graphics.setColor(0.82, 0.75, 0.62, 1)
    local discovered = self.extrasData.discoveredItems or {}
    local columns = 2
    local rowsPerColumn = math.max(1, math.floor((height * 0.27) / 24))
    local pageSize = rowsPerColumn * columns
    self.extrasPageCount = math.max(1, math.ceil(#discovered / pageSize))
    self.extrasPage = math.min(self.extrasPage, self.extrasPageCount)
    local firstIndex = (self.extrasPage - 1) * pageSize + 1
    local lastIndex = math.min(#discovered, firstIndex + pageSize - 1)
    for index = firstIndex, lastIndex do
      local name = discovered[index]
      local localIndex = index - firstIndex
      local column = math.floor(localIndex / rowsPerColumn)
      local row = localIndex % rowsPerColumn
      local columnWidth = (width - 72) / columns
      love.graphics.printf(name, 36 + column * columnWidth, height * 0.56 + row * 24, columnWidth - 18, 'left')
    end
    if #discovered == 0 then
      love.graphics.printf('Collect items during a run to discover them here.', 24, height * 0.59, width - 48, 'center')
    end
    love.graphics.setColor(0.68, 0.55, 0.39, 0.82)
    love.graphics.printf(string.format('UP / DOWN PAGE %d / %d     ESC / B / ENTER - BACK',
      self.extrasPage, self.extrasPageCount), 0, height - 42, width, 'center')
  elseif self.screen == 'quit' then
    love.graphics.setColor(0.01, 0.008, 0.006, 0.72)
    love.graphics.rectangle('fill', 0, 0, width, height)
    local boxWidth, boxHeight = math.min(520, width - 36), 190
    local boxX, boxY = centerX - boxWidth / 2, height * 0.43
    love.graphics.setColor(0.12, 0.065, 0.04, 0.98)
    love.graphics.rectangle('fill', boxX, boxY, boxWidth, boxHeight, 8, 8)
    love.graphics.setColor(0.84, 0.39, 0.13, 1)
    love.graphics.rectangle('line', boxX, boxY, boxWidth, boxHeight, 8, 8)
    drawScribble('ARE YOU SURE YOU WANT TO QUIT?', centerX, boxY + 32, self.renderer.smallFont, { 1, 0.84, 0.63 })
    for index, option in ipairs(quitOptions) do
      local x = centerX + (index == 1 and -100 or 100)
      local color = index == self.quitSelection and HOT or DIM
      drawScribble(option, x, boxY + 105, self.renderer.smallFont, color)
    end
    love.graphics.setColor(0.68, 0.55, 0.39, 0.9)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf('LEFT / RIGHT CHOOSE   ENTER CONFIRM   ESC CANCEL', 0, boxY + boxHeight + 16, width, 'center')
  end

  if self.message then
    love.graphics.setColor(1, 0.7, 0.3, 1)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf(self.message, 24, height - 28, width - 48, 'center')
  end

  love.graphics.pop()
  self:drawTransitionOverlay(width, height)
  love.graphics.setColor(1, 1, 1, 1)
end

return MainMenu