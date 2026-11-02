-- Player rendering. Atlas loading belongs in atlas.lua.
---@diagnostic disable: undefined-global
local LilSnake = require('lil_snake')
local Json = require('json')
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

function Renderer.new(atlas)
  LilSnake.load()
  local renderer = setmetatable({ atlas = atlas }, Renderer)
  renderer.enemyImage = love.graphics.newImage('resources/gfx/enemies/spritesheets/entity_002_scar.png')
  renderer.spiderImage = love.graphics.newImage('resources/gfx/enemies/spritesheets/entity_001_spider.png')
  renderer.centipedeImage = love.graphics.newImage('resources/gfx/enemies/spritesheets/enemies_004_centipede.png')
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
    defense = love.graphics.newImage('resources/gfx/ui/stats/stats_005_defense.png'),
  }
  for _, image in pairs(renderer.statImages) do
    image:setFilter('nearest', 'nearest')
  end
  renderer.bigFont = love.graphics.newFont('resources/font/bigfont.ttf', 24)
  renderer.floorIntroFont = love.graphics.newFont('resources/font/bigfont.ttf', 48)
  renderer.smallFont = love.graphics.newFont('resources/font/smallfont.ttf', 14)
  renderer.hudFont = love.graphics.newFont('resources/font/smallfont.ttf', 20)
  renderer.coinsFont = love.graphics.newFont('resources/font/smallfont.ttf', 28)
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
  local y = love.graphics.getHeight() - 42
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
    local cardX = math.floor(cardCenterX - currentCardWidth / 2)
    local cardY = math.floor((height - currentCardHeight) / 2 + 12)
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
      local imageScale = focused and math.min(
        4,
        currentCardWidth * 0.34 / imageWidth,
        currentCardHeight * 0.36 / imageHeight
      ) or math.min(
        2.8,
        currentCardWidth * 0.32 / imageWidth,
        currentCardHeight * 0.3 / imageHeight
      )
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
      local statIconSize = 18
      local statGap = 10
      local statTextGap = 8
      local statsX = cardX + currentCardWidth * 0.12
      local statsY = cardY + currentCardHeight * 0.6
      local rowEntries = {}

      for _, stat in ipairs(stats) do
        local valueText = tostring(stat.value)
        rowEntries[#rowEntries + 1] = {
          image = stat.image,
          value = valueText,
          quad = stat.quad,
          width = statIconSize + statTextGap + self.smallFont:getWidth(valueText),
        }
      end

      local dividerY = cardY + currentCardHeight * 0.57
      love.graphics.setColor(0.95, 0.58, 0.18, 0.5)
      love.graphics.rectangle(
        'fill',
        cardX + currentCardWidth * 0.1,
        dividerY,
        currentCardWidth * 0.8,
        1.5
      )

      local x = statsX
      local y = statsY + 4
      for _, stat in ipairs(rowEntries) do
        love.graphics.setColor(1, 1, 1, 1)
        if stat.quad then
          love.graphics.draw(stat.image, stat.quad, math.floor(x), math.floor(y), 0, 1, 1)
        else
          love.graphics.draw(stat.image, math.floor(x), math.floor(y), 0, 1, 1)
        end
        love.graphics.setColor(1, 0.79, 0.42, 1)
        love.graphics.print(stat.value, math.floor(x + statIconSize + statTextGap), math.floor(y + 1))
        x = x + stat.width + statGap
      end
    end
  end

  love.graphics.setLineWidth(1)
  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.68, 0.55, 0.39, 0.9)
  love.graphics.printf('LEFT / RIGHT - CHOOSE     ENTER - BEGIN     F7 - BOSS DEBUG', 0, height - 44, width, 'center')
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

  if enemy.kind == 'spider' then
    local spiderFrame = math.floor(enemy.animationTime / 0.1) % 2 + 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.spiderImage, self.spiderQuads[spiderFrame], math.floor(enemy.x - camera.x), math.floor(enemy.y - camera.y), 0, 2, 2, 32, 32)
    return
  end

  if enemy.kind == 'centipede' then
    local scale = (enemy.scale or 1) * 2
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
    scale = 3.2
  elseif crawler.phaseState == 'charging' then
    local pulse = (math.sin(crawler.animationTime * 12) + 1) * 0.2
    love.graphics.setColor(1, 0.25 + pulse, 0.08, 1)
    scale = 3.3
  elseif crawler.phaseState == 'wall_running' then
    love.graphics.setColor(1, 0.18, 0.08, 1)
    scale = 3.15
  elseif crawler.phaseState == 'exhausted' then
    love.graphics.setColor(0.48, 0.72, 1, 1)
    scale = 2.7
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

