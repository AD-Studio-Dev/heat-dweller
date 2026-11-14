-- Player rendering. Atlas loading belongs in atlas.lua.
---@diagnostic disable: undefined-global
local LilSnake = require('lil_snake')
local Json = require('json')
local PixelGrid = require('pixelgrid')
local snap, snapScale = PixelGrid.snap, PixelGrid.snapScale
local Renderer = {}
Renderer.__index = Renderer

local geometricFrameIndices = {
  headForward = 0,
  headForwardBlink = 1,
  headRight = 2,
  headRightBlink = 3,
  bodyWalk = 4,
  bodyWalkAlt = 5,
}

local function getBossDrawOffset(boss)
  if not boss or not boss.deathSequence then
    return 0, 0
  end

  return math.random(-4, 4), math.random(-4, 4)
end

local function formatStat(value)
  if value % 1 == 0 then
    return string.format('%d', value)
  end
  return string.format('%.1f', value):gsub('%.0$', '')
end

-- The HUD floats directly on the angled stone wall frame (no sidebars), so it
-- hugs the canvas edge. HUD_ALPHA lets the brick texture show through it.
local HUD_MARGIN = 16
local HUD_ALPHA = 0.88

-- Stat icons are 32 x 32 pixel art. They are always drawn at a whole-number scale
-- (1 = native size) and never shrunk: a fractional or 0.5 scale makes nearest-neighbour
-- sampling drop and double pixels unevenly, which is what makes them glitch.
-- Use 2 for a bigger icon; do not use anything fractional.
local STAT_ICON_SOURCE = 32
local STAT_ICON_SCALE = 1
local STAT_ICON_SIZE = STAT_ICON_SOURCE * STAT_ICON_SCALE

