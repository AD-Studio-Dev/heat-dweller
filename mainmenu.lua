-- Main menu: off-white notebook doodle style (image logo, pinned paper, hand-drawn options).
-- Drop-in replacement: same public API as the old MainMenu.
local MainMenu = {}
MainMenu.__index = MainMenu
local drawBackground
local drawScribble
local drawCursor
local drawPanel
local drawLogo

local LOGO_PATH = 'resources/gfx/ui/mainmenu/menu_logo.png'
local PAPER_PATH = 'resources/gfx/ui/mainmenu/menu_paper.png'
local OPTIONS_PATH = 'resources/gfx/ui/mainmenu/menu_options.png'

-- menu_options.png: seven 128x32 cells stacked vertically.
local CELL_WIDTH, CELL_HEIGHT = 128, 32
local CONTINUE_DISABLED_ROW = 3
local CURSOR_ROW = 7
local OPTION_ROWS = { 1, 2, 4, 5, 6 } -- sheet row for each main menu entry
-- Where the visible ink starts inside each entry's cell (sheet pixels).
local OPTION_INK_LEFT = { 19, 10, 24, 24, 21 }
-- The cursor art sits mid-cell: its right edge and vertical centre.
local CURSOR_INK_RIGHT, CURSOR_INK_CENTER_Y = 77, 16

-- Main screen layout, in canvas pixels.
local PAPER_SCALE = 2
local PAPER_BOTTOM_MARGIN = 8
local MAIN_LOGO_CENTER_Y, MAIN_LOGO_MAX_HEIGHT = 54, 92
local OPTION_FIRST_CENTER = 210 -- from the paper's top edge, below the pushpin
local OPTION_SPACING = 68
local OPTION_HIT_HALF_HEIGHT = 33
local OPTION_HIT_HALF_WIDTH = 180
local CURSOR_GAP = 10

local menuOptions = { 'NEW GAME', 'CONTINUE RUN', 'OPTIONS', 'EXTRAS', 'QUIT' }
local settingsOptions = { 'MUSIC VOLUME', 'SFX VOLUME', 'SCREEN SHAKE', 'BACK' }
local quitOptions = { 'YES, QUIT', 'NO, STAY' }

local function rgb(r, g, b)
  return { r / 255, g / 255, b / 255 }
end

local HOT = rgb(209, 36, 31) -- #d1241f crimson: selection and highlights
local WARM = rgb(8, 0, 0) -- #080000 ink: headings and body text
local DIM = rgb(59, 50, 44) -- #3b322c soft ink: unselected entries and hints
local DISABLED = rgb(138, 127, 120) -- faded ink
local PAGE = rgb(209, 198, 194) -- #d1c6c2, the menu_bg.png paper colour
local CARD = rgb(237, 229, 211) -- cream panels and highlights
local CARD_SHADE = rgb(207, 194, 173) -- tan inset panels
local GOOD = rgb(26, 92, 36) -- dark green for stat modifiers

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