function Renderer:drawHud(player, items)
  local hudScale = 1.25
  local heartSpacing = 34 * hudScale
  local statRowSpacing = 36 * hudScale
  local statIconSize = 32 * hudScale
  local health = math.max(0, player.stats.health)
  local maxHealth = math.max(0, player.stats.maxHealth)
  local heartCount = math.ceil(maxHealth / 20)

  local hudTop = math.floor(math.max(24, love.graphics.getHeight() / 2 - 178))
  local hudX = 24

  love.graphics.setColor(1, 1, 1, 1)
  for index = 1, heartCount do
    local heartValue = health - (index - 1) * 20
    local quad = heartValue >= 20 and self.heartQuads.full or self.heartQuads.half
    if heartValue > 0 then
      love.graphics.draw(
        self.heartsImage,
        quad,
        math.floor(hudX + (index - 1) * heartSpacing),
        hudTop,
        0,
        hudScale,
        hudScale
      )
    end
  end

  local minimapX = love.graphics.getWidth() - 220 - 16
  local minimapWidth = 220
  local minimapBottom = 16 + 172
  local coinsY = minimapBottom + 8
  local coinsIconScale = 1.5
  local coinsText = tostring(player.stats.dollars or 0)
  local coinsGap = 8
  local coinsWidth = self.coinsIcon:getWidth() * coinsIconScale
    + coinsGap + self.coinsFont:getWidth(coinsText)
  local coinsX = minimapX + (minimapWidth - coinsWidth) / 2
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.coinsIcon, coinsX, coinsY, 0, coinsIconScale, coinsIconScale)
  love.graphics.setFont(self.coinsFont)
  love.graphics.print(
    coinsText,
    coinsX + self.coinsIcon:getWidth() * coinsIconScale + coinsGap,
    coinsY + (self.coinsIcon:getHeight() * coinsIconScale - self.coinsFont:getHeight()) / 2
  )
  love.graphics.setFont(self.hudFont)
  local stats = {
    { key = 'damage', value = function() return tostring(math.max(1, math.floor(player.stats.damage / 20))) end, image = self.statImages.damage },
    { key = 'speed', value = function() return tostring(math.max(1, math.floor(player.speed / 35))) end, image = self.statImages.speed },
    { key = 'attackSpeed', value = function() return formatStat((player.stats.attackSpeed or 1) / 1) end, image = self.statImages.attackSpeed },
    { key = 'range', value = function() return tostring(math.max(1, math.floor(112 / 112))) end, image = self.statImages.range },
    { key = 'defense', value = function() return tostring(player.stats.defense or 0) end, image = self.statImages.defense },
  }
  local statsY = hudTop + 64
  local statIconSize = 18
  local statColor = { 1, 0.86, 0.52 }
  local rowGap = 18
  local statX = hudX + 8
  local statY = statsY
  love.graphics.setFont(self.hudFont)

  for _, stat in ipairs(stats) do
    local image = stat.image
    if image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, math.floor(statX), math.floor(statY), 0, 1, 1)
      love.graphics.setColor(statColor[1], statColor[2], statColor[3], 1)
      love.graphics.print(tostring(stat.value()), math.floor(statX + statIconSize + 10), math.floor(statY + 1))
      statY = statY + rowGap + 12
    end
  end
  local inventory = items:getInventoryItems()
  local iconSize = 28
  local iconSpacing = 34
  local columns = math.max(1, math.floor((love.graphics.getWidth() - hudX * 2) / iconSpacing))
  local inventoryY = love.graphics.getHeight() - iconSize - 12
  for index, item in ipairs(inventory) do
    if item.image then
      local column = (index - 1) % columns
      local row = math.floor((index - 1) / columns)
      local scale = iconSize / math.max(item.image:getWidth(), item.image:getHeight())
      love.graphics.setColor(1, 1, 1, 0.9)
      love.graphics.draw(
        item.image,
        hudX + column * iconSpacing,
        inventoryY - row * iconSpacing,
        0,
        scale,
        scale
      )
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:drawActiveItem(item, cooldownRemaining)
  if not item or not item.image then
    return
  end

  local iconSize = 64
  local padding = 16
  local x = love.graphics.getWidth() - iconSize - padding
  local y = padding
  local remaining = math.max(0, cooldownRemaining or 0)
  local cooldown = item.cooldown or 0

  love.graphics.setColor(0.08, 0.045, 0.025, 0.9)
  love.graphics.rectangle('fill', x - 5, y - 5, iconSize + 10, iconSize + 34, 6, 6)
  love.graphics.setColor(1, 1, 1, remaining > 0 and 0.55 or 1)
  local scale = iconSize / math.max(item.image:getWidth(), item.image:getHeight())
  love.graphics.draw(item.image, x, y, 0, scale, scale)
  if remaining > 0 and cooldown > 0 then
    local overlayHeight = iconSize * math.min(1, remaining / cooldown)
    love.graphics.setColor(0.04, 0.035, 0.03, 0.68)
    love.graphics.rectangle('fill', x, y, iconSize, overlayHeight)
  end

  love.graphics.setFont(self.smallFont)
  love.graphics.setColor(0.98, 0.82, 0.56, 1)
  love.graphics.printf(
    remaining > 0 and string.format('%.1fs', remaining) or 'READY',
    x - 5,
    y + iconSize + 5,
    iconSize + 10,
    'center'
  )
  love.graphics.setColor(0.9, 0.82, 0.68, 0.9)
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
  local panelX = (screenWidth - panelWidth) / 2
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
    local scale = iconSize / math.max(item.image:getWidth(), item.image:getHeight())
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(
      item.image,
      panelX + 14,
      16 + (panelHeight - iconSize) / 2,
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

  local screenWidth = love.graphics.getWidth()
  local panelWidth = 220
  local panelHeight = 172
  local panelX = screenWidth - panelWidth - 16
  local panelY = 16
  local padding = 14
  local maxDistanceX, maxDistanceY = 0, 0
  for _, room in ipairs(rooms) do
    maxDistanceX = math.max(maxDistanceX, math.abs(room.gridX))
    maxDistanceY = math.max(maxDistanceY, math.abs(room.gridY))
  end

  local gridWidth = math.max(1, maxDistanceX * 2 + 1)
  local gridHeight = math.max(1, maxDistanceY * 2 + 1)
  local cellSize = math.floor(math.min((panelWidth - padding * 2) / gridWidth, (panelHeight - padding * 2) / gridHeight))
  cellSize = math.max(8, math.min(22, cellSize))

  love.graphics.setColor(0.03, 0.04, 0.05, 0.72)
  love.graphics.rectangle('fill', panelX, panelY, panelWidth, panelHeight)
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

  love.graphics.setLineWidth(1)
end

function Renderer:drawPlayer(player, camera)
  local width = player.width
  local height = player.height
  local drawX = math.floor(player.x - camera.x - width / 2)
  local drawY = math.floor(player.y - camera.y - height / 2)
  local scale = 2
  local scaleX = player.facing == 'left' and -scale or scale
  local skyForm = self.atlas and self.atlas.imagePath
    and string.find(self.atlas.imagePath, 'matthew-angel.png', 1, true)

  if skyForm then
    local bobAmplitude = 2.4
    local bobSpeed = 4.2
    drawY = drawY + math.sin(love.timer.getTime() * bobSpeed) * bobAmplitude
  end

  -- A negative scale mirrors around the draw point, so move left-facing
  -- sprites one width to keep their center in the same place.
  if scaleX < 0 then
    drawX = drawX + width
  end

  local alpha = 1
  if player.damageInvulnerabilityTimer > 0
      and math.floor(player.damageInvulnerabilityTimer * 16) % 2 == 0 then
    alpha = 0.35
  end
  love.graphics.setColor(1, 1, 1, alpha)
  self:drawFrame(player:getBodyFrame(), drawX, drawY, scaleX, scale)
  if not player.isHurt then
    self:drawFrame(player:getHeadFrame(), drawX, drawY, scaleX, scale)
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
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    self.sweatImage,
    math.floor(projectile.x - camera.x),
    math.floor(projectile.y - camera.y),
    projectile.angle,
    2,
    2,
    self.sweatImage:getWidth() / 2,
    self.sweatImage:getHeight() / 2
  )
end

function Renderer:drawSweatSplash(splash, camera)
  local progress = math.max(0, 1 - splash.elapsed / 0.13)
  local scale = 2 + progress
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

function Renderer:drawFrame(frameName, x, y, scaleX, scaleY)
  local frame = self.atlas.frames[frameName]
  if not frame then
    return
  end

  love.graphics.draw(self.atlas.image, frame.quad, math.floor(x), math.floor(y), 0, scaleX, scaleY)
end

return Renderer