-- Door sprites. Each sheet is 128 x 64 with 32 x 32 frames (see doors.json):
-- closed (0,0), three opening frames (32..96, 0), open (0,32). The art is drawn
-- for the TOP wall (wide edge outward) and rotated for the other three walls. At
-- 2x each door is exactly one 64 px tile, the same as the wall thickness.
-- Sheets that are missing on disk are skipped; the procedural door is used then.
local DOOR_SHEET_PATHS = {
  normal = 'resources/gfx/grid/doors_001_basementdoor.png',
  boss = 'resources/gfx/grid/doors_002_bossdoor.png',
  shop = 'resources/gfx/grid/doors_003_shopdoor.png',
  itemroom = 'resources/gfx/grid/doors_004_itemroomdoor.png',
  shoproom = 'resources/gfx/grid/doors_005_shoproomdoor.png',
}
-- Which sheet each kind of door uses (kind comes from main.lua's door list).
local DOOR_SHEET_FOR_KIND = {
  normal = 'normal', boss = 'boss', deal = 'boss', shop = 'shoproom', item = 'itemroom',
}
local DOOR_FRAME_SIZE, DOOR_SCALE, DOOR_FRAME_SECONDS = 32, 2, 0.1
local DOOR_ROTATION = { up = 0, right = math.pi / 2, down = math.pi, left = -math.pi / 2 }

-- Optional art: a missing file just means the normal look, never a crash.
-- 16x16 minimap room sprites: the room Matthew is in, and every other seen room.
local MINIMAP_INSIDE_PATH = 'resources/gfx/grid/minimap_insideroom_1x1.png'
local MINIMAP_OUTSIDE_PATH = 'resources/gfx/grid/minimap_outsideroom_1x1.png'
local MINIMAP_CELL = 16

local function loadOptionalImage(path)
  if not love.filesystem.getInfo(path) then
    print('Missing image: ' .. path)
    return nil
  end
  local ok, image = pcall(love.graphics.newImage, path)
  if not ok then
    print('Could not load ' .. path .. ': ' .. tostring(image))
    return nil
  end
  image:setFilter('nearest', 'nearest')
  return image
end

-- Costume sheets drawn over Matthew's sprite sheet (same frame layout), per
-- evolution (see Player.EVOLUTIONS). Drawn in this order.
local COSTUMES = {
  { evolution = 'burnt_chilli', path = 'resources/gfx/characters/costumes/costume_003_matthew-blushred.png' },
}
local FIRE_SWEAT_PATH = 'resources/sprites/attack/sweatattack_fire.png'

-- The Remote held in Matthew's hand (see remote.lua). The collectible sprite is
-- drawn as-is, gripped at its bottom-centre, with its top pointing along the swing.
-- REMOTE_SPRITE_ANGLE rotates it if the art's "tip" isn't at the top of the image.
local REMOTE_HELD_SCALE = 2
local REMOTE_SPRITE_ANGLE = 0
local REMOTE_SWING_SWEEP = math.rad(65) -- the blade sweeps +/- this around the aim
local REMOTE_REST = { -- hand offset from Matthew's centre and resting tilt, per facing
  right = { x = 22, y = 8, angle = 0.5 },
  left = { x = -22, y = 8, angle = -0.5 },
  down = { x = 20, y = 14, angle = 0.3 },
  up = { x = -20, y = 6, angle = -0.3 },
}

function Renderer.new(atlas)
  LilSnake.load()
  local renderer = setmetatable({ atlas = atlas }, Renderer)
  renderer.enemyImage = love.graphics.newImage('resources/gfx/enemies/spritesheets/entity_002_scar.png')
  renderer.spiderImage = love.graphics.newImage('resources/gfx/enemies/spritesheets/entity_001_spider.png')
  renderer.centipedeImage = love.graphics.newImage('resources/gfx/enemies/spritesheets/enemies_004_centipede.png')
  renderer.stationaryAngelImage = love.graphics.newImage('resources/gfx/enemies/spritesheets/enemies_005_stationaryangel.png')
  renderer.stationaryAngelImage:setFilter('nearest', 'nearest')
  renderer.divineBeamImage = love.graphics.newImage('resources/sprites/attack/divinebeam_attack.png')
  renderer.divineBeamImage:setFilter('nearest', 'nearest')
  renderer.crawlerImage = love.graphics.newImage('resources/gfx/bosses/spritesheets/boss_001_thecrawler.png')
  renderer.geometricImage = love.graphics.newImage('resources/gfx/bosses/spritesheets/boss_003_thegeometric.png')
  renderer.stuffingImage = love.graphics.newImage('resources/gfx/bosses/spritesheets/boss_004_thestuffing.png')
  renderer.stuffingCharredImage = love.graphics.newImage('resources/gfx/bosses/spritesheets/boss_004_thestuffingcharred.png')
  renderer.geometricPortrait = love.graphics.newImage('resources/gfx/bosses/portraits/thegeometric_portrait.png')
  renderer.stuffingPortrait = love.graphics.newImage('resources/gfx/bosses/portraits/thestuffing_portrait.png')
  renderer.acidImage = love.graphics.newImage('resources/sprites/attack/acid_attack.png')
  renderer.stuffingProjectileImage = love.graphics.newImage('resources/sprites/attack/thestuffing_attack.png')
  renderer.sweatImage = love.graphics.newImage('resources/sprites/attack/sweatattack.png')
  renderer.sweatSplashImage = love.graphics.newImage('resources/sprites/attack/sweat_splash.png')
  renderer.missingUnknownImage = love.graphics.newImage('resources/sprites/characters/missingunknown.png')
  renderer.missingUnknownImage:setFilter('nearest', 'nearest')
  renderer.fireFoamImage = love.graphics.newImage('resources/sprites/attack/firefoam.png')
  renderer.sweatImage:setFilter('nearest', 'nearest')
  renderer.fireSweatImage = loadOptionalImage(FIRE_SWEAT_PATH)
  renderer.minimapInsideImage = loadOptionalImage(MINIMAP_INSIDE_PATH)
  renderer.minimapOutsideImage = loadOptionalImage(MINIMAP_OUTSIDE_PATH)
  for _, image in ipairs({ renderer.minimapInsideImage or false, renderer.minimapOutsideImage or false }) do
    if image then
      image:setFilter('nearest', 'nearest')
    end
  end
  renderer.costumeImages = {}
  for _, costume in ipairs(COSTUMES) do
    renderer.costumeImages[costume.evolution] = loadOptionalImage(costume.path)
  end
  renderer.sweatSplashImage:setFilter('nearest', 'nearest')
  renderer.fireFoamImage:setFilter('nearest', 'nearest')
  local fireFoamJson, fireFoamReadError = love.filesystem.read('resources/sprites/attack/firefoam.json')
  if not fireFoamJson then
    error('Unable to read firefoam.json: ' .. tostring(fireFoamReadError))
  end
  local fireFoamData = Json.decode(fireFoamJson)
  renderer.fireFoamQuads = {}
  for name, frame in pairs(fireFoamData.frames) do
    local rect = frame.frame
    renderer.fireFoamQuads[name] = love.graphics.newQuad(
      rect.x, rect.y, rect.w, rect.h, renderer.fireFoamImage:getDimensions()
    )
  end
  renderer.matthewPortrait = love.graphics.newImage('resources/gfx/ui/stage/character_001_matthew_stage.png')
  renderer.crawlerPortrait = love.graphics.newImage('resources/gfx/bosses/portraits/thecrawler_portrait.png')
  renderer.lilSnakePortrait = love.graphics.newImage('resources/gfx/bosses/portraits/lilsnake_portrait.png')
  renderer.playerNameImage = love.graphics.newImage('resources/gfx/ui/stage/playername_001_matthew.png')
  renderer.playerIconImage = love.graphics.newImage('resources/gfx/ui/stage/playericon_001_matthew.png')
  renderer.vsImage = love.graphics.newImage('resources/gfx/ui/stage/vs.png')
  renderer.lilSnakeNameImage = love.graphics.newImage('resources/gfx/ui/stage/bossname_lilsnake.png')
  local crawlerNamePath = 'resources/gfx/ui/stage/bossname_thecrawler.png'
  if love.filesystem.getInfo(crawlerNamePath) then
    renderer.crawlerNameImage = love.graphics.newImage(crawlerNamePath)
    renderer.crawlerNameImage:setFilter('nearest', 'nearest')
  end
  renderer.lilSnakeImage = LilSnake.image
  renderer.enemyImage:setFilter('nearest', 'nearest')
  renderer.spiderImage:setFilter('nearest', 'nearest')
  renderer.centipedeImage:setFilter('nearest', 'nearest')
  renderer.crawlerImage:setFilter('nearest', 'nearest')
  renderer.geometricImage:setFilter('nearest', 'nearest')
  renderer.stuffingImage:setFilter('nearest', 'nearest')
  renderer.stuffingCharredImage:setFilter('nearest', 'nearest')
  renderer.geometricPortrait:setFilter('nearest', 'nearest')
  renderer.stuffingPortrait:setFilter('nearest', 'nearest')
  renderer.acidImage:setFilter('nearest', 'nearest')
  renderer.stuffingProjectileImage:setFilter('nearest', 'nearest')
  renderer.matthewPortrait:setFilter('nearest', 'nearest')
  renderer.crawlerPortrait:setFilter('nearest', 'nearest')
  renderer.lilSnakePortrait:setFilter('nearest', 'nearest')
  renderer.playerNameImage:setFilter('nearest', 'nearest')
  renderer.playerIconImage:setFilter('nearest', 'nearest')
  renderer.vsImage:setFilter('nearest', 'nearest')
  renderer.lilSnakeNameImage:setFilter('nearest', 'nearest')
  renderer.enemyQuads = {}
  renderer.spiderQuads = {
    [1] = love.graphics.newQuad(0, 0, 64, 64, renderer.spiderImage:getDimensions()),
    [2] = love.graphics.newQuad(64, 0, 64, 64, renderer.spiderImage:getDimensions()),
  }
  renderer.crawlerQuads = {}
  for frame = 0, 3 do
    renderer.crawlerQuads[frame + 1] = love.graphics.newQuad(frame * 96, 0, 96, 96, renderer.crawlerImage:getDimensions())
  end
  renderer.geometricQuads = {}
  for frame = 0, 5 do
    renderer.geometricQuads[frame] = love.graphics.newQuad(
      frame * 64, 0, 64, 64, renderer.geometricImage:getDimensions()
    )
  end
  renderer.stuffingQuads = {}
  for frame = 0, 4 do
    renderer.stuffingQuads[frame] = love.graphics.newQuad(
      frame * 64, 0, 64, 64, renderer.stuffingImage:getDimensions()
    )
  end
  renderer.stuffingCharredQuads = {}
  for frame = 0, 4 do
    renderer.stuffingCharredQuads[frame] = love.graphics.newQuad(
      frame * 64, 0, 64, 64, renderer.stuffingCharredImage:getDimensions()
    )
  end
  renderer.matthewPortraitQuad = love.graphics.newQuad(0, 0, 64, 64, renderer.matthewPortrait:getDimensions())
  renderer.crawlerPortraitQuad = love.graphics.newQuad(0, 0, 64, 64, renderer.crawlerPortrait:getDimensions())
  renderer.lilSnakePortraitQuad = LilSnake.frames.headRight.quad
  renderer.heartsImage = love.graphics.newImage('resources/gfx/health/hearts.png')
  renderer.heartsImage:setFilter('nearest', 'nearest')
  renderer.coinsIcon = love.graphics.newImage('resources/gfx/ui/stats/coins_icon.png')
  renderer.coinsIcon:setFilter('nearest', 'nearest')
  renderer.heartQuads = {
    full = love.graphics.newQuad(0, 0, 32, 32, renderer.heartsImage:getDimensions()),
    half = love.graphics.newQuad(0, 32, 32, 32, renderer.heartsImage:getDimensions()),
  }
  renderer.statImages = {
    speed = love.graphics.newImage('resources/gfx/ui/stats/stats_001_speed.png'),
    attackSpeed = love.graphics.newImage('resources/gfx/ui/stats/stats_002_attackspeed.png'),
    damage = love.graphics.newImage('resources/gfx/ui/stats/stats_003_damage.png'),
    range = love.graphics.newImage('resources/gfx/ui/stats/stats_004_range.png'),
  }
  for _, image in pairs(renderer.statImages) do
    image:setFilter('nearest', 'nearest')
  end
  renderer.bigFont = love.graphics.newFont('resources/font/bigfont.ttf', 24)
  renderer.floorIntroFont = love.graphics.newFont('resources/font/bigfont.ttf', 48)
  renderer.smallFont = love.graphics.newFont('resources/font/smallfont.ttf', 14)
  renderer.hudFont = love.graphics.newFont('resources/font/smallfont.ttf', 20)
  renderer.coinsFont = love.graphics.newFont('resources/font/smallfont.ttf', 28)
  renderer.statFont = love.graphics.newFont('resources/font/smallfont.ttf', 16)
  renderer.bossHealthTail = 1
  renderer.bossHealthIdentity = nil

  renderer.enemyQuads.idle_0 = love.graphics.newQuad(0, 0, 32, 32, renderer.enemyImage:getDimensions())
  for frame = 0, 8 do
    local x = (frame % 4) * 32
    local y = math.floor((frame + 1) / 4) * 32
    renderer.enemyQuads['scream_' .. frame] = love.graphics.newQuad(
      x, y, 32, 32, renderer.enemyImage:getDimensions()
    )
  end

  renderer.doorSheets = {}
  for sheetName, path in pairs(DOOR_SHEET_PATHS) do
    if love.filesystem.getInfo(path) then
      local image = love.graphics.newImage(path)
      image:setFilter('nearest', 'nearest')
      local imageWidth, imageHeight = image:getDimensions()
      local function frameQuad(x, y)
        return love.graphics.newQuad(x, y, DOOR_FRAME_SIZE, DOOR_FRAME_SIZE, imageWidth, imageHeight)
      end
      renderer.doorSheets[sheetName] = {
        image = image,
        closed = frameQuad(0, 0),
        opening = { frameQuad(32, 0), frameQuad(64, 0), frameQuad(96, 0) },
        open = frameQuad(0, 32),
      }
    end
  end
  renderer.doorStates = {}
  renderer.doorStateRoom = nil

  return renderer
end

function Renderer:updateBossHealth(boss, dt)
  if not boss or not boss.alive then
    self.bossHealthIdentity = nil
    self.bossHealthTail = 1
    return
  end

  if self.bossHealthIdentity ~= boss then
    self.bossHealthIdentity = boss
    self.bossHealthTail = 1
  end

  local maximumHealth = boss.maxHealth or boss.health
  local healthRatio = math.max(0, math.min(1, boss.health / maximumHealth))
  self.bossHealthTail = math.max(healthRatio, self.bossHealthTail - dt * 0.42)
end

function Renderer:drawBossHealthBar(boss)
  if not boss or not boss.alive then
    return
  end

  local maximumHealth = boss.maxHealth or boss.health
  local healthRatio = math.max(0, math.min(1, boss.health / maximumHealth))
  local screenWidth = love.graphics.getWidth()
  local width = math.min(760, math.max(0, screenWidth - 32))
  local nameWidth = math.min(148, width * 0.3)
  local iconSize = math.min(40, width * 0.1)
  local barWidth = math.max(24, width - nameWidth - iconSize - 16)
  local panelX = (screenWidth - width) / 2
  local x = panelX + nameWidth + 8
  local height = 18
  local y = love.graphics.getHeight() - 56
  local label = boss.kind == 'lilsnake' and "LIL' SNAKE"
    or boss.kind == 'geometric' and 'THE GEOMETRIC'
    or boss.kind == 'stuffing' and 'THE STUFFING' or 'THE CRAWLER'

  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.98, 0.82, 0.56, 1)
  love.graphics.printf(label, panelX, y + 2, nameWidth, 'left')
  love.graphics.setColor(0.12, 0.065, 0.025, 0.95)
  love.graphics.rectangle('fill', x - 4, y - 4, barWidth + 8, height + 8, 4, 4)
  love.graphics.setColor(0.58, 0.31, 0.1, 1)
  love.graphics.rectangle('line', x - 4, y - 4, barWidth + 8, height + 8, 4, 4)
  love.graphics.setColor(0.28, 0.14, 0.055, 1)
  love.graphics.rectangle('fill', x, y, barWidth, height, 2, 2)
  love.graphics.setColor(0.86, 0.38, 0.08, 1)
  love.graphics.rectangle('fill', x, y, barWidth * self.bossHealthTail, height, 2, 2)
  love.graphics.setColor(1, 0.69, 0.18, 1)
  love.graphics.rectangle('fill', x, y, barWidth * healthRatio, height, 2, 2)
  local portrait = boss.kind == 'geometric' and self.geometricPortrait
    or boss.kind == 'lilsnake' and self.lilSnakePortrait
    or boss.kind == 'stuffing' and self.stuffingPortrait or self.crawlerPortrait
  local portraitX = panelX + width - iconSize
  local portraitY = y + (height - iconSize) / 2
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    portrait,
    math.floor(portraitX),
    math.floor(portraitY),
    0,
    iconSize / portrait:getWidth(),
    iconSize / portrait:getHeight()
  )
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:setCharacter(imagePath)
  self.atlas.imagePath = imagePath
  self.atlas:load()
end