local function loadSprite(path)
  if not love.filesystem.getInfo(path) then
    return nil
  end
  local ok, image = pcall(love.graphics.newImage, path)
  if not ok or not image then
    return nil
  end
  setNearestFilter(image)
  return image
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
    stageBackground = love.graphics.newImage('resources/gfx/ui/mainmenu/menu_bg.png'),
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
    paper = loadSprite(PAPER_PATH),
    optionSheet = loadSprite(OPTIONS_PATH),
    optionQuads = {},
  }, MainMenu)

  if menu.optionSheet then
    for row = 1, CURSOR_ROW do
      menu.optionQuads[row] = love.graphics.newQuad(
        0, (row - 1) * CELL_HEIGHT, CELL_WIDTH, CELL_HEIGHT,
        CELL_WIDTH, CELL_HEIGHT * CURSOR_ROW
      )
    end
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
    -- Dim the frozen game; the ink text sits on a paper panel drawn on top.
    love.graphics.setColor(0.03, 0.025, 0.028, 0.52)
    love.graphics.rectangle('fill', 0, 0, width, height)
  else
    drawBackground(width, height, self.stageBackground)
  end
  local centerX = width / 2
  if self.pauseScreen == 'main' then
    drawPanel(centerX - 300, height * 0.18 - 36, 600, height * 0.60)
    drawScribble('PAUSED', centerX, height * 0.18, self.titleFont, WARM)
  elseif self.pauseScreen == 'options' then
    drawPanel(centerX - 320, height * 0.13 - 30, 640, height * 0.87 + 14)
  else
    drawPanel(14, 24, width - 28, height - 36)
    drawScribble('PAUSED', centerX, 34, self.renderer.bigFont, WARM)
  end

  local optionFont = self.optionFont
  if self.pauseScreen == 'main' then
    for index, option in ipairs(pauseOptions) do
      local y = height * 0.46 + (index - 1) * 54
      local selected = index == self.pauseSelection
      drawScribble(option, centerX, y, optionFont, selected and HOT or DIM)
      if selected then
        drawCursor(self, centerX - optionFont:getWidth(option) / 2 - CURSOR_GAP,
          y + optionFont:getHeight() / 2, 1)
      end
    end
  elseif self.pauseScreen == 'options' then
    drawScribble('OPTIONS - KEYBINDS', centerX, height * 0.13, self.renderer.bigFont, WARM)
    local firstY = height * 0.25
    for index, binding in ipairs(remappableBindings) do
      local y = firstY + (index - 1) * 31
      local selected = index == self.pauseSelection
      local label = binding.label .. '   ' .. (self.pendingBinding == binding.key
        and '[PRESS A KEY]' or string.upper(input.bindings[binding.key]))
      love.graphics.setColor(selected and HOT or WARM)
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.printf(label, centerX - 210, y, 420, 'center')
      if selected then
        drawCursor(self, centerX - self.renderer.smallFont:getWidth(label) / 2 - CURSOR_GAP,
          y + self.renderer.smallFont:getHeight() / 2, 1)
      end
    end
    local backY = firstY + #remappableBindings * 31
    local backSelected = self.pauseSelection == #remappableBindings + 1
    drawScribble('BACK', centerX, backY, self.renderer.bigFont, backSelected and HOT or DIM)
    if backSelected then
      drawCursor(self, centerX - self.renderer.bigFont:getWidth('BACK') / 2 - CURSOR_GAP,
        backY + self.renderer.bigFont:getHeight() / 2, 1)
    end
    love.graphics.setColor(DIM)
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
    love.graphics.setColor(CARD_SHADE)
    love.graphics.rectangle('fill', listX, listY, listWidth, visibleRows * rowHeight, 8, 8)
    for row = 0, visibleRows - 1 do
      local index = firstIndex + row
      local entry = self.pauseItems[index]
      if not entry then break end
      local rowTop = listY + row * rowHeight
      if index == self.itemSelection then
        love.graphics.setColor(CARD)
        love.graphics.rectangle('fill', listX + 4, rowTop + 2, listWidth - 8, rowHeight - 4, 5, 5)
      end
      local imageWidth, imageHeight = getImageDimensions(entry.definition.image)
      if imageWidth and imageHeight then
        local iconScale = math.min(36 / imageWidth, 36 / imageHeight)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(entry.definition.image, listX + 12, rowTop + (rowHeight - 36) / 2, 0, iconScale, iconScale)
      end
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.setColor(index == self.itemSelection and HOT or WARM)
      love.graphics.printf(entry.definition.name .. (entry.count > 1 and '  x' .. entry.count or ''),
        listX + 58, rowTop + (rowHeight - self.renderer.smallFont:getHeight()) / 2,
        listWidth - 68, 'left')
    end

    local selected = self.pauseItems[self.itemSelection]
    local detailX = listX + listWidth + 24
    local detailWidth = width - detailX - 34
    love.graphics.setColor(CARD_SHADE)
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
      love.graphics.setColor(WARM)
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
      love.graphics.setColor(GOOD)
      love.graphics.printf(#modifiers > 0 and table.concat(modifiers, '  |  ') or 'No stat modifiers',
        detailX + 16, contentY, detailWidth - 32, 'center')
      contentY = contentY + self.renderer.smallFont:getHeight() + 10
      love.graphics.setColor(WARM)
      love.graphics.printf(definition.description or '', detailX + 20, contentY, detailWidth - 40, 'center')
      if definition.activeEffect then
        local _, descriptionLines = self.renderer.smallFont:getWrap(
          definition.description or '', detailWidth - 40
        )
        contentY = contentY + #descriptionLines * self.renderer.smallFont:getHeight() + 12
        love.graphics.setColor(DIM)
        love.graphics.printf(definition.activeEffect, detailX + 20, contentY, detailWidth - 40, 'center')
      end
    else
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.setColor(WARM)
      love.graphics.printf('No items collected yet.', detailX + 16, listY + 80, detailWidth - 32, 'center')
    end
    love.graphics.setColor(DIM)
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