function Renderer:drawCharacterCarousel(characters, carouselPosition)
  local width, height = love.graphics.getDimensions()
  local centerX = width / 2
  local cardWidth = math.min(440, width * 0.52)
  local cardHeight = math.min(450, height * 0.62)
  local slotWidth = math.min(330, width * 0.28)
  local visibleCards = {}
  local characterCount = #characters

  if characterCount == 0 then
    return
  end

  for characterIndex, character in ipairs(characters) do
    local offset = characterIndex - carouselPosition
    while offset > characterCount / 2 do
      offset = offset - characterCount
    end
    while offset < -characterCount / 2 do
      offset = offset + characterCount
    end

    if math.abs(offset) <= 2.1 then
      visibleCards[#visibleCards + 1] = {
        character = character,
        offset = offset,
        index = characterIndex,
        focused = math.abs(offset) < 0.5,
      }
    end
  end

  table.sort(visibleCards, function(left, right)
    return left.offset < right.offset
  end)

  for _, card in ipairs(visibleCards) do
    local character = card.character
    local focused = card.focused
    local offset = card.offset
    local distance = math.abs(offset)
    local scale = 1 - math.min(0.7, distance * 0.24)
    local alpha = 1 - math.min(0.72, distance * 0.22)
    local currentCardWidth = cardWidth * scale
    local currentCardHeight = cardHeight * scale
    local cardCenterX = centerX + offset * slotWidth
    local cardX = snap(cardCenterX - currentCardWidth / 2)
    local cardY = snap((height - currentCardHeight) / 2 + 12)
    local isLocked = character.isUnlocked == false
    local displayName = isLocked and '???' or (character.name or '?')
    local displaySubtitle = isLocked and '???' or (character.title or character.subtitle or '???')
    local portraitImage = isLocked and self.missingUnknownImage or (character.image or self.missingUnknownImage)

    love.graphics.setColor(0.025, 0.018, 0.016, 0.88 * alpha)
    love.graphics.rectangle('fill', cardX, cardY, currentCardWidth, currentCardHeight, 6, 6)
    love.graphics.setColor(
      focused and 0.98 or 0.44,
      focused and 0.43 or 0.29,
      focused and 0.14 or 0.19,
      (focused and 0.92 or 0.46) * alpha
    )
    love.graphics.setLineWidth(focused and 3 or 1)
    love.graphics.rectangle('line', cardX, cardY, currentCardWidth, currentCardHeight, 6, 6)

    love.graphics.setColor(0.96, 0.84, 0.63, alpha)
    love.graphics.setFont(focused and self.bigFont or self.smallFont)
    love.graphics.printf(
      displayName,
      cardX + 12,
      cardY + 18,
      currentCardWidth - 24,
      'center'
    )

    local image = portraitImage
    if image then
      image:setFilter('nearest', 'nearest')
      local imageWidth, imageHeight = image:getDimensions()
      local imageScale = snapScale(focused and math.min(
        4,
        currentCardWidth * 0.34 / imageWidth,
        currentCardHeight * 0.36 / imageHeight
      ) or math.min(
        2.8,
        currentCardWidth * 0.32 / imageWidth,
        currentCardHeight * 0.3 / imageHeight
      ))
      local imageCenterY = focused and cardY + currentCardHeight * 0.31
        or cardY + currentCardHeight * 0.44
      love.graphics.setColor(focused and 1 or 0.52, focused and 1 or 0.52, focused and 1 or 0.52, alpha)
      love.graphics.draw(
        image,
        math.floor(cardCenterX),
        math.floor(imageCenterY),
        0,
        imageScale,
        imageScale,
        imageWidth / 2,
        imageHeight / 2
      )
    end

    if focused then
      local titleY = cardY + currentCardHeight * 0.49
      local quoteY = cardY + currentCardHeight * 0.56

      love.graphics.setColor(0.82, 0.78, 0.68, 1)
      love.graphics.setFont(self.smallFont)
      love.graphics.printf(displaySubtitle, cardX + 12, titleY, currentCardWidth - 24, 'center')

      love.graphics.setColor(0.72, 0.56, 0.39, 1)
      love.graphics.setFont(self.smallFont)
      love.graphics.printf(isLocked and '???' or (character.quote or displaySubtitle), cardX + 12, quoteY,
        currentCardWidth - 24, 'center')

      love.graphics.setColor(0.98, 0.49, 0.16, 0.75)
      love.graphics.rectangle(
        'fill',
        cardX + currentCardWidth * 0.12,
        cardY + currentCardHeight * 0.61,
        currentCardWidth * 0.76,
        2
      )

      local stats = {
        { key = 'health', value = isLocked and '?' or tostring(math.max(1, math.ceil(100 / 20))), image = self.heartsImage, quad = self.heartQuads.full },
        { key = 'speed', value = isLocked and '?' or tostring(350), image = self.statImages.speed },
        { key = 'damage', value = isLocked and '?' or tostring(20), image = self.statImages.damage },
        { key = 'range', value = isLocked and '?' or tostring(540), image = self.statImages.range },
        { key = 'attackSpeed', value = isLocked and '?' or '2.9', image = self.statImages.attackSpeed },
      }
      -- Icons stay native 32 x 32 (never shrunk). The stats wrap into up to 3 columns so
      -- they fit the card however far it is scaled down.
      local statIconSize = STAT_ICON_SIZE
      local statGap = 10
      local statTextGap = 8
      local statsX = cardX + currentCardWidth * 0.12
      local statsWidth = currentCardWidth * 0.76
      local statsY = cardY + currentCardHeight * 0.61 + 8
      local rowEntries = {}
      local widestEntry = 0

      for _, stat in ipairs(stats) do
        local valueText = tostring(stat.value)
        local entryWidth = statIconSize + statTextGap + self.smallFont:getWidth(valueText)
        widestEntry = math.max(widestEntry, entryWidth)
        rowEntries[#rowEntries + 1] = {
          image = stat.image,
          value = valueText,
          quad = stat.quad,
          width = entryWidth,
        }
      end
      local statColumns = math.max(1, math.min(3,
        math.floor((statsWidth + statGap) / (widestEntry + statGap))))

      local dividerY = cardY + currentCardHeight * 0.57
      love.graphics.setColor(0.95, 0.58, 0.18, 0.5)
      love.graphics.rectangle(
        'fill',
        cardX + currentCardWidth * 0.1,
        dividerY,
        currentCardWidth * 0.8,
        1.5
      )

      local statRowHeight = statIconSize + 6
      local statColumnWidth = widestEntry + statGap
      for index, stat in ipairs(rowEntries) do
        local column = (index - 1) % statColumns
        local row = math.floor((index - 1) / statColumns)
        local x = math.floor(statsX + column * statColumnWidth)
        local y = math.floor(statsY + row * statRowHeight)
        love.graphics.setColor(1, 1, 1, 1)
        if stat.quad then
          love.graphics.draw(stat.image, stat.quad, x, y, 0, STAT_ICON_SCALE, STAT_ICON_SCALE)
        else
          love.graphics.draw(stat.image, x, y, 0, STAT_ICON_SCALE, STAT_ICON_SCALE)
        end
        love.graphics.setColor(1, 0.79, 0.42, 1)
        love.graphics.print(stat.value, x + statIconSize + statTextGap,
          y + math.floor((statIconSize - self.smallFont:getHeight()) / 2))
      end
    end
  end

  love.graphics.setLineWidth(1)
  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.68, 0.55, 0.39, 0.9)
  love.graphics.printf(
    self.debugKeysEnabled and 'LEFT / RIGHT - CHOOSE     ENTER - BEGIN     F7 - BOSS DEBUG'
      or 'LEFT / RIGHT - CHOOSE     ENTER - BEGIN',
    0, height - 44, width, 'center'
  )
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawBossDebugMenu(bosses, selection)
  local width, height = love.graphics.getDimensions()
  love.graphics.setColor(0.01, 0.008, 0.01, 0.78)
  love.graphics.rectangle('fill', 0, 0, width, height)

  local panelWidth = math.min(560, width - 48)
  local panelHeight = math.min(390, height - 48)
  local panelX = (width - panelWidth) / 2
  local panelY = (height - panelHeight) / 2
  love.graphics.setColor(0.035, 0.022, 0.018, 0.98)
  love.graphics.rectangle('fill', panelX, panelY, panelWidth, panelHeight, 6, 6)
  love.graphics.setColor(0.95, 0.31, 0.08, 0.95)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle('line', panelX, panelY, panelWidth, panelHeight, 6, 6)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(self.bigFont)
  love.graphics.setColor(1, 0.68, 0.28, 1)
  love.graphics.printf('BOSS TELEPORT', panelX + 16, panelY + 28, panelWidth - 32, 'center')
  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.72, 0.62, 0.5, 1)
  love.graphics.printf('CHOOSE A BOSS TO START A DEBUG RUN', panelX + 16, panelY + 72, panelWidth - 32, 'center')

  for index, boss in ipairs(bosses) do
    local rowY = panelY + 118 + (index - 1) * 60
    if index == selection then
      love.graphics.setColor(0.75, 0.2, 0.045, 0.3)
      love.graphics.rectangle('fill', panelX + 42, rowY - 8, panelWidth - 84, 44, 4, 4)
    end
    love.graphics.setColor(index == selection and 1 or 0.7,
      index == selection and 0.72 or 0.62, index == selection and 0.38 or 0.52, 1)
    love.graphics.setFont(self.bigFont)
    love.graphics.printf(boss.name, panelX + 52, rowY, panelWidth - 104, 'center')
  end

  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.68, 0.55, 0.39, 0.9)
  love.graphics.printf('UP / DOWN - CHOOSE     ENTER / SPACE - TELEPORT     ESC - CLOSE',
    panelX + 16, panelY + panelHeight - 42, panelWidth - 32, 'center')
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawEnemy(enemy, camera)
  if not enemy.alive then
    return
  end

  if enemy.kind == 'stationaryangel' then
    self:drawStationaryAngel(enemy, camera)
    return
  end

  if enemy.kind == 'spider' then
    local spiderFrame = math.floor(enemy.animationTime / 0.1) % 2 + 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.spiderImage, self.spiderQuads[spiderFrame], math.floor(enemy.x - camera.x), math.floor(enemy.y - camera.y), 0, 2, 2, 32, 32)
    return
  end

  if enemy.kind == 'centipede' then
    local scale = snapScale((enemy.scale or 1) * 2)
    local dx = enemy.vx or 0
    local dy = enemy.vy or 0
    if dx == 0 and dy == 0 then
      dx, dy = 0, 1
    end
    local angle = math.atan2(dy, dx) - math.pi / 2
    local sourceWidth = self.centipedeImage:getWidth() or 32
    local sourceHeight = self.centipedeImage:getHeight() or 32

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      self.centipedeImage,
      math.floor(enemy.x - camera.x),
      math.floor(enemy.y - camera.y),
      angle,
      scale,
      scale,
      sourceWidth / 2,
      sourceHeight / 2
    )
    return
  end

  local frameName = 'idle_0'
  if enemy.anim and type(enemy.anim.getFrame) == 'function' then
    frameName = enemy.anim:getFrame()
  elseif type(enemy.getFrame) == 'function' then
    frameName = enemy:getFrame()
  end

  local quad = self.enemyQuads[frameName]
  if not quad then
    return
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    self.enemyImage,
    quad,
    math.floor(enemy.x - camera.x),
    math.floor(enemy.y - camera.y),
    0,
    2,
    2,
    16,
    16
  )
end

-- Stationary Angel: ground telegraph, divine beam, then the (shaking, shrinking)
-- sprite on top. Everything is driven by the enemy's own state, so a dead angel
-- (drawEnemy returns early when not alive) draws no beam at all.
function Renderer:drawStationaryAngel(angel, camera)
  local screenX = angel.beamX - camera.x
  local beamWidth = angel.beamWidth
  local floorY = (angel.beamBottom or 704) - camera.y -- 704 = room height
  local topY = -256 -- origin sits well above the top edge of the screen

  if angel:isTelegraphing() then
    local progress = angel:getTelegraphProgress()
    local blink = 0.6 + 0.4 * math.sin(progress * math.pi * 10)
    local screenHeight = love.graphics.getHeight()
    love.graphics.setColor(1, 0.9, 0.45, (0.1 + 0.2 * progress) * blink)
    love.graphics.rectangle('fill', screenX - beamWidth / 2, 0, beamWidth, screenHeight)
    love.graphics.setColor(1, 0.95, 0.6, 0.35 + 0.5 * progress)
    love.graphics.setLineWidth(2)
    love.graphics.line(screenX - beamWidth / 2, 0, screenX - beamWidth / 2, screenHeight)
    love.graphics.line(screenX + beamWidth / 2, 0, screenX + beamWidth / 2, screenHeight)
    -- Ground highlight where the beam will land.
    love.graphics.setColor(1, 0.95, 0.6, 0.45 + 0.4 * progress)
    love.graphics.ellipse('fill', screenX, floorY - 20, beamWidth / 2 * (0.5 + 0.5 * progress), 14)
    love.graphics.setLineWidth(1)
  elseif angel:isBeamActive() then
    local progress = angel:getBeamProgress()
    local fade = math.min(1, progress / 0.15, (1 - progress) / 0.3)
    local pulse = 0.92 + 0.08 * math.sin(angel.animationTime * 40)
    local image = self.divineBeamImage
    local imageWidth, imageHeight = image:getDimensions()
    local length = floorY - topY
    if length > 0 then
      love.graphics.setColor(1, 1, 1, math.max(0, fade))
      love.graphics.draw(
        image,
        math.floor(screenX),
        math.floor(topY),
        0,
        beamWidth * pulse / imageWidth,
        length / imageHeight,
        imageWidth / 2,
        0
      )
    end
  end

  local image = self.stationaryAngelImage
  local imageWidth, imageHeight = image:getDimensions()
  local displaySize = 128 * (angel.sizeFactor or 1)
  local scale = snapScale(displaySize / math.max(imageWidth, imageHeight))
  local intensity = angel.shakeIntensity or 0
  local shakeX = (math.random() * 2 - 1) * intensity
  local shakeY = (math.random() * 2 - 1) * intensity
  local bob = math.sin(angel.animationTime * 2) * 3
  if angel.hitFlashTimer and angel.hitFlashTimer > 0 then
    love.graphics.setColor(1, 0.6, 0.6, 1)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.draw(
    image,
    snap(angel.x - camera.x + shakeX),
    snap(angel.y - camera.y + bob + shakeY),
    0,
    scale,
    scale,
    imageWidth / 2,
    imageHeight / 2
  )
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawCrawler(crawler, camera)
  if not crawler or not crawler.alive then
    return
  end

  local shakeX, shakeY = getBossDrawOffset(crawler)
  local dx = (crawler.x or 0) - (crawler.lastX or crawler.x or 0)
  local dy = (crawler.y or 0) - (crawler.lastY or crawler.y or 0)
  local scaleX = 1
  local scaleY = 1
  local baseFrame = math.floor(crawler.animationTime / 0.1) % 2 + 1
  local frameIndex = baseFrame

  if math.abs(dx) >= math.abs(dy) then
    if dx > 0 then
      scaleX = -1
    end
    frameIndex = baseFrame
  else
    frameIndex = 2 + baseFrame
    if dy > 0 then
      scaleY = -1
    end
  end

  local scale = 3
  if crawler.phaseState == 'rage_pause' then
    love.graphics.setColor(1, 0.28, 0.12, 1)
    scale = 3
  elseif crawler.phaseState == 'charging' then
    local pulse = (math.sin(crawler.animationTime * 12) + 1) * 0.2
    love.graphics.setColor(1, 0.25 + pulse, 0.08, 1)
    scale = 3
  elseif crawler.phaseState == 'wall_running' then
    love.graphics.setColor(1, 0.18, 0.08, 1)
    scale = 3
  elseif crawler.phaseState == 'exhausted' then
    love.graphics.setColor(0.48, 0.72, 1, 1)
    scale = 3
  else
    love.graphics.setColor(1, 1, 1, 1)
  end

  love.graphics.draw(
    self.crawlerImage,
    self.crawlerQuads[frameIndex],
    math.floor(crawler.x - camera.x + shakeX),
    math.floor(crawler.y - camera.y + shakeY),
    0,
    scale * scaleX,
    scale * scaleY,
    48,
    48
  )
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawBabyWidow(babyWidow, camera)
  if not babyWidow or not babyWidow.alive then
    return
  end

  local scale = babyWidow.attackWindup > 0 and 3 or 2
  local flash = babyWidow.attackWindup > 0 and 0.35 or 0
  love.graphics.setColor(1, 1 - flash, 1 - flash, 1)
  love.graphics.draw(self.crawlerImage, self.crawlerQuads[babyWidow:getFrame()], math.floor(babyWidow.x - camera.x), math.floor(babyWidow.y - camera.y), 0, scale, scale, 48, 48)
end

function Renderer:drawAcidProjectile(projectile, camera)
  if not projectile.alive then
    return
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.acidImage, math.floor(projectile.x - camera.x), math.floor(projectile.y - camera.y), 0, 2, 2, self.acidImage:getWidth() / 2, self.acidImage:getHeight() / 2)
end

function Renderer:drawStuffingProjectile(projectile, camera)
  if not projectile or not projectile.alive then
    return
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    self.stuffingProjectileImage,
    math.floor(projectile.x - camera.x),
    math.floor(projectile.y - camera.y),
    math.atan2(projectile.vy, projectile.vx),
    1.8,
    1.8,
    self.stuffingProjectileImage:getWidth() / 2,
    self.stuffingProjectileImage:getHeight() / 2
  )
end