-- main.lua calls this after drawing the menus. The screen slide from
-- getTransitionOffset is the whole transition now: nothing is tinted or
-- flashed, so the paper keeps its true colour.
function MainMenu:drawTransitionOverlay(width, height)
  love.graphics.setColor(1, 1, 1, 1)
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

-- Main menu entry under the pointer; self.optionY holds each row's centre.
function MainMenu:mainOptionAt(x, y)
  if math.abs(x - love.graphics.getWidth() / 2) > OPTION_HIT_HALF_WIDTH then
    return nil
  end
  for index, optionY in ipairs(self.optionY) do
    if math.abs(y - optionY) <= OPTION_HIT_HALF_HEIGHT then
      return index
    end
  end
  return nil
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

  local index = self:mainOptionAt(x, y)
  if index then
    if self.selection ~= index then
      self.selection = index
      playSound(self.switchSound)
    end
    return self:confirm()
  end
end

function MainMenu:mousemoved(x, y)
  if self.screen == 'main' then
    local index = self:mainOptionAt(x, y)
    if index and self.selection ~= index then
      self.selection = index
      playSound(self.switchSound)
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
  drawBackground(width, height, self.stageBackground)
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

-- Largest whole-number (or 1/n) scale that is not above `scale`.
local function snapDown(scale)
  if scale >= 1 then
    return math.floor(scale)
  end
  return 1 / math.ceil(1 / scale - 1e-9)
end

drawBackground = function(width, height, stageImage)
  -- The page colour sits underneath in case the image is missing.
  love.graphics.setColor(PAGE)
  love.graphics.rectangle('fill', 0, 0, width, height)
  local imageWidth, imageHeight = getImageDimensions(stageImage)
  if imageWidth and imageHeight then
    -- Smallest whole-number (or 1/n) scale that still covers the canvas.
    local scale = math.max(width / imageWidth, height / imageHeight)
    if scale >= 1 then
      scale = math.ceil(scale - 1e-9)
    else
      scale = 1 / math.floor(1 / scale + 1e-9)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      stageImage,
      math.floor((width - imageWidth * scale) / 2),
      math.floor((height - imageHeight * scale) / 2),
      0,
      scale,
      scale
    )
  end
end

-- Centred, crisp single-pass text.
drawScribble = function(text, centerX, y, font, color)
  love.graphics.setFont(font)
  love.graphics.setColor(color)
  love.graphics.print(text, math.floor(centerX - font:getWidth(text) / 2), math.floor(y))
end

-- Draws the sheet's ">" cursor so its tip ends at rightX, centred on centerY.
drawCursor = function(menu, rightX, centerY, scale)
  local bob = math.floor(math.sin(menu.animationTime * 6) * 2 + 0.5)
  if menu.optionSheet then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      menu.optionSheet,
      menu.optionQuads[CURSOR_ROW],
      math.floor(rightX + bob - CURSOR_INK_RIGHT * scale),
      math.floor(centerY - CURSOR_INK_CENTER_Y * scale),
      0,
      scale,
      scale
    )
  else
    love.graphics.setColor(WARM)
    local tip = math.floor(rightX + bob)
    love.graphics.polygon('fill',
      tip, centerY,
      tip - 12 * scale, centerY - 7 * scale,
      tip - 12 * scale, centerY + 7 * scale)
  end
end

-- Cream paper card with an ink border and a soft drop shadow.
drawPanel = function(x, y, width, height)
  x, y = math.floor(x), math.floor(y)
  width, height = math.floor(width), math.floor(height)
  love.graphics.setColor(0, 0, 0, 0.18)
  love.graphics.rectangle('fill', x + 6, y + 6, width, height, 8, 8)
  love.graphics.setColor(CARD)
  love.graphics.rectangle('fill', x, y, width, height, 8, 8)
  love.graphics.setColor(DIM)
  love.graphics.setLineWidth(4)
  love.graphics.rectangle('line', x, y, width, height, 8, 8)
  love.graphics.setLineWidth(1)
end

drawLogo = function(menu, centerX, centerY, maxWidth, maxHeight, stayInside)
  local logo = menu.logo
  if not logo then
    return false
  end
  local scale = math.min(maxWidth / logo.width, maxHeight / logo.height)
  if stayInside then
    scale = snapDown(scale)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(logo.image, logo.quad, centerX, centerY, 0, scale, scale,
    logo.width / 2, logo.height / 2)
  return true
end

----------------------------------------------------------------------
-- Main draw
----------------------------------------------------------------------