function Renderer:drawStuffing(boss, camera)
  if not boss or not boss.alive then
    return
  end

  local shakeX, shakeY = getBossDrawOffset(boss)
  local image = boss.charred and self.stuffingCharredImage or self.stuffingImage
  local quads = boss.charred and self.stuffingCharredQuads or self.stuffingQuads
  local frameIndex = 0
  if boss.suctioning then
    local cycle = math.floor((boss.animationTime * 9) % 3)
    frameIndex = 2 + cycle
  elseif math.floor(boss.animationTime * 2) % 6 == 0 then
    frameIndex = 1
  end

  local scale = 4
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image,
    quads[frameIndex],
    math.floor(boss.x - camera.x + shakeX),
    math.floor(boss.y - camera.y + shakeY),
    0,
    scale,
    scale,
    32,
    32
  )
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawGeometric(boss, camera)
  if not boss or not boss.alive then
    return
  end

  local shakeX, shakeY = getBossDrawOffset(boss)
  local frame = geometricFrameIndices[boss:getFrame()]
  if boss.phase == 'final' then
    local scaleX = boss.finalVx < 0 and -4 or 4
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      self.geometricImage,
      self.geometricQuads[frame],
      math.floor(boss.x - camera.x + shakeX),
      math.floor(boss.y - camera.y + shakeY),
      0,
      scaleX,
      4,
      32,
      32
    )
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  if boss.bodyAlive then
    local scaleX = boss.facing == 'left' and -3.5 or 3.5
    if boss.phase == 'body_recovery'
        and math.floor(boss.bodyInvulnerabilityTimer * 12) % 2 == 0 then
      love.graphics.setColor(0.45, 0.8, 1, 0.72)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.draw(
      self.geometricImage,
      self.geometricQuads[frame],
      math.floor(boss.x - camera.x + shakeX),
      math.floor(boss.y - camera.y + shakeY),
      0,
      scaleX,
      3.5,
      32,
      32
    )
  end

  if boss.shieldActive then
    local pulse = 0.88 + math.sin(boss.animationTime * 8) * 0.08
    love.graphics.setColor(0.32, 0.82, 1, 0.78)
    love.graphics.setLineWidth(5)
    love.graphics.circle(
      'line',
      math.floor(boss.x - camera.x),
      math.floor(boss.y - camera.y),
      boss.radius * pulse + 13
    )
    love.graphics.setLineWidth(1)
  end

  for _, head in ipairs(boss.heads) do
    if head.alive then
      local blinking = boss.animationTime % 3 < 0.12
      local headFrame = head.facing == 'left' and (blinking and 3 or 2)
        or (blinking and 1 or 0)
      if head.hitFlashTimer > 0 then
        love.graphics.setColor(1, 1, 1, 1)
      else
        love.graphics.setColor(1, 0.72, 0.24, 1)
      end
      love.graphics.draw(
        self.geometricImage,
        self.geometricQuads[headFrame],
        math.floor(head.x - camera.x + shakeX),
        math.floor(head.y - camera.y + shakeY),
        0,
        head.facing == 'left' and -2 or 2,
        2,
        32,
        32
      )
    end
  end

  for _, shatter in ipairs(boss.headShatters) do
    local progress = 1 - shatter.timer / 0.45
    local alpha = math.max(0, 1 - progress)
    local radius = 12 + progress * 42
    love.graphics.setColor(0.7, 0.94, 1, alpha)
    love.graphics.setLineWidth(3)
    love.graphics.circle(
      'line',
      math.floor(shatter.x - camera.x + shakeX),
      math.floor(shatter.y - camera.y + shakeY),
      radius
    )
    for shard = 1, 4 do
      local angle = shard * math.pi / 2 + progress * 2
      local x = shatter.x - camera.x + shakeX + math.cos(angle) * radius
      local y = shatter.y - camera.y + shakeY + math.sin(angle) * radius
      love.graphics.line(
        x,
        y,
        x + math.cos(angle) * 15,
        y + math.sin(angle) * 15
      )
    end
    love.graphics.setLineWidth(1)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawBossIntro(bossType, progress)
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  progress = math.max(0, math.min(1, progress or 1))
  local slideProgress = math.min(1, progress / 0.55)
  slideProgress = 1 - (1 - slideProgress) * (1 - slideProgress)
  local alpha = math.min(1, progress / 0.18)
  local centerY = height / 2
  local leftX = width * 0.09
  local rightNameX = width - 416
  local portraitX = width - 200

  love.graphics.setColor(0.035, 0.025, 0.025, 1)
  love.graphics.rectangle('fill', 0, 0, width, height)
  love.graphics.setColor(0.65, 0.25, 0.12, 0.24 * alpha)
  love.graphics.setLineWidth(2)
  love.graphics.line(48, 104, width - 48, 104)
  love.graphics.line(48, height - 104, width - 48, height - 104)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(0.98, 0.83, 0.58, alpha)
  love.graphics.setFont(self.bigFont)
  love.graphics.printf('BOSS ENCOUNTER', 0, 66, width, 'center')

  local leftStartX = -220
  local rightStartX = width + 220
  local playerX = leftStartX + (leftX - leftStartX) * slideProgress
  local bossNameX = rightStartX + (rightNameX - rightStartX) * slideProgress
  local bossPortraitX = rightStartX + (portraitX - rightStartX) * slideProgress
  local versusY = centerY - 32 + (1 - slideProgress) * -70

  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(
    self.playerIconImage,
    math.floor(playerX),
    math.floor(centerY - 48),
    0,
    1,
    1,
    0,
    0
  )
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(
    self.playerNameImage,
    math.floor(playerX + 108),
    math.floor(centerY - 32)
  )
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(self.vsImage, math.floor((width - 128) / 2), math.floor(versusY))

  if bossType == 'geometric' then
    love.graphics.setColor(0.98, 0.83, 0.58, alpha)
    love.graphics.setFont(self.bigFont)
    love.graphics.printf('THE GEOMETRIC', math.floor(bossNameX), math.floor(centerY - 16), 240, 'center')
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(
      self.geometricPortrait,
      math.floor(bossPortraitX),
      math.floor(centerY - 96),
      0,
      4,
      4
    )
  elseif bossType == 'stuffing' then
    love.graphics.setColor(0.98, 0.83, 0.58, alpha)
    love.graphics.setFont(self.bigFont)
    love.graphics.printf('THE STUFFING', math.floor(bossNameX), math.floor(centerY - 16), 240, 'center')
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(
      self.stuffingPortrait,
      math.floor(bossPortraitX),
      math.floor(centerY - 96),
      0,
      4,
      4
    )
  elseif bossType == 'lilsnake' then
    love.graphics.draw(self.lilSnakeNameImage, math.floor(bossNameX), math.floor(centerY - 32))
    love.graphics.draw(
      self.lilSnakeImage,
      self.lilSnakePortraitQuad,
      math.floor(bossPortraitX),
      math.floor(centerY - 96),
      0,
      4,
      4
    )
  else
    if self.crawlerNameImage then
      love.graphics.draw(self.crawlerNameImage, math.floor(bossNameX), math.floor(centerY - 32))
    else
      love.graphics.setColor(0.98, 0.83, 0.58, alpha)
      love.graphics.setFont(self.bigFont)
      love.graphics.printf('THE CRAWLER', math.floor(bossNameX), math.floor(centerY - 16), 192, 'center')
    end
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(
      self.crawlerPortrait,
      math.floor(bossPortraitX),
      math.floor(centerY - 46),
      0,
      92 / self.crawlerPortrait:getWidth(),
      92 / self.crawlerPortrait:getHeight()
    )
  end

  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- Angled stone wall frame (Isaac-style 2.5D perspective)
--
-- The frame is four trapezoids joined by 45 degree mitres, like a picture
-- frame: the OUTER edge is the canvas border, the INNER edge is the floor. A
-- point on a band is addressed by (u, v): u runs along the wall (0..1), v runs
-- from the outer edge (0) to the floor edge (1). Because the outer edge is
-- longer than the inner edge, brick joints (constant u) lean toward the room
-- centre and the courses (constant v) get shorter toward the floor, which is
-- what gives the walls their slanted, thick look.
-- ---------------------------------------------------------------------------
local WALL_SIDES = { 'up', 'left', 'right', 'down' }
local WALL_LIGHT = { up = 1.0, left = 0.8, right = 0.72, down = 0.56 } -- face lighting per wall
local WALL_CAP_DEPTH = 0.2 -- outer share of each band that is the lit top surface of the wall
local WALL_ROWS = 3
local WALL_COLUMNS = { up = 24, down = 24, left = 12, right = 12 }
local quadBuffer = {}

-- Outer edge (start, end) then floor edge (start, end) of one wall band.
local function bandGeometry(frame, side)
  local ox, oy, ow, oh = frame.outerX, frame.outerY, frame.outerWidth, frame.outerHeight
  local ix, iy, iw, ih = frame.innerX, frame.innerY, frame.innerWidth, frame.innerHeight
  if side == 'up' then
    return { ox, oy, ox + ow, oy, ix, iy, ix + iw, iy }
  elseif side == 'down' then
    return { ox, oy + oh, ox + ow, oy + oh, ix, iy + ih, ix + iw, iy + ih }
  elseif side == 'left' then
    return { ox, oy, ox, oy + oh, ix, iy, ix, iy + ih }
  end
  return { ox + ow, oy, ox + ow, oy + oh, ix + iw, iy, ix + iw, iy + ih }
end

local function bandPoint(geometry, u, v)
  local outerX = geometry[1] + (geometry[3] - geometry[1]) * u
  local outerY = geometry[2] + (geometry[4] - geometry[2]) * u
  local innerX = geometry[5] + (geometry[7] - geometry[5]) * u
  local innerY = geometry[6] + (geometry[8] - geometry[6]) * u
  return outerX + (innerX - outerX) * v, outerY + (innerY - outerY) * v
end

-- Fills `quadBuffer` with the 4 corners of the (u0..u1, v0..v1) patch.
local function bandQuad(geometry, u0, u1, v0, v1)
  quadBuffer[1], quadBuffer[2] = bandPoint(geometry, u0, v0)
  quadBuffer[3], quadBuffer[4] = bandPoint(geometry, u1, v0)
  quadBuffer[5], quadBuffer[6] = bandPoint(geometry, u1, v1)
  quadBuffer[7], quadBuffer[8] = bandPoint(geometry, u0, v1)
  return quadBuffer
end

local function fillBand(geometry, u0, u1, v0, v1)
  love.graphics.polygon('fill', bandQuad(geometry, u0, u1, v0, v1))
end

local function setShaded(color, factor, alpha)
  love.graphics.setColor(
    math.min(1, color[1] * factor), math.min(1, color[2] * factor), math.min(1, color[3] * factor), alpha or 1
  )
end

-- Deterministic 0..1 noise so each brick keeps its own shade every frame.
local function brickNoise(a, b, c)
  local value = math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
  return value - math.floor(value)
end

local function drawWallBand(theme, geometry, side, sideIndex)
  local light = WALL_LIGHT[side]

  -- Mortar underlay for the whole band.
  setShaded(theme.mortar, light)
  fillBand(geometry, 0, 1, 0, 1)

  -- Lit top surface (cap) along the outer edge.
  setShaded(theme.cap, light)
  fillBand(geometry, 0, 1, 0, WALL_CAP_DEPTH - 0.025)

  -- Brick courses between the cap and the floor, in running bond.
  local columns = WALL_COLUMNS[side]
  local gapU = 0.14 / columns
  local gapV = 0.05 / WALL_ROWS
  for row = 0, WALL_ROWS - 1 do
    local v0 = WALL_CAP_DEPTH + (1 - WALL_CAP_DEPTH) * row / WALL_ROWS
    local v1 = WALL_CAP_DEPTH + (1 - WALL_CAP_DEPTH) * (row + 1) / WALL_ROWS
    local offset = row % 2 == 1 and 0.5 or 0
    for column = 0, columns do
      local u0 = (column - offset) / columns
      local u1 = u0 + 1 / columns
      local from = math.max(0, u0 + gapU)
      local to = math.min(1, u1 - gapU)
      if to > from then
        -- Rows nearer the floor are a touch lighter, like light falling down the face.
        local shade = light * (0.88 + 0.24 * brickNoise(sideIndex, row, column))
          * (0.94 + 0.06 * (row / (WALL_ROWS - 1)))
        setShaded(theme.face, shade)
        fillBand(geometry, from, to, v0 + gapV, v1 - gapV)
      end
    end
  end

  -- Bevel along the floor edge and a dark line along the outer edge.
  local floorX0, floorY0 = bandPoint(geometry, 0, 1)
  local floorX1, floorY1 = bandPoint(geometry, 1, 1)
  setShaded(theme.cap, light * 1.15, 0.9)
  love.graphics.setLineWidth(2)
  love.graphics.line(floorX0, floorY0, floorX1, floorY1)
  setShaded(theme.mortar, 0.6)
  local capX0, capY0 = bandPoint(geometry, 0, WALL_CAP_DEPTH - 0.012)
  local capX1, capY1 = bandPoint(geometry, 1, WALL_CAP_DEPTH - 0.012)
  love.graphics.line(capX0, capY0, capX1, capY1)