function MainMenu:drawMainPaper(width, height)
  local centerX = math.floor(width / 2)
  local paperWidth, paperHeight = 256 * PAPER_SCALE, 320 * PAPER_SCALE
  local paperX = centerX - math.floor(paperWidth / 2)
  local paperY = height - paperHeight - PAPER_BOTTOM_MARGIN

  if self.paper then
    -- Soft shadow: faint black copies of the paper at growing offsets.
    for _, offset in ipairs({ { 3, 4 }, { 6, 7 }, { 9, 10 } }) do
      love.graphics.setColor(0, 0, 0, 0.07)
      love.graphics.draw(self.paper, paperX + offset[1], paperY + offset[2], 0, PAPER_SCALE, PAPER_SCALE)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.paper, paperX, paperY, 0, PAPER_SCALE, PAPER_SCALE)
  else
    drawPanel(paperX + 14, paperY + 28, paperWidth - 28, paperHeight - 40)
  end

  self.optionY = {}
  local cellWidth, cellHeight = CELL_WIDTH * PAPER_SCALE, CELL_HEIGHT * PAPER_SCALE
  for index, option in ipairs(menuOptions) do
    local rowCenter = paperY + OPTION_FIRST_CENTER + (index - 1) * OPTION_SPACING
    self.optionY[index] = rowCenter
    local selected = index == self.selection
    local disabled = index == 2 and not self.hasSave
    -- The selected row nudges right and bobs in whole sheet pixels.
    local nudge = selected
      and PAPER_SCALE * (2 + math.floor(math.sin(self.animationTime * 6) + 0.5)) or 0
    local cellX = centerX - math.floor(cellWidth / 2) + nudge
    local inkLeft
    if self.optionSheet then
      local row = disabled and CONTINUE_DISABLED_ROW or OPTION_ROWS[index]
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self.optionSheet, self.optionQuads[row],
        cellX, rowCenter - math.floor(cellHeight / 2), 0, PAPER_SCALE, PAPER_SCALE)
      inkLeft = cellX + OPTION_INK_LEFT[index] * PAPER_SCALE
    else
      local color = disabled and DISABLED or (selected and HOT or WARM)
      drawScribble(option, centerX + nudge, rowCenter - self.optionFont:getHeight() / 2,
        self.optionFont, color)
      inkLeft = centerX + nudge - self.optionFont:getWidth(option) / 2
    end
    if selected then
      drawCursor(self, inkLeft - CURSOR_GAP, rowCenter, PAPER_SCALE)
    end
  end

  -- Hints sit in the bottom-left corner so they stay clear of the paper.
  love.graphics.setColor(DIM)
  love.graphics.setFont(self.renderer.smallFont)
  love.graphics.printf('UP / DOWN / D-PAD - CHOOSE\nENTER / A - SELECT\nESC / B - BACK',
    24, height - 96, paperX - 48, 'left')
end