end

-- A doorway cut through the band: stone jamb, dark passage, then the door
-- (solid when locked, an open threshold strip when unlocked).
-- Draws one door from its sprite sheet in the 64 px wall ring, playing the
-- opening animation when it goes from locked to unlocked. Returns false when no
-- sheet is loaded so the caller can fall back to the procedural door.
local function drawDoorSprite(self, door, frame)
  local sheet = self.doorSheets[DOOR_SHEET_FOR_KIND[door.kind or 'normal']] or self.doorSheets.normal
  if not sheet then
    return false
  end

  local now = love.timer.getTime()
  local locked = door.locked and true or false
  local state = self.doorStates[door.side]
  if not state then
    state = { locked = locked }
    self.doorStates[door.side] = state
  end
  if locked then
    state.openedAt = nil
  elseif state.locked then
    state.openedAt = now -- just unlocked: start the opening frames
  end
  state.locked = locked

  local quad = sheet.closed
  if not locked then
    local openFor = state.openedAt and (now - state.openedAt) or math.huge
    local index = math.floor(openFor / DOOR_FRAME_SECONDS) + 1
    quad = sheet.opening[index] or sheet.open
  end

  local half = DOOR_FRAME_SIZE * DOOR_SCALE / 2
  local middleX = frame.innerX + frame.innerWidth / 2
  local middleY = frame.innerY + frame.innerHeight / 2
  local x, y
  if door.side == 'up' then
    x, y = middleX, frame.innerY - half
  elseif door.side == 'down' then
    x, y = middleX, frame.innerY + frame.innerHeight + half
  elseif door.side == 'left' then
    x, y = frame.innerX - half, middleY
  else
    x, y = frame.innerX + frame.innerWidth + half, middleY
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    sheet.image, quad, math.floor(x), math.floor(y), DOOR_ROTATION[door.side],
    DOOR_SCALE, DOOR_SCALE, DOOR_FRAME_SIZE / 2, DOOR_FRAME_SIZE / 2
  )
  return true
end

local function drawWallDoor(self, theme, geometry, door, frame)
  if drawDoorSprite(self, door, frame) then
    return
  end

  local innerStart, innerLength, doorCenter
  if door.side == 'up' or door.side == 'down' then
    innerStart, innerLength = frame.innerX, frame.innerWidth
    doorCenter = frame.innerX + frame.innerWidth / 2
  else
    innerStart, innerLength = frame.innerY, frame.innerHeight
    doorCenter = frame.innerY + frame.innerHeight / 2
  end
  local half = frame.doorLength / 2
  local u0 = (doorCenter - half - innerStart) / innerLength
  local u1 = (doorCenter + half - innerStart) / innerLength
  local jamb = 0.012
  local color = door.color

  setShaded(theme.mortar, 0.45)
  fillBand(geometry, u0 - jamb, u1 + jamb, 0, 1)
  love.graphics.setColor(0.015, 0.012, 0.018, 1)
  fillBand(geometry, u0, u1, 0, 1)

  if door.locked then
    love.graphics.setColor(color[1], color[2], color[3], 1)
    fillBand(geometry, u0 + 0.006, u1 - 0.006, 0.12, 1)
    love.graphics.setColor(color[1] * 1.35, color[2] * 1.35, color[3] * 1.35, 0.9)
    love.graphics.setLineWidth(2)
    local seamX0, seamY0 = bandPoint(geometry, (u0 + u1) / 2, 0.12)
    local seamX1, seamY1 = bandPoint(geometry, (u0 + u1) / 2, 1)
    love.graphics.line(seamX0, seamY0, seamX1, seamY1)
    local barX0, barY0 = bandPoint(geometry, u0 + 0.006, 0.55)
    local barX1, barY1 = bandPoint(geometry, u1 - 0.006, 0.55)
    love.graphics.line(barX0, barY0, barX1, barY1)
  else
    love.graphics.setColor(color[1], color[2], color[3], 0.9)
    fillBand(geometry, u0, u1, 0.82, 1)
    love.graphics.setColor(color[1] * 1.3, color[2] * 1.3, color[3] * 1.3, 0.95)
    love.graphics.setLineWidth(3)
    local postX0, postY0 = bandPoint(geometry, u0, 0)
    local postX1, postY1 = bandPoint(geometry, u0, 1)
    local postX2, postY2 = bandPoint(geometry, u1, 0)
    local postX3, postY3 = bandPoint(geometry, u1, 1)
    love.graphics.line(postX0, postY0, postX1, postY1)
    love.graphics.line(postX2, postY2, postX3, postY3)
  end
end

-- Draws the whole frame in room coordinates (the caller has already applied the
-- camera/room offset). `frame` gives the outer rectangle (the canvas edge), the
-- inner rectangle (the floor) and the door opening length; `doors` is a list of
-- { side, color, locked }.
function Renderer:drawRoomFrame(theme, frame, doors)
  if frame.roomId ~= self.doorStateRoom then
    self.doorStates = {} -- new room: doors start in their current state, no animation
    self.doorStateRoom = frame.roomId
  end
  local previousLineWidth = love.graphics.getLineWidth()
  local geometries = {}
  for index, side in ipairs(WALL_SIDES) do
    geometries[side] = bandGeometry(frame, side)
    drawWallBand(theme, geometries[side], side, index)
  end

  -- Mitred corner seams.
  setShaded(theme.mortar, 0.5)
  love.graphics.setLineWidth(3)
  local corners = {
    { frame.outerX, frame.outerY, frame.innerX, frame.innerY },
    { frame.outerX + frame.outerWidth, frame.outerY, frame.innerX + frame.innerWidth, frame.innerY },
    { frame.outerX, frame.outerY + frame.outerHeight, frame.innerX, frame.innerY + frame.innerHeight },
    {
      frame.outerX + frame.outerWidth, frame.outerY + frame.outerHeight,
      frame.innerX + frame.innerWidth, frame.innerY + frame.innerHeight,
    },
  }
  for _, corner in ipairs(corners) do
    love.graphics.line(corner[1], corner[2], corner[3], corner[4])
  end

  for _, door in ipairs(doors or {}) do
    drawWallDoor(self, theme, geometries[door.side], door, frame)
  end

  -- Optional themed glow (embers, sky light) that gently pulses over the stone.
  if theme.glow then
    local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 3)
    love.graphics.setColor(theme.glow[1], theme.glow[2], theme.glow[3], theme.glow[4] * pulse)
    for _, side in ipairs(WALL_SIDES) do
      fillBand(geometries[side], 0, 1, 0, 1)
    end
  end

  -- Soft contact shadow the walls throw onto the floor.
  local ix, iy, iw, ih = frame.innerX, frame.innerY, frame.innerWidth, frame.innerHeight
  for step = 0, 7 do
    local alpha = 0.34 * (1 - step / 8)
    local offset = step * 3
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle('fill', ix, iy + offset, iw, 3)
    love.graphics.rectangle('fill', ix + offset, iy, 3, ih)
    love.graphics.rectangle('fill', ix + iw - offset - 3, iy, 3, ih)
    love.graphics.rectangle('fill', ix, iy + ih - offset - 3, iw, 3)
  end

  love.graphics.setLineWidth(previousLineWidth)
  love.graphics.setColor(1, 1, 1, 1)
end


-- Draws text with a 1 px drop shadow so it stays readable over brick.
local function printShadowed(text, x, y, alpha)
  love.graphics.setColor(0, 0, 0, 0.65 * alpha)
  love.graphics.print(text, x + 1, y + 1)
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.print(text, x, y)
end

-- Everything here floats on the stone walls: hearts top-right, stats hugging the
-- left wall, coins under the hearts, inventory along the bottom wall. Each element
-- is slightly transparent so the bricks stay faintly visible beneath it.
function Renderer:drawHud(player, items)
  local screenWidth, screenHeight = love.graphics.getDimensions()
  local rightEdge = screenWidth - HUD_MARGIN

  -- Hearts: top-right, right-aligned, wrapping after 10 per row.
  local hudScale = snapScale(1.25) -- whole-number scale only
  local heartSize = 32 * hudScale
  local heartSpacing = heartSize + 2
  local heartsPerRow = 10
  local health = math.max(0, player.stats.health)
  local heartCount = math.ceil(math.max(0, player.stats.maxHealth) / 20)
  local firstRowCount = math.min(heartCount, heartsPerRow)
  local heartsLeft = rightEdge - firstRowCount * heartSpacing + (heartSpacing - heartSize)
  local heartsTop = HUD_MARGIN
  love.graphics.setColor(1, 1, 1, HUD_ALPHA)
  for index = 1, heartCount do
    local heartValue = health - (index - 1) * 20
    if heartValue > 0 then
      local quad = heartValue >= 20 and self.heartQuads.full or self.heartQuads.half
      local column = (index - 1) % heartsPerRow
      local row = math.floor((index - 1) / heartsPerRow)
      love.graphics.draw(
        self.heartsImage,
        quad,
        math.floor(heartsLeft + column * heartSpacing),
        math.floor(heartsTop + row * (heartSize + 4)),
        0,
        hudScale,
        hudScale
      )
    end
  end

  -- Coins: right-aligned, directly under the hearts.
  local heartRows = math.max(1, math.ceil(heartCount / heartsPerRow))
  local coinsY = snap(heartsTop + heartRows * (heartSize + 4) + 2)
  local coinsIconScale = snapScale(1.5)
  local coinsText = tostring(player.stats.dollars or 0)
  local coinsGap = 8
  local coinsWidth = self.coinsIcon:getWidth() * coinsIconScale
    + coinsGap + self.coinsFont:getWidth(coinsText)
  local coinsX = snap(rightEdge - coinsWidth)
  love.graphics.setColor(1, 1, 1, HUD_ALPHA)
  love.graphics.draw(self.coinsIcon, coinsX, coinsY, 0, coinsIconScale, coinsIconScale)
  love.graphics.setFont(self.coinsFont)
  printShadowed(
    coinsText,
    snap(coinsX + self.coinsIcon:getWidth() * coinsIconScale + coinsGap),
    snap(coinsY + (self.coinsIcon:getHeight() * coinsIconScale - self.coinsFont:getHeight()) / 2),
    HUD_ALPHA
  )

  -- Stats: a column hugging the left wall, vertically centred. Icon against the
  -- wall edge, value right of it, so the block stays inside the 64 px wall band.
  local stats = {
    { value = function() return tostring(math.floor(player:getDamage())) end, image = self.statImages.damage },
    { value = function() return tostring(math.max(1, math.floor(player.speed / 35))) end, image = self.statImages.speed },
    { value = function() return formatStat(player:getAttackSpeed()) end, image = self.statImages.attackSpeed },
    { value = function() return tostring(math.max(1, math.floor(112 / 112))) end, image = self.statImages.range },
    { value = function() return tostring(player.stats.defense or 0) end, image = self.statImages.defense },
  }
  -- Icons are drawn at their native 32 x 32 (STAT_ICON_SCALE), never shrunk. Rows
  -- without art (e.g. defense) are left out so the column stays vertically centred.
  local visibleStats = {}
  for _, stat in ipairs(stats) do
    if stat.image then
      visibleStats[#visibleStats + 1] = stat
    end
  end
  local statRowHeight = STAT_ICON_SIZE + 4
  local statX = 4
  local statY = snap((screenHeight - #visibleStats * statRowHeight) / 2)
  love.graphics.setFont(self.statFont)
  for _, stat in ipairs(visibleStats) do
    love.graphics.setColor(1, 1, 1, HUD_ALPHA)
    love.graphics.draw(stat.image, statX, statY, 0, STAT_ICON_SCALE, STAT_ICON_SCALE)
    printShadowed(
      stat.value(),
      snap(statX + STAT_ICON_SIZE + 2),
      snap(statY + (STAT_ICON_SIZE - self.statFont:getHeight()) / 2),
      HUD_ALPHA
    )
    statY = statY + statRowHeight
  end

  -- Collected items: bottom-left, over the bottom wall, growing upward.
  local inventory = items:getInventoryItems()
  local iconSize = 28
  local iconSpacing = 34
  local columns = 7
  local inventoryX = HUD_MARGIN + 4
  local inventoryY = screenHeight - HUD_MARGIN - iconSize
  for index, item in ipairs(inventory) do
    if item.image then
      local column = (index - 1) % columns
      local row = math.floor((index - 1) / columns)
      local scale = snapScale(iconSize / math.max(item.image:getWidth(), item.image:getHeight()))
      love.graphics.setColor(1, 1, 1, HUD_ALPHA)
      love.graphics.draw(
        item.image,
        inventoryX + column * iconSpacing,
        inventoryY - row * iconSpacing,
        0,
        scale,
        scale
      )
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Active item: bottom-right corner, over the bottom wall.
function Renderer:drawActiveItem(item, cooldownRemaining)
  if not item or not item.image then
    return
  end

  local screenWidth, screenHeight = love.graphics.getDimensions()
  local iconSize = 64
  local x = screenWidth - HUD_MARGIN - 5 - iconSize
  local y = screenHeight - HUD_MARGIN - 29 - iconSize
  local remaining = math.max(0, cooldownRemaining or 0)
  local cooldown = item.cooldown or 0

  love.graphics.setColor(0.08, 0.045, 0.025, 0.6)
  love.graphics.rectangle('fill', x - 5, y - 5, iconSize + 10, iconSize + 34, 6, 6)
  love.graphics.setColor(1, 1, 1, (remaining > 0 and 0.55 or 1) * HUD_ALPHA)
  local scale = snapScale(iconSize / math.max(item.image:getWidth(), item.image:getHeight()))
  love.graphics.draw(item.image, x, y, 0, scale, scale)
  if remaining > 0 and cooldown > 0 then
    local overlayHeight = iconSize * math.min(1, remaining / cooldown)
    love.graphics.setColor(0.04, 0.035, 0.03, 0.68)
    love.graphics.rectangle('fill', x, y, iconSize, overlayHeight)
  end

  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.98, 0.82, 0.56, HUD_ALPHA)
  love.graphics.printf(
    remaining > 0 and string.format('%.1fs', remaining) or 'READY',
    x - 5,
    y + iconSize + 5,
    iconSize + 10,
    'center'
  )
  love.graphics.setColor(0.9, 0.82, 0.68, HUD_ALPHA)
  love.graphics.printf('Q: USE', x - 5, y + iconSize + 21, iconSize + 10, 'center')
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawPickupNotification(item, elapsed, duration)
  if not item then
    return
  end

  local fadeDuration = 0.35
  local alpha = math.min(1, elapsed / fadeDuration, (duration - elapsed) / fadeDuration)
  alpha = math.max(0, alpha)
  local screenWidth = love.graphics.getWidth()
  local panelWidth = math.min(880, screenWidth - 32)
  local panelX = snap((screenWidth - panelWidth) / 2)
  local textX = panelX + 78
  local textWidth = panelWidth - 96
  local _, lines = self.smallFont:getWrap(item.description or '', textWidth)
  local panelHeight = math.max(96, 48 + #lines * self.smallFont:getHeight())

  love.graphics.setColor(0.035, 0.025, 0.02, 0.92 * alpha)
  love.graphics.rectangle('fill', panelX, 16, panelWidth, panelHeight, 8, 8)
  love.graphics.setColor(0.83, 0.52, 0.2, alpha)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle('line', panelX, 16, panelWidth, panelHeight, 8, 8)

  if item.image then
    local iconSize = 54
    local scale = snapScale(iconSize / math.max(item.image:getWidth(), item.image:getHeight()))
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(
      item.image,
      panelX + 14,
      snap(16 + (panelHeight - iconSize) / 2),
      0,
      scale,
      scale
    )
  end

  love.graphics.setFont(self.bigFont)
  love.graphics.setColor(1, 0.82, 0.45, alpha)
  love.graphics.printf(item.name or 'Item', textX, 24, textWidth, 'left')
  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.95, 0.9, 0.79, alpha)
  love.graphics.printf(item.description or '', textX, 58, textWidth, 'left')
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawMinimap(rooms, currentRoomId, seenRooms, exploredRooms)
  if not rooms or #rooms == 0 then
    return
  end

  -- Top-left, floating on the top and left walls.
  local panelWidth = 176
  local panelHeight = 112
  local panelX = HUD_MARGIN - 4
  local panelY = HUD_MARGIN - 6
  local padding = 12
  local maxDistanceX, maxDistanceY = 0, 0
  for _, room in ipairs(rooms) do
    maxDistanceX = math.max(maxDistanceX, math.abs(room.gridX))
    maxDistanceY = math.max(maxDistanceY, math.abs(room.gridY))
  end

  local gridWidth = math.max(1, maxDistanceX * 2 + 1)
  local gridHeight = math.max(1, maxDistanceY * 2 + 1)
  local cellSize = math.floor(math.min((panelWidth - padding * 2) / gridWidth, (panelHeight - padding * 2) / gridHeight))
  cellSize = math.max(8, math.min(22, cellSize))

  -- With the 16x16 room sprites, one room = one 16px cell drawn at 1x. The
  -- sprites carry their own 1px transparent margin, so neighbors sit 2px apart
  -- with no overlap. The panel grows if a large floor needs more than it holds.
  local useSprites = self.minimapInsideImage ~= nil and self.minimapOutsideImage ~= nil
  if useSprites then
    cellSize = MINIMAP_CELL
    panelWidth = math.max(panelWidth, gridWidth * cellSize + padding * 2)
    panelHeight = math.max(panelHeight, gridHeight * cellSize + padding * 2)
  end

  love.graphics.setColor(0.03, 0.04, 0.05, 0.5)
  love.graphics.rectangle('fill', panelX, panelY, panelWidth, panelHeight)
  love.graphics.setColor(0.65, 0.68, 0.7, 0.35)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle('line', panelX + 0.5, panelY + 0.5, panelWidth - 1, panelHeight - 1)
  love.graphics.setLineWidth(2)

  local function roomPosition(room)
    return panelX + panelWidth / 2 + room.gridX * cellSize,
      panelY + panelHeight / 2 + room.gridY * cellSize
  end

  for _, room in ipairs(rooms) do
    if seenRooms[room.id] then
      local x, y = roomPosition(room)
      for direction, connectedId in pairs(room.connections) do
        if seenRooms[connectedId] then
          local connectedRoom = rooms[connectedId]
          local connectedX, connectedY = roomPosition(connectedRoom)
          love.graphics.setColor(0.65, 0.68, 0.7, 0.65)
          love.graphics.line(math.floor(x), math.floor(y), math.floor(connectedX), math.floor(connectedY))
        end
      end
    end
  end

  for _, room in ipairs(rooms) do
    if seenRooms[room.id] then
      local x, y = roomPosition(room)
      if useSprites then
        local sprite = room.id == currentRoomId and self.minimapInsideImage or self.minimapOutsideImage
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sprite, math.floor(x - MINIMAP_CELL / 2), math.floor(y - MINIMAP_CELL / 2))
      else
        if room.id == currentRoomId then
          love.graphics.setColor(0.95, 0.72, 0.2, 1)
        elseif not exploredRooms[room.id] then
          love.graphics.setColor(0.48, 0.5, 0.53, 0.9)
        elseif room.cleared then
          love.graphics.setColor(0.25, 0.78, 0.42, 0.9)
        elseif room.boss then
          love.graphics.setColor(0.82, 0.25, 0.22, 0.9)
        else
          love.graphics.setColor(0.7, 0.72, 0.75, 0.78)
        end
        love.graphics.rectangle('fill', math.floor(x - cellSize / 2 + 2), math.floor(y - cellSize / 2 + 2), cellSize - 4, cellSize - 4)
      end
    end
  end

  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Matthew's strip frames are 32x32 and drawn at an exact 2x so pixels stay crisp.
-- The sprite is anchored by its feet: cell column 16 sits on the hitbox center
-- and the body's bottom row (27) sits PLAYER_FEET_OFFSET below it.
local PLAYER_SPRITE_SCALE = 2
local PLAYER_FEET_ROW = 27
local PLAYER_FEET_OFFSET = 22

function Renderer:drawPlayer(player, camera)
  local width = player.width
  local height = player.height
  local centerX = player.x - camera.x
  local centerY = player.y - camera.y
  local legacy = self.atlas.layout == 'legacy'
  local scale = legacy and 2 or PLAYER_SPRITE_SCALE
  local spriteSize = legacy and width or self.atlas.frameSize * scale
  local drawX, drawY
  if legacy then
    drawX = math.floor(centerX - width / 2)
    drawY = math.floor(centerY - height / 2)
  else
    drawX = math.floor(centerX - spriteSize / 2)
    drawY = math.floor(centerY + PLAYER_FEET_OFFSET - PLAYER_FEET_ROW * scale)
  end
  local facingLeft = player.facing == 'left'
  local skyForm = self.atlas and self.atlas.imagePath
    and string.find(self.atlas.imagePath, 'matthew-angel.png', 1, true)

  if skyForm then
    local bobAmplitude = 2.4
    local bobSpeed = 4.2
    drawY = snap(drawY + math.sin(love.timer.getTime() * bobSpeed) * bobAmplitude)
  end

  -- A negative scale mirrors around the draw point, so shift mirrored sprites
  -- one sprite width to keep their center in the same place.
  local function mirrorX(mirrored)
    return mirrored and -scale or scale, mirrored and drawX + spriteSize or drawX
  end

  local alpha = 1
  if player.damageInvulnerabilityTimer > 0
      and math.floor(player.damageInvulnerabilityTimer * 16) % 2 == 0 then
    alpha = 0.35
  end
  love.graphics.setColor(1, 1, 1, alpha)
  -- Costume overlays only fit Matthew's own sheet, not Stella's or the angel form.
  local costumable = not skyForm and self.atlas.imagePath
    and string.find(self.atlas.imagePath, 'matthew', 1, true) ~= nil
  local bodyFrame, headFrame = player:getBodyFrame(), player:getHeadFrame()
  -- The 30x28 head is seated on the 17px body so they overlap ~3px at the
  -- collar; the offset (in sprite pixels) scales with the draw scale and
  -- follows the body pose so the head bobs with the walk.
  local headY = drawY + snap(self.atlas:getHeadOffset(bodyFrame) * scale)

  -- Only the side-view body mirrors; front/back bodies are drawn as-is.
  local bodyScaleX, bodyX = mirrorX(facingLeft and (legacy or bodyFrame:find('^walk_right') ~= nil))
  self:drawFrame(bodyFrame, bodyX, drawY, bodyScaleX, scale)
  if costumable then
    self:drawCostumeOverlays(player, bodyFrame, bodyX, drawY, bodyScaleX, scale)
  end
  local headScaleX, headX = mirrorX(legacy and facingLeft or player:isHeadMirrored())
  self:drawFrame(headFrame, headX, headY, headScaleX, scale)
  if costumable then
    self:drawCostumeOverlays(player, headFrame, headX, headY, headScaleX, scale)
  end

  local pickupItem = player.pickupItem
  if pickupItem and pickupItem.image and not legacy then
    -- Collected item floats centered above the (scaled) head and bobs gently.
    local image = pickupItem.image
    local itemScale = snapScale(math.min(scale, 16 * scale / math.max(image:getWidth(), image:getHeight())))
    local bob = math.sin(love.timer.getTime() * 5) * (scale)
    local headTop = headY + 2 * scale -- head art starts on row 2 of its cell
    local itemX = centerX - image:getWidth() * itemScale / 2
    local itemY = headTop - image:getHeight() * itemScale - 3 * scale + bob
    love.graphics.draw(image, snap(itemX), snap(itemY), 0, itemScale, itemScale)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the held Remote with the exact collectible sprite. Resting in the hand
-- between swings, sweeping an arc while a swing is active. Once empowered (30 hits)
-- it gets a slightly yellow tint plus a pulsing additive glow.
function Renderer:drawRemote(player, camera, remote, image)
  if not image then
    return
  end

  local time = love.timer.getTime()
  local playerX = player.x - camera.x
  local playerY = player.y - camera.y
  local swing = remote:getActiveSwing()
  local angle, handX, handY

  if swing then
    local progress = math.min(1, swing.elapsed / swing.duration)
    local eased = 1 - (1 - progress) * (1 - progress)
    local aim = math.atan2(swing.dirY, swing.dirX)
    angle = aim + math.pi / 2 + (-1 + 2 * eased) * REMOTE_SWING_SWEEP
    handX = playerX + swing.dirX * 16
    handY = playerY + 6 + swing.dirY * 12

    -- Faint slash arc that follows the blade.
    love.graphics.setLineWidth(3)
    if remote.empowered then
      love.graphics.setColor(1, 0.92, 0.4, 0.5 * (1 - progress))
    else
      love.graphics.setColor(1, 1, 1, 0.4 * (1 - progress))
    end
    love.graphics.arc(
      'line', 'open', playerX, playerY - 8, remote.REACH * 0.8,
      aim - remote.ARC_HALF, aim - remote.ARC_HALF + 2 * remote.ARC_HALF * eased
    )
    love.graphics.setLineWidth(1)
  else
    local rest = REMOTE_REST[player.facing] or REMOTE_REST.down
    angle = rest.angle
    handX = playerX + rest.x
    handY = playerY + rest.y
  end

  angle = angle + REMOTE_SPRITE_ANGLE
  local originX, originY = image:getWidth() / 2, image:getHeight()
  local drawX, drawY = snap(handX), snap(handY)

  if remote.empowered then
    love.graphics.setColor(1, 0.93, 0.5, 1) -- slightly yellow tint
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.draw(image, drawX, drawY, angle, REMOTE_HELD_SCALE, REMOTE_HELD_SCALE, originX, originY)

  if remote.empowered then
    local pulse = 0.5 + 0.5 * math.sin(time * 6)
    love.graphics.setBlendMode('add')
    love.graphics.setColor(1, 0.9, 0.3, 0.18 + 0.14 * pulse)
    love.graphics.draw(image, drawX, drawY, angle, REMOTE_HELD_SCALE, REMOTE_HELD_SCALE, originX, originY)
    love.graphics.setBlendMode('alpha')
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawFireFoam(player, camera, beam)
  if not player or not camera or not player.foamEquipped or not beam
      or type(beam.distance) ~= 'number' or beam.distance <= 0 then
    return
  end

  local directions = {
    right = { angle = 0, handX = 18, handY = 8 },
    down = { angle = math.pi / 2, handX = 8, handY = 18 },
    left = { angle = math.pi, handX = -18, handY = 8 },
    up = { angle = -math.pi / 2, handX = 8, handY = -18 },
  }
  local direction = directions[beam.direction]
  local spread = self.fireFoamQuads and self.fireFoamQuads['Foam Spread']
  local contact = self.fireFoamQuads and self.fireFoamQuads['Foam Contact']
  if not direction or not self.fireFoamImage or not spread then
    return
  end

  local startX = player.x - camera.x + direction.handX
  local startY = player.y - camera.y + direction.handY
  local segmentLength = 32
  local pulse = (math.sin((beam.animationTime or 0) * 12) + 1) * 0.5
  local beamAlpha = 0.78 + pulse * 0.2

  love.graphics.push()
  love.graphics.translate(startX, startY)
  love.graphics.rotate(direction.angle)
  love.graphics.setColor(1, 1, 1, beamAlpha)

  local segments = math.ceil(beam.distance / segmentLength)
  for index = 0, segments - 1 do
    local x = math.min(index * segmentLength, beam.distance)
    local ripple = math.sin(x * 0.12 - (beam.animationTime or 0) * 10) * 1.5
    love.graphics.draw(
      self.fireFoamImage,
      spread,
      x,
      ripple,
      0,
      1.5,
      1.5,
      0,
      8
    )
  end

  if beam.contact and contact then
    love.graphics.draw(
      self.fireFoamImage,
      contact,
      beam.distance,
      0,
      0,
      1.5,
      1.5,
      16,
      8
    )
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end

function Renderer:drawSweatProjectile(projectile, camera)
  local image = projectile.fire and self.fireSweatImage or self.sweatImage
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    image,
    snap(projectile.x - camera.x),
    snap(projectile.y - camera.y),
    projectile.angle,
    2,
    2,
    image:getWidth() / 2,
    image:getHeight() / 2
  )