function MainMenu:draw(input)
  love.graphics.setShader()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  local centerX = width / 2
  drawBackground(width, height, self.stageBackground)
  local offsetX, offsetY = self:getTransitionOffset()
  love.graphics.push()
  love.graphics.translate(offsetX, offsetY)

  if self.screen == 'title' then
    local logoY = height * 0.36 + math.sin(self.animationTime * 1.6) * 5
    local drewLogo = drawLogo(self, centerX, logoY, width * 0.56, height * 0.34)
    if not drewLogo then
      drawScribble('HEAT DWELLER', centerX, logoY - 30, self.titleFont, WARM)
    end
  elseif self.screen == 'main' then
    -- A shorter banner leaves room for the full-size paper underneath.
    local drewLogo = drawLogo(self, centerX, MAIN_LOGO_CENTER_Y, width * 0.38, MAIN_LOGO_MAX_HEIGHT, true)
    if not drewLogo then
      drawScribble('HEAT DWELLER', centerX, MAIN_LOGO_CENTER_Y - 16, self.renderer.bigFont, WARM)
    end
  else
    -- TBoI-style clean fixed logo banner at top, leaving room for the menu below
    local headerY = height * 0.16
    local drewLogo = drawLogo(self, centerX, headerY, width * 0.38, height * 0.14)
    if not drewLogo then
      drawScribble('HEAT DWELLER', centerX, height * 0.12, self.renderer.bigFont, WARM)
    end
  end

  if self.screen == 'main' then
    self:drawMainPaper(width, height)
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
        love.graphics.setColor(CARD)
        love.graphics.rectangle('fill', rect.x, rect.y, rect.width, rect.height, 6, 6)
      end
      love.graphics.setFont(self.renderer.smallFont)
      love.graphics.setColor(selected and HOT or WARM)
      love.graphics.printf(option, rect.x + 14, y + 8, rowWidth * 0.45, 'left')
      if selected then
        drawCursor(self, rect.x - 6, rect.y + rect.height / 2, 1)
      end
      if index <= 2 then
        local value = index == 1 and self.musicVolume or self.sfxVolume
        local barX = rect.x + rowWidth * 0.55
        local barY = y + rowHeight * 0.48
        love.graphics.setColor(CARD_SHADE)
        love.graphics.rectangle('fill', barX, barY, rowWidth * 0.29, 10, 4, 4)
        if value > 0 then
          love.graphics.setColor(selected and HOT or DIM)
          love.graphics.rectangle('fill', barX, barY, rowWidth * 0.29 * value, 10, 4, 4)
        end
        love.graphics.setColor(WARM)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle('line', barX, barY, rowWidth * 0.29, 10, 4, 4)
        love.graphics.setLineWidth(1)
        love.graphics.printf(string.format('%d%%', math.floor(value * 100 + 0.5)),
          barX + rowWidth * 0.3, y + 8, rowWidth * 0.12, 'right')
      elseif index == 3 then
        love.graphics.setColor(self.screenShakeEnabled and WARM or DIM)
        love.graphics.printf(self.screenShakeEnabled and 'ON' or 'OFF',
          rect.x + rowWidth * 0.55, y + 8, rowWidth * 0.4, 'right')
      end
    end
    love.graphics.setColor(DIM)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf('LEFT / RIGHT ADJUST     ENTER TO TOGGLE     ESC / B BACK', 0, height - 42, width, 'center')
  elseif self.screen == 'extras' then
    drawScribble('EXTRAS / STATS', centerX, height * 0.285, self.renderer.bigFont, WARM)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.setColor(WARM)
    love.graphics.printf('RUNS STARTED: ' .. tostring(self.extrasData.runsStarted or 0)
      .. '     BOSSES DEFEATED: ' .. tostring(self.extrasData.bossesDefeated or 0),
      24, height * 0.38, width - 48, 'center')
    love.graphics.printf('FAVORITE ITEM: ' .. tostring(self.extrasData.favoriteItem or 'NONE YET'),
      24, height * 0.43, width - 48, 'center')
    love.graphics.setColor(HOT)
    love.graphics.printf('DISCOVERED ITEMS', 24, height * 0.51, width - 48, 'center')
    love.graphics.setColor(WARM)
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
    love.graphics.setColor(DIM)
    love.graphics.printf(string.format('UP / DOWN PAGE %d / %d     ESC / B / ENTER - BACK',
      self.extrasPage, self.extrasPageCount), 0, height - 42, width, 'center')
  elseif self.screen == 'quit' then
    local boxWidth, boxHeight = math.min(520, width - 36), 190
    local boxX, boxY = centerX - boxWidth / 2, height * 0.43
    drawPanel(boxX, boxY, boxWidth, boxHeight)
    drawScribble('ARE YOU SURE YOU WANT TO QUIT?', centerX, boxY + 32, self.renderer.smallFont, WARM)
    for index, option in ipairs(quitOptions) do
      local x = centerX + (index == 1 and -100 or 100)
      local selected = index == self.quitSelection
      drawScribble(option, x, boxY + 105, self.renderer.smallFont, selected and HOT or DIM)
      if selected then
        drawCursor(self, x - self.renderer.smallFont:getWidth(option) / 2 - CURSOR_GAP,
          boxY + 105 + self.renderer.smallFont:getHeight() / 2, 1)
      end
    end
    love.graphics.setColor(DIM)
    love.graphics.setFont(self.renderer.smallFont)
    love.graphics.printf('LEFT / RIGHT CHOOSE   ENTER CONFIRM   ESC CANCEL', 0, boxY + boxHeight + 16, width, 'center')
  end

  if self.message then
    love.graphics.setColor(HOT)
    love.graphics.setFont(self.renderer.smallFont)
    if self.screen == 'main' then
      -- Bottom-right corner, clear of the paper.
      local messageX = math.floor(width / 2) + 128 * PAPER_SCALE + 24
      love.graphics.printf(self.message, messageX, height - 96, width - messageX - 24, 'left')
    else
      love.graphics.printf(self.message, 24, height - 28, width - 48, 'center')
    end
  end

  love.graphics.pop()
  self:drawTransitionOverlay(width, height)
  love.graphics.setColor(1, 1, 1, 1)
end

return MainMenu