end

function Renderer:drawSweatSplash(splash, camera)
  local progress = math.max(0, 1 - splash.elapsed / 0.13)
  local scale = snapScale(2 + progress)
  love.graphics.setColor(1, 1, 1, progress)
  love.graphics.draw(
    self.sweatSplashImage,
    math.floor(splash.x - camera.x),
    math.floor(splash.y - camera.y),
    0,
    scale,
    scale,
    self.sweatSplashImage:getWidth() / 2,
    self.sweatSplashImage:getHeight() / 2
  )
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws every active costume sheet with the SAME frame (and therefore the same
-- animation frame and facing) as the base sprite, on top of it.
function Renderer:drawCostumeOverlays(player, frameName, x, y, scaleX, scaleY)
  for _, costume in ipairs(COSTUMES) do
    local image = self.costumeImages[costume.evolution]
    -- Costume sheets must share the new 832x32 strip layout; older 40x40
    -- costume sheets are skipped until they are redrawn.
    if image and self.atlas:matchesLayout(image) and player:hasEvolution(costume.evolution) then
      self:drawFrame(frameName, x, y, scaleX, scaleY, image)
    end
  end
end

function Renderer:drawFrame(frameName, x, y, scaleX, scaleY, image)
  local frame = self.atlas:getFrame(frameName)
  if not frame then
    return
  end

  love.graphics.draw(image or self.atlas.image, frame.quad, snap(x), snap(y), 0, snapScale(scaleX), snapScale(scaleY))
end

return Renderer