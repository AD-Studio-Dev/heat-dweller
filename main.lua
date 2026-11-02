---@diagnostic disable: undefined-global
local Atlas = require('atlas')
local Input = require('input')
local MainMenu = require('mainmenu')
local Items = require('items')
local Player = require('player')
local Renderer = require('renderer')
local Enemy = require('enemy')
local Scar = require('scar')
local Spider = require('spider')
local Fly = require('fly')
local Centipede = require('centipede')
local Crawler = require('crawler')
local LilSnake = require('lil_snake')
local TheGeometric = require('the_geometric')
local TheStuffing = require('the_stuffing')
local BabyWidow = require('baby_widow')
local AcidProjectile = require('acid_projectile')
local SweatProjectile = require('sweat_projectile')
local Rooms = require('rooms')
local Json = require('json')
local FireFoam = require('firefoam')

local SAVE_FILE = 'heat_dweller_run.json'
local PROFILE_FILE = 'heat_dweller_profile.json'
local FLOOR_TYPES = Rooms.floorTypes
local FLOOR_NAME_LABELS = {
  basement = 'BASEMENT',
  living_room = 'LIVING ROOM',
  kitchen = 'KITCHEN',
  bedroom = 'BEDROOM',
  attic = 'ATTIC',
  roof = 'ROOF',
  sky = 'THE SKY',
}
local currentFloorDisplayName = 'BASEMENT'
local currentFloorBannerTimer = 0
local FLOOR_PALETTES = {
  basement = { base = { 0.09, 0.095, 0.1 }, tile = { 0.14, 0.148, 0.152 } },
  living_room = { base = { 0.28, 0.16, 0.14 }, tile = { 0.34, 0.19, 0.16 } },
  kitchen = { base = { 0.19, 0.2, 0.16 }, tile = { 0.28, 0.29, 0.23 } },
  bedroom = { base = { 0.19, 0.13, 0.22 }, tile = { 0.27, 0.18, 0.3 } },
  attic = { base = { 0.2, 0.16, 0.11 }, tile = { 0.29, 0.23, 0.15 } },
  roof = { base = { 0.13, 0.19, 0.25 }, tile = { 0.18, 0.27, 0.35 } },
  sky = { base = { 0.13, 0.24, 0.32 }, tile = { 0.19, 0.34, 0.43 } },
}
local saveRun
local continueRun
local loadFloor
local input
local player
local renderer
local mainMenu
local menuSwitchSound
local menuSelectSound
local menuCancelSound
local items
local fireFoam = FireFoam.new()
local enemies
local world
local menuMusic
local audioMusicVolume = 0.5
local audioSfxVolume = 1
local audioSfxSources = setmetatable({}, { __mode = 'k' })
local menuMusicFade
local menuMusicActive
local updateMainMenuMusic
local backgroundMusic
local basementOscMusic
local basementMusicFade
local kitchenMusic
local kitchenMusicFade
local skyMusic
local skyMusicFade
local floorTransitionSound
local bossIntroMusic
local bossActiveStartMusic
local bossLoopMusic
local bossMusicPhase
local bossMusicCrossfadeDuration = 0.2
local waitingForPickupSound
local roomRewardSpawned
local roomIndex
local currentRoom
local rooms
local runSeed
local autosaveTimer
local exploredRooms
local seenRooms
local ladder
local ladderImage
local deathScreenImage
local bossDeathParticles = {}
local doorsLocked
local gameState
local crawler
local lilSnake
local geometric
local stuffing
local babyWidow
local acidProjectiles
local sweatProjectiles = {}
local sweatSplashes = {}
local activeFireZones = {}
local snowmanArmedTimer = 0
local snowmanFamiliarTimer = 0
local snowmanShotTimer = 0
local floorTransitionTimer
local floorTransitionDuration = 2.4
local floorTransitionFadeDuration = 0.45
local floorTransitionTargetIndex
local floorTransitionFloorName
local floorTransitionLoaded
local floorTransitionSoundDuration
local screenShakeTime
local screenShakeDuration = 0.2
local screenShakeStrength
local screenShakeEnabled = true
local openingCutscene
local cutsceneFallbackTimer = 0
local cutsceneFallbackDuration = 3
local profile = { runsStarted = 0, bossesDefeated = 0, itemCounts = {} }
local spiderSpawnTimer
local bossIntroTimer
local bossIntroType
local bossDefeated
local isAudioLocked = false
local isPickingUpItem
local pickupTimer
local pickupNotification
local pickupNotificationElapsed
local pickupNotificationDuration = 3.4
local matthewHurtSounds
local babyWidowSounds
local bossDefeatSound
local shopOffers
local cultistOffer
local cultistChoiceActive
local cultistCardImages
local selectedCharacter
local characterIndex
local characterCarouselPosition = 1
local characterCarouselTarget = 1
local bossDebugMenuOpen = false
local bossDebugSelection = 1
local debugBosses = {
  { name = 'The Crawler', type = 'crawler', floorIndex = 1 },
  { name = "Lil' Snake", type = 'lilsnake', floorIndex = 2 },
  { name = 'The Geometric', type = 'geometric', floorIndex = 3 },
  { name = 'The Stuffing', type = 'stuffing', floorIndex = 4 },
}
local characters = {
  {
    name = 'Matthew',
    subtitle = 'The determined dweller',
    isUnlocked = true,
    imagePath = 'resources/sprites/characters/character_001_matthew.png',
    spriteSheetPath = 'resources/gfx/characters/character_001_matthew.png',
  },
  {
    name = 'Stella',
    subtitle = 'The bright survivor',
    isUnlocked = false,
    imagePath = 'resources/sprites/characters/character_002_stella.png',
  },
}

local function getFloorDisplayName(floorType)
  if not floorType then
    return currentFloorDisplayName or 'BASEMENT'
  end
  return FLOOR_NAME_LABELS[floorType] or string.upper((tostring(floorType):gsub('_', ' ')))
end

local function floorTypeForIndex(index)
  return FLOOR_TYPES[index]
end

local function generateCurrentFloorRooms(seed)
  local floorType = floorTypeForIndex(world.floorIndex)
  assert(floorType and floorType == world.floorType,
    'Current floor index does not match its floor type.')
  return Rooms.generate(15, floorType, seed, world.floorIndex)
end

local function setFloorMusicVolume()
  if backgroundMusic then
    local intensity = 0.75 + math.max(0, (world and world.floorIndex or 1) - 1) * 0.04
    backgroundMusic:setVolume(audioMusicVolume * math.min(1, intensity))
  end
end

local function registerSfxSource(source)
  audioSfxSources[source] = true
  source:setVolume(audioSfxVolume)
  return source
end

local function hardStopMusicSources()
  local sources = {
    menuMusic,
    backgroundMusic,
    basementOscMusic,
    kitchenMusic,
    skyMusic,
    bossIntroMusic,
    bossActiveStartMusic,
    bossLoopMusic,
  }

  for _, source in ipairs(sources) do
    if source then
      source:stop()
      source:setVolume(0)
    end
  end
end

local function unlockBossRoom()
  if not currentRoom then
    return
  end

  currentRoom.dealUnlocked = true
  currentRoom.cleared = true
  doorsLocked = false

  if currentRoom.doors then
    for _, door in pairs(currentRoom.doors) do
      door.locked = false
    end
  end

  if currentRoom.boss and not ladder and world.floorIndex < #FLOOR_TYPES then
    ladder = { x = 104, y = 104 }
  end

  if currentRoom.boss and not roomRewardSpawned then
    items:spawnFloorReward(world.width / 2, world.height / 2)
    roomRewardSpawned = true
  end
end

local function saveProfile()
  local encodedSuccessfully, encoded = pcall(Json.encode, profile)
  if not encodedSuccessfully then
    print('Profile save failed: ' .. tostring(encoded))
    return false
  end
  local success, writeError = love.filesystem.write(PROFILE_FILE, encoded)
  if not success then
    print('Profile save failed: ' .. tostring(writeError))
    return false
  end
  return true
end

local function loadProfile()
  local contents, readError = love.filesystem.read(PROFILE_FILE)
  if not contents then
    if love.filesystem.getInfo(PROFILE_FILE) then
      print('Profile load failed: ' .. tostring(readError))
    end
    return
  end

  local decoded, savedProfile = pcall(Json.decode, contents)
  if not decoded or type(savedProfile) ~= 'table' then
    print('Profile load failed: ' .. tostring(savedProfile))
    return
  end
  profile.runsStarted = math.max(0, tonumber(savedProfile.runsStarted) or 0)
  profile.bossesDefeated = math.max(0, tonumber(savedProfile.bossesDefeated) or 0)
  profile.itemCounts = {}
  for _, entry in ipairs(type(savedProfile.itemCounts) == 'table' and savedProfile.itemCounts or {}) do
    if type(entry) == 'table' and tonumber(entry.id) and tonumber(entry.count) then
      profile.itemCounts[#profile.itemCounts + 1] = {
        id = tonumber(entry.id),
        count = math.max(0, tonumber(entry.count)),
      }
    end
  end
  audioMusicVolume = math.max(0, math.min(1, tonumber(savedProfile.musicVolume) or audioMusicVolume))
  audioSfxVolume = math.max(0, math.min(1, tonumber(savedProfile.sfxVolume) or audioSfxVolume))
  screenShakeEnabled = savedProfile.screenShakeEnabled ~= false
end

local function updatePlayerSpriteForFloor()
  if not renderer or not selectedCharacter or selectedCharacter.name ~= 'Matthew' then
    return
  end

  local standardPath = selectedCharacter.spriteSheetPath or 'resources/gfx/characters/character_001_matthew.png'
  local activePath = world and world.floorType == 'sky'
      and 'resources/gfx/characters/character_001_matthew-angel.png'
      or standardPath

  if love.filesystem.getInfo(activePath) then
    renderer:setCharacter(activePath)
  elseif love.filesystem.getInfo(standardPath) then
    renderer:setCharacter(standardPath)
  end
end

local function setAudioSettings(musicVolume, sfxVolume, shakeEnabled)
  audioMusicVolume = musicVolume
  audioSfxVolume = sfxVolume
  screenShakeEnabled = shakeEnabled
  for source in pairs(audioSfxSources) do
    source:setVolume(audioSfxVolume)
  end
  if menuMusic then
    menuMusic:setVolume(audioMusicVolume)
    if menuMusicFade and gameState == 'title' then
      menuMusicFade = nil
    end
  end
  setFloorMusicVolume()
  if bossIntroMusic then bossIntroMusic:setVolume(audioMusicVolume) end
  if bossActiveStartMusic then bossActiveStartMusic:setVolume(audioMusicVolume) end
  if bossLoopMusic then bossLoopMusic:setVolume(audioMusicVolume) end
  if basementOscMusic then basementOscMusic:setVolume(audioMusicVolume) end
  if kitchenMusic then kitchenMusic:setVolume(audioMusicVolume) end
  if skyMusic then skyMusic:setVolume(audioMusicVolume) end
  profile.musicVolume = audioMusicVolume
  profile.sfxVolume = audioSfxVolume
  profile.screenShakeEnabled = screenShakeEnabled
  saveProfile()
end

local function refreshMenuExtras()
  if not mainMenu then
    return
  end
  local discoveredItems = {}
  local favoriteName
  local favoriteCount = 0
  for _, entry in ipairs(profile.itemCounts) do
    local definition = items and items.definitions[entry.id]
    if definition then
      discoveredItems[#discoveredItems + 1] = definition.name
      if entry.count > favoriteCount then
        favoriteName = definition.name
        favoriteCount = entry.count
      end
    end
  end
  table.sort(discoveredItems)
  mainMenu:setExtrasData({
    runsStarted = profile.runsStarted,
    bossesDefeated = profile.bossesDefeated,
    favoriteItem = favoriteName or 'NONE YET',
    discoveredItems = discoveredItems,
  })
end

local function initializeItems()
  items = Items.new()
  items.pickupSound = registerSfxSource(items.pickupSound)
  items.onAcquired = function(definition)
    local entry
    for _, itemCount in ipairs(profile.itemCounts) do
      if itemCount.id == definition.id then
        entry = itemCount
        break
      end
    end
    if entry then
      entry.count = entry.count + 1
    else
      profile.itemCounts[#profile.itemCounts + 1] = { id = definition.id, count = 1 }
    end
    saveProfile()
    refreshMenuExtras()
  end
  refreshMenuExtras()
end

local function finishOpeningCutscene()
  if openingCutscene then
    openingCutscene:pause()
    openingCutscene = nil
  end
  cutsceneFallbackTimer = 0
  gameState = 'title'
end

local function loadOpeningCutscene()
  local path = 'resources/gfx/cutscenes/mainmenucutscene.ogv'
  if love.filesystem.getInfo(path) then
    local loaded, video = pcall(function()
      local cutscene = love.graphics.newVideo(path, { audio = true })
      cutscene:play()
      return cutscene
    end)
    if loaded then
      openingCutscene = video
      gameState = 'opening_cutscene'
      return
    end
    print('Unable to load or play main menu cutscene: ' .. tostring(video))
  end
  openingCutscene = nil
  cutsceneFallbackTimer = 0
  gameState = 'cutscene_fallback'
end

local function createMenuTone(startFrequency, endFrequency, duration)
  local sampleRate = 22050
  local sampleCount = math.floor(sampleRate * duration)
  local soundData = love.sound.newSoundData(sampleCount, sampleRate, 16, 1)

  for sample = 0, sampleCount - 1 do
    local progress = sample / sampleCount
    local frequency = startFrequency + (endFrequency - startFrequency) * progress
    local envelope = (1 - progress) ^ 2
    local value = math.sin(2 * math.pi * frequency * sample / sampleRate) * envelope * 0.28
    soundData:setSample(sample, 1, value)
  end

  return registerSfxSource(love.audio.newSource(soundData, 'static'))
end

local function createBossDefeatTone()
  local sampleRate = 22050
  local sampleCount = math.floor(sampleRate * 0.8)
  local soundData = love.sound.newSoundData(sampleCount, sampleRate, 16, 1)

  for sample = 0, sampleCount - 1 do
    local progress = sample / sampleCount
    local frequency = 180 - (180 * progress)
    local envelope = math.max(0, 1 - progress)
    local value = math.sin(2 * math.pi * frequency * sample / sampleRate) * envelope * 0.46
    soundData:setSample(sample, 1, value)
  end

  return registerSfxSource(love.audio.newSource(soundData, 'static'))
end

local function updateCameraSize()
  world.camera.width = love.graphics.getWidth()
  world.camera.height = love.graphics.getHeight()
end

local function resetPlayer()
  player = Player.new({
    startX = world.width / 2,
    startY = world.height / 2,
    width = 64,
    height = 64,
    speed = 350,
    currentFloorType = world.floorType,
    onShootSweat = function(directionX, directionY)
      if selectedCharacter and selectedCharacter.name == 'Matthew' then
        sweatProjectiles[#sweatProjectiles + 1] = SweatProjectile.new(
          player.x,
          player.y,
          directionX,
          directionY
        )
      end
    end,
  })
  player.onDamaged = function()
    if matthewHurtSounds and #matthewHurtSounds > 0 then
      local hurtSound = matthewHurtSounds[math.random(#matthewHurtSounds)]
      hurtSound:setPitch(love.math.random(92, 108) / 100)
      hurtSound:play()
    end
    triggerScreenShake(math.random(4, 6))
    if snowmanArmedTimer and snowmanArmedTimer > 0 then
      snowmanArmedTimer = 0
      snowmanFamiliarTimer = 5
      snowmanShotTimer = 0
    end
  end
end

local function resetPlayerRunState()
  world.floorIndex = 1
  world.floorType = floorTypeForIndex(world.floorIndex)
  world.roomType = world.floorType
  world.camera.x = 0
  world.camera.y = 0
  runSeed = nil
  autosaveTimer = 0

  resetPlayer()
  sweatProjectiles = {}
  sweatSplashes = {}
  initializeItems()
  fireFoam = FireFoam.new()
  rooms = {}
  roomIndex = 1
  currentRoom = nil
  enemies = {}
  crawler = nil
  lilSnake = nil
  geometric = nil
  stuffing = nil
  babyWidow = nil
  acidProjectiles = {}
  activeFireZones = {}
  snowmanArmedTimer = 0
  snowmanFamiliarTimer = 0
  snowmanShotTimer = 0
  exploredRooms = {}
  seenRooms = {}
  ladder = nil
  bossDeathParticles = {}
  doorsLocked = true
  roomRewardSpawned = false
  bossDefeated = false
  spiderSpawnTimer = 0
  bossIntroTimer = 0
  bossIntroType = nil
  floorTransitionTimer = nil
  floorTransitionTargetIndex = nil
  floorTransitionFloorName = nil
  floorTransitionLoaded = nil
  screenShakeTime = 0
  screenShakeStrength = 0
  isPickingUpItem = false
  pickupTimer = 0
  pickupNotification = nil
  pickupNotificationElapsed = 0
  waitingForPickupSound = false
  shopOffers = nil
  cultistOffer = nil
  cultistChoiceActive = false
end

local function clearSavedRun()
  if not love.filesystem.getInfo(SAVE_FILE) then
    mainMenu.hasSave = false
    return true
  end

  local removed, removeError = love.filesystem.remove(SAVE_FILE)
  if not removed then
    return false, 'Unable to clear the previous run save: ' .. tostring(removeError)
  end
  mainMenu.hasSave = false
  return true
end

local function beginNewRunSelection()
  local cleared, clearError = clearSavedRun()
  if not cleared then
    mainMenu.message = clearError
    print(clearError)
    return false
  end
  mainMenu.message = nil
  mainMenu:setScreen('character_select')
  gameState = 'character_select'
  return true
end

local function restartRunAfterDeath()
  runSeed = love.math.random(1, 9999999)
  if not runSeed or type(runSeed) ~= 'number' then
    runSeed = math.floor((love.timer.getTime() or 0) * 10000)
  end

  hardStopMusicSources()
  bossIntroMusic:stop()
  bossActiveStartMusic:stop()
  bossLoopMusic:stop()
  bossMusicPhase = nil
  stopBasementMusic(false)
  stopKitchenMusic(false)
  stopSkyMusic(false)
  if backgroundMusic then
    backgroundMusic:stop()
    backgroundMusic:setVolume(0)
  end
  resetPlayerRunState()
  if selectedCharacter and selectedCharacter.spriteSheetPath then
    renderer:setCharacter(selectedCharacter.spriteSheetPath)
  end
  updatePlayerSpriteForFloor()
  local loaded, loadError = loadFloor(1)
  if not loaded then
    print('Unable to restart run after death: ' .. tostring(loadError))
    return false
  end
  gameState = 'playing'
  return true
end

local function initializeProfileAndItems()
  loadProfile()
  initializeItems()
end

local function initializeAudio()
  matthewHurtSounds = {
    registerSfxSource(love.audio.newSource('resources/music/sfx/matthewhurt1.wav', 'static')),
    registerSfxSource(love.audio.newSource('resources/music/sfx/matthewhurt2.wav', 'static')),
    registerSfxSource(love.audio.newSource('resources/music/sfx/matthewhurt3.wav', 'static')),
    registerSfxSource(love.audio.newSource('resources/music/sfx/matthewhurt4.wav', 'static')),
  }
  babyWidowSounds = {
    enter = registerSfxSource(love.audio.newSource('resources/music/sfx/baby widow enter stage.wav', 'static')),
    summon = registerSfxSource(love.audio.newSource('resources/music/sfx/baby widow summon.wav', 'static')),
    -- TODO: Use inhale/throwup for a defined Baby Widow attack telegraph/release.
    inhale = registerSfxSource(love.audio.newSource('resources/music/sfx/baby widow inhale.wav', 'static')),
    throwup = registerSfxSource(love.audio.newSource('resources/music/sfx/baby widow throwup.wav', 'static')),
    coughing = registerSfxSource(love.audio.newSource('resources/music/sfx/baby widow coughing.wav', 'static')),
    death = registerSfxSource(love.audio.newSource('resources/music/sfx/baby widow death.wav', 'static')),
  }
  local musicPath = 'resources/music/music/backgroundmusic.ogg'
  if not love.filesystem.getInfo(musicPath) then
    musicPath = 'resources/music/music/resources_music_music_song(2).ogg'
  end
  backgroundMusic = love.audio.newSource(musicPath, 'stream')
  backgroundMusic:setLooping(true)
  setFloorMusicVolume()
  backgroundMusic:play()
  backgroundMusic:pause()
  menuMusic = love.audio.newSource('resources/music/music/mainmenumusic.ogg', 'stream')
  menuMusic:setLooping(true)
  menuMusic:setVolume(0)
  menuMusic:stop()
  menuMusicActive = false
  basementOscMusic = love.audio.newSource('resources/music/music/basement/basementsong.ogg', 'stream')
  basementOscMusic:setLooping(true)
  basementOscMusic:setVolume(0)
  basementOscMusic:stop()
  kitchenMusic = love.audio.newSource('resources/music/music/kitchen/kitchensong.ogg', 'stream')
  kitchenMusic:setLooping(true)
  kitchenMusic:setVolume(0)
  kitchenMusic:stop()
  skyMusic = love.audio.newSource('resources/music/music/thesky/theskysong.ogg', 'stream')
  skyMusic:setLooping(true)
  skyMusic:setVolume(0)
  skyMusic:stop()
  bossIntroMusic = love.audio.newSource('resources/music/music/bossfightstart.ogg', 'stream')
  bossIntroMusic:setLooping(false)
  bossIntroMusic:setVolume(audioMusicVolume)
  bossActiveStartMusic = love.audio.newSource('resources/music/music/bossfightactivestart.ogg', 'stream')
  bossActiveStartMusic:setLooping(false)
  bossActiveStartMusic:setVolume(audioMusicVolume)
  bossLoopMusic = love.audio.newSource('resources/music/music/bossfightactiveloop.ogg', 'stream')
  bossLoopMusic:setLooping(true)
  bossLoopMusic:setVolume(audioMusicVolume)
  bossDefeatSound = nil
  local bossDefeatPaths = {
    'resources/music/sfx/beatbosswin.wav',
    'resources/music/music/beatbosswin.wav',
  }
  for _, bossDefeatPath in ipairs(bossDefeatPaths) do
    if love.filesystem.getInfo(bossDefeatPath) then
      bossDefeatSound = registerSfxSource(love.audio.newSource(bossDefeatPath, 'static'))
      break
    end
  end
  if not bossDefeatSound then
    bossDefeatSound = createBossDefeatTone()
  end
  local floorTransitionPaths = {
    'resources/music/music/floor transition.wav',
    'resources/music/sfx/floor transition.wav',
  }
  for _, floorTransitionPath in ipairs(floorTransitionPaths) do
    if love.filesystem.getInfo(floorTransitionPath) then
      floorTransitionSound = love.audio.newSource(floorTransitionPath, 'static')
      registerSfxSource(floorTransitionSound)
      break
    end
  end
end

local function initializeMenu()
  cultistCardImages = {
    health = love.graphics.newImage('resources/gfx/ui/cultistcard/cultistcard_001_health.png'),
    speed = love.graphics.newImage('resources/gfx/ui/cultistcard/cultistcard_002_speed.png'),
  }
  for _, image in pairs(cultistCardImages) do
    image:setFilter('nearest', 'nearest')
  end
  Atlas:load()
  Fly.load()
  ladderImage = love.graphics.newImage('resources/gfx/ui/stage/climbingladder.png')
  ladderImage:setFilter('nearest', 'nearest')
  renderer = Renderer.new(Atlas)
  menuSwitchSound = createMenuTone(1050, 760, 0.065)
  menuSelectSound = createMenuTone(620, 980, 0.11)
  menuCancelSound = createMenuTone(440, 190, 0.14)
  mainMenu = MainMenu.new(renderer, menuSwitchSound, menuSelectSound, menuCancelSound)
  mainMenu.musicVolume = audioMusicVolume
  mainMenu.sfxVolume = audioSfxVolume
  mainMenu.screenShakeEnabled = screenShakeEnabled
  mainMenu.onSettingsChanged = setAudioSettings
  mainMenu.hasSave = love.filesystem.getInfo(SAVE_FILE) ~= nil
  refreshMenuExtras()
end

function love.load()
  if love.window.maximize and love.window.isMaximized
      and not love.window.isMaximized() then
    love.window.maximize()
  end

  love.graphics.setDefaultFilter('nearest', 'nearest')
  love.window.setTitle('Heat Dweller')
  initializeProfileAndItems()

  world = {
    width = 1280,
    height = 960,
    tileSize = 80,
    roomType = 'basement',
    floorType = 'basement',
    floorIndex = 1,
    camera = { x = 0, y = 0, width = 1024, height = 576 },
  }
  deathScreenImage = nil
  local deathScreenCandidates = {
    'resources/gfx/ui/stage/deathscreen.png',
    'resources/gfx/ui/stage/deathsceen.png',
  }
  for _, deathScreenPath in ipairs(deathScreenCandidates) do
    if love.filesystem.getInfo(deathScreenPath) then
      deathScreenImage = love.graphics.newImage(deathScreenPath)
      deathScreenImage:setFilter('nearest', 'nearest')
      break
    end
  end
  input = Input.new()
  initializeAudio()
  resetPlayer()
  enemies = {}
  gameState = 'cutscene_fallback'
  characterIndex = 1
  selectedCharacter = characters[characterIndex]
  for _, character in ipairs(characters) do
    character.image = love.graphics.newImage(character.imagePath)
    character.image:setFilter('nearest', 'nearest')
  end
  waitingForPickupSound = false
  roomRewardSpawned = false
  roomIndex = 1
  currentRoom = nil
  rooms = {}
  exploredRooms = {}
  seenRooms = {}
  ladder = nil
  bossDeathParticles = {}
  doorsLocked = true
  crawler = nil
  lilSnake = nil
  geometric = nil
  stuffing = nil
  babyWidow = nil
  acidProjectiles = {}
  screenShakeTime = 0
  screenShakeStrength = 0
  spiderSpawnTimer = 0
  bossIntroTimer = 0
  bossIntroType = nil
  bossDefeated = false
  isPickingUpItem = false
  pickupTimer = 0
  pickupNotification = nil
  pickupNotificationElapsed = 0

  initializeMenu()
  updateCameraSize()
  player:update(0, input, world)
  loadOpeningCutscene()
end

local function copySaveData(value, omitRuntimeReferences)
  if type(value) ~= 'table' then
    return value
  end

  local copy = {}
  for key, entry in pairs(value) do
    local skip = omitRuntimeReferences and
      (key == 'image' or key == 'definition' or key == 'shopOffers' or key == 'cultistOffer')
    if not skip and type(entry) ~= 'function' and type(entry) ~= 'userdata' then
      copy[key] = copySaveData(entry, omitRuntimeReferences)
    end
  end
  return copy
end

local function saveEntity(entity, fields)
  if not entity then
    return nil
  end
  local snapshot = {}
  for _, field in ipairs(fields) do
    local value = entity[field]
    if type(value) == 'number' or type(value) == 'string' or type(value) == 'boolean' then
      snapshot[field] = value
    elseif type(value) == 'table' then
      snapshot[field] = copySaveData(value, true)
    end
  end
  return snapshot
end

local function restoreEntity(entity, snapshot)
  if not entity or not snapshot then
    return
  end
  for field, value in pairs(snapshot) do
    entity[field] = value
  end
end

local function saveRoomFlags(flags)
  local saved = {}
  for roomId, value in pairs(flags or {}) do
    saved[tostring(roomId)] = value
  end
  return saved
end

local function restoreRoomFlags(flags)
  local restored = {}
  for roomId, value in pairs(flags or {}) do
    restored[tonumber(roomId)] = value
  end
  return restored
end

local function saveOffer(offer)
  if not offer then
    return nil
  end
  return {
    itemId = offer.definition.id,
    x = offer.x,
    baseY = offer.baseY,
    timer = offer.timer,
    purchased = offer.purchased,
  }
end

local function restoreOffer(snapshot)
  if not snapshot then
    return nil
  end
  local definition = items.definitions[snapshot.itemId]
  assert(definition, 'Save refers to unknown item id ' .. tostring(snapshot.itemId))
  return {
    definition = definition,
    x = snapshot.x,
    baseY = snapshot.baseY,
    timer = snapshot.timer,
    purchased = snapshot.purchased or false,
  }
end

saveRun = function()
  if not currentRoom or not rooms or #rooms == 0 then
    return false, 'There is no active run to save.'
  end

  local inventory = {}
  for id, count in pairs(items.inventory) do
    inventory[#inventory + 1] = { id = id, count = count }
  end
  local activeItems = {}
  for _, item in ipairs(items.active) do
    activeItems[#activeItems + 1] = {
      id = item.definition.id,
      x = item.x,
      baseY = item.baseY,
      timer = item.timer,
    }
  end

  local bossFields = {
    'x', 'y', 'health', 'alive', 'phase', 'phaseState', 'phaseStateTimer',
    'pathIndex', 'animationTime', 'babySpawnTimer', 'babySpawned',
    'rushDistanceRemaining', 'rushSpeed',
  }
  local snakeFields = {
    'x', 'y', 'health', 'alive', 'facing', 'animationTimer',
    'animationFrame', 'trailDistance', 'trail',
    'locomotionDirectionX', 'locomotionDirectionY',
    'locomotionTurnTimer', 'holeSpawnTimer', 'holes',
  }
  local geometricFields = {
    'x', 'y', 'health', 'maxHealth', 'alive', 'bodyHealth', 'bodyAlive', 'phase',
    'animationTime', 'facing', 'moving', 'contactCooldown', 'heads',
    'headOrbitAngle', 'bodyInvulnerabilityTimer', 'shieldActive',
    'finalVx', 'finalVy', 'finalHeadHealth', 'headShatters',
    'finalShakeTimer',
  }
  local minionFields = {
    'x', 'y', 'health', 'alive', 'pathIndex', 'animationTime',
    'spiderSpawnTimer', 'attackCooldown', 'attackWindup',
    'aggravated',
  }
  local stuffingFields = {
    'x', 'y', 'health', 'maxHealth', 'alive', 'phase', 'animationTime',
    'suctioning', 'pullStrength', 'projectileTimer', 'charred', 'stateTimer',
  }
  local enemyFields = {
    'kind', 'x', 'y', 'health', 'alive', 'speed', 'aggravated',
    'animationTime', 'attackCooldown', 'state',
    'animationName', 'animationFrame', 'animationTimer', 'dashCooldown',
    'stateTimer', 'dashDirectionX', 'dashDirectionY',
    'driftAngle', 'driftTargetX', 'driftTargetY', 'driftTimer',
    'velocityX', 'velocityY',
  }
  local savedEnemies = {}
  for index, enemy in ipairs(enemies) do
    savedEnemies[index] = saveEntity(enemy, enemyFields)
  end

  local snapshot = {
    version = 1,
    seed = runSeed,
    world = {
      floorIndex = world.floorIndex,
      floorType = world.floorType,
      roomType = world.roomType,
    },
    rooms = copySaveData(rooms, true),
    roomIndex = roomIndex,
    roomGridX = currentRoom.gridX,
    roomGridY = currentRoom.gridY,
    exploredRooms = saveRoomFlags(exploredRooms),
    seenRooms = saveRoomFlags(seenRooms),
    doorsLocked = doorsLocked,
    roomRewardSpawned = roomRewardSpawned,
    bossDefeated = bossDefeated,
    ladder = copySaveData(ladder),
    player = {
      x = player.x,
      y = player.y,
      facing = player.facing,
      speed = player.speed,
      stats = copySaveData(player.stats),
      activeEffects = copySaveData(player.activeEffects),
      damageInvulnerabilityTimer = player.damageInvulnerabilityTimer,
      temporaryPlatform = copySaveData(player.temporaryPlatform),
    },
    inventory = inventory,
    activeItems = activeItems,
    heldActiveItem = items.heldActive and items.heldActive.id or nil,
    activeItemCooldown = items.cooldownRemaining,
    activeFireZones = copySaveData(activeFireZones),
    snowmanArmedTimer = snowmanArmedTimer,
    snowmanFamiliarTimer = snowmanFamiliarTimer,
    snowmanShotTimer = snowmanShotTimer,
    enemies = savedEnemies,
    crawler = saveEntity(crawler, bossFields),
    lilSnake = saveEntity(lilSnake, snakeFields),
    geometric = saveEntity(geometric, geometricFields),
    stuffing = saveEntity(stuffing, stuffingFields),
    lilSnakeTrail = lilSnake and copySaveData(lilSnake.trail) or nil,
    babyWidow = saveEntity(babyWidow, minionFields),
    acidProjectiles = {},
    shopOffers = {},
    roomOffers = {},
    cultistOffer = saveOffer(cultistOffer),
    inputBindings = copySaveData(input.bindings),
    characterIndex = characterIndex,
  }
  for _, projectile in ipairs(acidProjectiles) do
    snapshot.acidProjectiles[#snapshot.acidProjectiles + 1] = saveEntity(projectile, {
      'x', 'y', 'velocityX', 'velocityY', 'alive', 'damage', 'radius',
      'lifetime',
    })
  end
  for _, offer in ipairs(shopOffers or {}) do
    snapshot.shopOffers[#snapshot.shopOffers + 1] = saveOffer(offer)
  end
  for index, room in ipairs(rooms) do
    if room.shopOffers or room.cultistOffer then
      local roomOfferSnapshot = {}
      for _, offer in ipairs(room.shopOffers or {}) do
        roomOfferSnapshot.shop = roomOfferSnapshot.shop or {}
        roomOfferSnapshot.shop[#roomOfferSnapshot.shop + 1] = saveOffer(offer)
      end
      roomOfferSnapshot.cultist = saveOffer(room.cultistOffer)
      snapshot.roomOffers[tostring(index)] = roomOfferSnapshot
    end
  end

  local encodedSuccessfully, encoded = pcall(Json.encode, snapshot)
  if not encodedSuccessfully then
    return false, 'Unable to serialize the active run: ' .. tostring(encoded)
  end
  local success, message = love.filesystem.write(SAVE_FILE, encoded)
  if not success then
    return false, message or 'Unable to write the run save.'
  end
  mainMenu.hasSave = true
  mainMenu.message = nil
  return true
end

continueRun = function()
  local contents, readError = love.filesystem.read(SAVE_FILE)
  if not contents then
    return false, readError or 'No saved run was found.'
  end

  local decoded, snapshot = pcall(Json.decode, contents)
  if not decoded then
    return false, 'The saved run could not be read: ' .. tostring(snapshot)
  end
  if type(snapshot) ~= 'table' or snapshot.version ~= 1
      or type(snapshot.rooms) ~= 'table' or type(snapshot.player) ~= 'table'
      or type(snapshot.world) ~= 'table' or type(snapshot.roomIndex) ~= 'number'
      or snapshot.roomIndex % 1 ~= 0 or not snapshot.rooms[snapshot.roomIndex]
      or type(snapshot.player.x) ~= 'number' or type(snapshot.player.y) ~= 'number'
      or type(snapshot.seed) ~= 'number' then
    return false, 'The saved run is invalid or uses an unsupported version.'
  end

  runSeed = snapshot.seed
  local savedFloorIndex = snapshot.world.floorIndex or 1
  if type(savedFloorIndex) ~= 'number' or savedFloorIndex % 1 ~= 0
      or not floorTypeForIndex(savedFloorIndex) then
    return false, 'The saved run refers to an unsupported or inconsistent floor.'
  end
  local savedFloorType = snapshot.world.floorType or floorTypeForIndex(savedFloorIndex)
  if floorTypeForIndex(savedFloorIndex) ~= savedFloorType then
    return false, 'The saved run refers to an unsupported or inconsistent floor.'
  end

  world.floorIndex = savedFloorIndex
  world.floorType = savedFloorType
  updatePlayerSpriteForFloor()
  currentFloorDisplayName = getFloorDisplayName(savedFloorType)
  currentFloorBannerTimer = 3
  world.roomType = snapshot.world.roomType or world.floorType
  setFloorMusicVolume()
  rooms = snapshot.rooms
  roomIndex = snapshot.roomIndex
  exploredRooms = restoreRoomFlags(snapshot.exploredRooms)
  seenRooms = restoreRoomFlags(snapshot.seenRooms)
  characterIndex = snapshot.characterIndex or 1
  selectedCharacter = characters[characterIndex] or characters[1]
  if selectedCharacter.spriteSheetPath then
    renderer:setCharacter(selectedCharacter.spriteSheetPath)
  end
  autosaveTimer = 0

  initializeItems()
  resetPlayer()
  for stat, value in pairs(snapshot.player.stats or {}) do
    player.stats[stat] = value
  end
  for field, value in pairs(snapshot.player) do
    if field == 'speed' or field == 'facing'
        or field == 'damageInvulnerabilityTimer' then
      player[field] = value
    end
  end
  player.activeEffects = snapshot.player.activeEffects or {}
  for _, entry in ipairs(snapshot.inventory or {}) do
    items.inventory[entry.id] = entry.count
  end
  if snapshot.heldActiveItem then
    items.heldActive = items.definitions[snapshot.heldActiveItem]
    assert(items.heldActive and items.heldActive.type == 'active',
      'Save refers to unknown active item id ' .. tostring(snapshot.heldActiveItem))
    items.cooldownRemaining = math.max(0, snapshot.activeItemCooldown or 0)
  end
  player.temporaryPlatform = snapshot.player.temporaryPlatform
  for _, entry in ipairs(snapshot.activeItems or {}) do
    local definition = items.definitions[entry.id]
    assert(definition, 'Save refers to unknown item id ' .. tostring(entry.id))
    items.active[#items.active + 1] = {
      definition = definition,
      x = entry.x,
      baseY = entry.baseY,
      timer = entry.timer,
    }
  end
  for key, value in pairs(snapshot.inputBindings or {}) do
    input.bindings[key] = value
  end
  for roomId, offerSnapshot in pairs(snapshot.roomOffers or {}) do
    local room = rooms[tonumber(roomId)]
    if room then
      if offerSnapshot.shop then
        room.shopOffers = {}
        for index, offer in ipairs(offerSnapshot.shop) do
          room.shopOffers[index] = restoreOffer(offer)
        end
      end
      room.cultistOffer = restoreOffer(offerSnapshot.cultist)
    end
  end

  enterRoom(roomIndex, nil, true, true)
  restoreEntity(crawler, snapshot.crawler)
  restoreEntity(lilSnake, snapshot.lilSnake)
  restoreEntity(geometric, snapshot.geometric)
  restoreEntity(stuffing, snapshot.stuffing)
  if geometric then
    geometric:restoreRuntimeState()
    geometric.onScreenShake = function(strength)
      triggerScreenShake(strength)
    end
  end
  if lilSnake and snapshot.lilSnakeTrail then
    lilSnake.trail = snapshot.lilSnakeTrail
  end
  if crawler and snapshot.babyWidow then
    crawler.babySpawned = true
    spawnBabyWidow()
    restoreEntity(babyWidow, snapshot.babyWidow)
  end
  for index, enemySnapshot in ipairs(snapshot.enemies or {}) do
    restoreEntity(enemies[index], enemySnapshot)
  end
  acidProjectiles = {}
  activeFireZones = snapshot.activeFireZones or {}
  snowmanArmedTimer = snapshot.snowmanArmedTimer or 0
  snowmanFamiliarTimer = snapshot.snowmanFamiliarTimer or 0
  snowmanShotTimer = snapshot.snowmanShotTimer or 0
  for _, projectile in ipairs(snapshot.acidProjectiles or {}) do
    acidProjectiles[#acidProjectiles + 1] = AcidProjectile.new(
      projectile.x, projectile.y, projectile.x + projectile.velocityX, projectile.y + projectile.velocityY
    )
    restoreEntity(acidProjectiles[#acidProjectiles], projectile)
  end
  player.x = snapshot.player.x
  player.y = snapshot.player.y
  doorsLocked = snapshot.doorsLocked
  roomRewardSpawned = snapshot.roomRewardSpawned
  bossDefeated = snapshot.bossDefeated
  ladder = snapshot.ladder
  if currentRoom.shop then
    shopOffers = {}
    for index, offer in ipairs(snapshot.shopOffers or {}) do
      shopOffers[index] = restoreOffer(offer)
    end
    currentRoom.shopOffers = shopOffers
  end
  if currentRoom.cultistDeal and snapshot.cultistOffer then
    cultistOffer = restoreOffer(snapshot.cultistOffer)
    currentRoom.cultistOffer = cultistOffer
  end
  for _, door in pairs(currentRoom.doors or {}) do
    door.locked = doorsLocked
  end
  gameState = 'playing'
  if currentRoom.boss and not bossDefeated then
    stopBasementMusic(false)
    stopKitchenMusic(false)
    stopSkyMusic(false)
    if backgroundMusic then
      backgroundMusic:stop()
      backgroundMusic:setVolume(0)
    end
    bossMusicPhase = 'loop'
    bossIntroMusic:stop()
    bossActiveStartMusic:stop()
    bossLoopMusic:play()
  elseif world.floorType == 'kitchen' then
    stopBasementMusic(false)
    stopSkyMusic(false)
    if backgroundMusic then
      backgroundMusic:stop()
      backgroundMusic:setVolume(0)
    end
    startKitchenMusic()
  elseif world.floorType == 'sky' then
    stopBasementMusic(false)
    stopKitchenMusic(false)
    if backgroundMusic then
      backgroundMusic:stop()
      backgroundMusic:setVolume(0)
    end
    if skyMusic and skyMusic:isPlaying() then
      skyMusic:setVolume(audioMusicVolume)
    else
      startSkyMusic()
    end
  elseif world.floorType ~= 'basement' then
    stopBasementMusic(false)
    stopKitchenMusic(false)
    stopSkyMusic(false)
    backgroundMusic:play()
  else
    stopKitchenMusic(false)
    stopSkyMusic(false)
    if backgroundMusic then
      backgroundMusic:stop()
      backgroundMusic:setVolume(0)
    end
    startBasementMusic()
  end
  renderer:updateBossHealth(crawler or lilSnake or geometric or stuffing, 0)
  mainMenu.hasSave = true
  mainMenu.message = nil
  return true
end

local function updateSweatCombat(dt, targets)
  local walls = currentRoom and currentRoom.layout.walls or {}
  local defeated = SweatProjectile.updateAll(
    sweatProjectiles,
    sweatSplashes,
    dt,
    targets,
    walls,
    world,
    player.stats.damage * 0.2
  )
  for _, target in ipairs(defeated) do
    if target == crawler or target == lilSnake or target == geometric or target == stuffing then
      player.stats.dollars = player.stats.dollars + 8
    elseif target == babyWidow then
      player.stats.dollars = player.stats.dollars + 3
    elseif not target.geometricPart then
      player.stats.dollars = player.stats.dollars + 1
    end
  end
end

function love.update(dt)
  updateMainMenuMusic(dt)
  if mainMenu and gameState ~= 'title' then
    if gameState ~= 'character_select' then
      mainMenu:updateTransition(dt)
    end
  end
  if gameState == 'opening_cutscene' then
    if openingCutscene then
      if not openingCutscene:isPlaying() then
        finishOpeningCutscene()
      end
    else
      finishOpeningCutscene()
    end
    return
  elseif gameState == 'cutscene_fallback' then
    cutsceneFallbackTimer = cutsceneFallbackTimer + dt
    if cutsceneFallbackTimer >= cutsceneFallbackDuration then
      finishOpeningCutscene()
    end
    return
  end
  if gameState == 'paused' then
    mainMenu:updatePause(dt)
    return
  end
  if gameState == 'item_selector' then
    return
  end
  updateBasementMusicFade(dt)
  updateKitchenMusicFade(dt)
  updateSkyMusicFade(dt)
  if gameState == 'title' then
    mainMenu:update(dt)
    return
  elseif gameState == 'character_select' then
    mainMenu:update(dt)
    characterCarouselPosition = characterCarouselPosition
      + (characterCarouselTarget - characterCarouselPosition) * math.min(1, dt * 10)
    return
  end
  if screenShakeTime and screenShakeTime > 0 then
    screenShakeTime = math.max(0, screenShakeTime - dt)
  end

  if currentFloorBannerTimer > 0 then
    currentFloorBannerTimer = math.max(0, currentFloorBannerTimer - dt)
  end

  if gameState == 'floor_transition' then
    floorTransitionTimer = (floorTransitionTimer or 0) + dt
    finishFloorTransition()
    return
  end

  if gameState == 'boss_intro' then
    bossIntroTimer = bossIntroTimer + dt
    if bossIntroTimer >= 1.8 then
      bossIntroMusic:stop()
      bossActiveStartMusic:play()
      bossMusicPhase = 'active_start'
      gameState = 'playing'
    end
    return
  end

  if gameState == 'playing' and bossMusicPhase == 'active_start' then
    local remaining = bossActiveStartMusic:getDuration() - bossActiveStartMusic:tell()
    if remaining <= bossMusicCrossfadeDuration then
      if not bossLoopMusic:isPlaying() then
        bossLoopMusic:setVolume(0)
        bossLoopMusic:play()
      end
      local progress = math.max(0, math.min(
        1,
        1 - math.max(0, remaining) / bossMusicCrossfadeDuration
      ))
      bossLoopMusic:setVolume(audioMusicVolume * progress)
      bossActiveStartMusic:setVolume(audioMusicVolume * (1 - progress))
    end
    if not bossActiveStartMusic:isPlaying() then
      bossLoopMusic:setVolume(audioMusicVolume)
      bossActiveStartMusic:setVolume(audioMusicVolume)
      bossMusicPhase = 'loop'
    end
  end

  if gameState ~= 'playing' then
    return
  end

  if pickupNotification then
    pickupNotificationElapsed = pickupNotificationElapsed + dt
    if pickupNotificationElapsed >= pickupNotificationDuration then
      pickupNotification = nil
      pickupNotificationElapsed = 0
    end
  end

  if isPickingUpItem then
    pickupTimer = pickupTimer - dt
    if pickupTimer <= 0 then
      isPickingUpItem = false
      pickupTimer = 0
    end
    return
  end

  input:update()
  world.floorHoles = currentRoom and currentRoom.layout.floorHoles or {}
  world.solidObstacles = currentRoom and currentRoom.layout.obstacles or {}
  if not lilSnake and currentRoom then
    for index = #world.floorHoles, 1, -1 do
      local hole = world.floorHoles[index]
      hole.lifetime = (hole.lifetime or 20) - dt
      if hole.lifetime <= 0 then
        table.remove(world.floorHoles, index)
      end
    end
  end
  player:update(dt, input, world)
  if love.mouse.isDown(1) then
    local mouseX, mouseY = love.mouse.getPosition()
    local screenWidth, screenHeight = love.graphics.getDimensions()
    local letterboxX = math.max(0, (screenWidth - world.width) / 2)
    local letterboxY = math.max(0, (screenHeight - world.height) / 2)
    local targetX = mouseX + world.camera.x - letterboxX
    local targetY = mouseY + world.camera.y - letterboxY
    player:shootSweat(targetX - player.x, targetY - (player.y - 22))
  else
    local attackDirection = input:getHeldAttackDirection()
    if attackDirection then
      player:shootSweat(attackDirection)
    end
  end
  player.foamEquipped = (items.inventory[23] or 0) > 0
  local foamTargets = {}
  if crawler then
    foamTargets[#foamTargets + 1] = crawler
  end
  if lilSnake then
    foamTargets[#foamTargets + 1] = lilSnake
  end
  if geometric then
    for _, target in ipairs(geometric:getTargets()) do
      foamTargets[#foamTargets + 1] = target
    end
  end
  if stuffing then
    foamTargets[#foamTargets + 1] = stuffing
  end
  if babyWidow then
    foamTargets[#foamTargets + 1] = babyWidow
  end
  for _, enemy in ipairs(enemies) do
    foamTargets[#foamTargets + 1] = enemy
  end
  local foamDeaths = fireFoam:update(
    dt,
    player,
    player.foamEquipped,
    input:getHeldAttackDirection(),
    foamTargets,
    world,
    currentRoom and currentRoom.layout.walls or {}
  )
  for _, defeated in ipairs(foamDeaths) do
    if defeated == crawler or defeated == lilSnake or defeated == geometric or defeated == stuffing then
      player.stats.dollars = player.stats.dollars + 8
    elseif defeated == babyWidow then
      player.stats.dollars = player.stats.dollars + 3
    elseif not defeated.geometricPart then
      player.stats.dollars = player.stats.dollars + 1
    end
  end
  if crawler then
    if crawler:update(dt) then
      spawnBabyWidow()
    end
  end
  if lilSnake then
    lilSnake:update(dt, player)
  end
  if geometric then
    geometric:update(dt, player, currentRoom and currentRoom.layout.walls or {})
  end
  if stuffing then
    stuffing:update(dt, player, currentRoom and currentRoom.layout.walls or {})
  end
  if babyWidow then
    local spiderCount = babyWidow:update(dt, player)
    for _ = 1, spiderCount do
      spawnBabySpider()
    end
    if not babyWidow.alive then
      if crawler then
        crawler:beginPhaseTwo()
      end
      babyWidow = nil
    end
  end
  if player.stats.health <= 0 then
    gameState = 'game_over'
    hardStopMusicSources()
    return
  end
  for _, projectile in ipairs(acidProjectiles) do
    projectile:update(dt, player)
  end
  for index = #acidProjectiles, 1, -1 do
    if not acidProjectiles[index].alive then
      table.remove(acidProjectiles, index)
    end
  end
  for _, enemy in ipairs(enemies) do
    if enemy and type(enemy.update) == 'function' and enemy.alive then
      local spawned = enemy:update(dt, player, world)
      if spawned and type(spawned) == 'table' then
        for _, child in ipairs(spawned) do
          if child and type(child.update) == 'function' then
            table.insert(enemies, child)
          end
        end
      end
    end
  end

  for index = #enemies, 1, -1 do
    local enemy = enemies[index]
    if not enemy or not enemy.alive or type(enemy.update) ~= 'function' then
      table.remove(enemies, index)
    end
  end
  updateSweatCombat(dt, foamTargets)

  local activeBoss = crawler or lilSnake or geometric or stuffing
  if currentRoom and currentRoom.boss then
    renderer:updateBossHealth(activeBoss, dt)
  else
    renderer:updateBossHealth(nil, dt)
  end

  if activeBoss and not activeBoss.alive then
    if startBossDeathSequence and not activeBoss.deathSequence then
      startBossDeathSequence(activeBoss)
    elseif activeBoss.deathSequence then
      updateBossDeathSequence(dt, activeBoss)
    end
  end

  if updateBossDeathParticles then
    updateBossDeathParticles(dt)
  end

  if doorsLocked and areAllRoomEnemiesDefeated() then
    doorsLocked = false
    currentRoom.cleared = true
    for _, door in pairs(currentRoom.doors or {}) do
      door.locked = false
    end
    if currentRoom.boss and not ladder and world.floorIndex < #FLOOR_TYPES then
      ladder = { x = 104, y = 104 }
    end
  end

  if currentRoom and currentRoom.boss and currentRoom.dealUnlocked and not roomRewardSpawned then
    items:spawnFloorReward(world.width / 2, world.height / 2)
    roomRewardSpawned = true
  end

  if crawler and crawler.alive then
    spiderSpawnTimer = spiderSpawnTimer + dt
    while spiderSpawnTimer >= 5 do
      spawnSpider()
      spiderSpawnTimer = spiderSpawnTimer - 5
    end
  end

  autosaveTimer = autosaveTimer + dt
  if autosaveTimer >= 10 then
    autosaveTimer = 0
    local saved, saveError = saveRun()
    if not saved and currentRoom then
      mainMenu.message = 'Save failed: ' .. tostring(saveError)
      print(mainMenu.message)
    end
  end

  if not doorsLocked and tryRoomTransition() then
    return
  end

  if ladder and playerTouchesLadder() then
    transitionToNextFloor()
    return
  end

  items:update(dt, player, function(definition)
    isPickingUpItem = true
    pickupTimer = 0.8
    pickupNotification = definition
    pickupNotificationElapsed = 0
    pauseGameAudio()
    waitingForPickupSound = true
  end)
  updateActiveEffects(dt)

  if waitingForPickupSound and not items:isPickupSoundPlaying() then
    waitingForPickupSound = false
    resumeGameAudio()
  end
end

local function getLivingRoomTargets()
  local targets = {}
  for _, enemy in ipairs(enemies) do
    if enemy.alive then targets[#targets + 1] = enemy end
  end
  if crawler and crawler.alive then targets[#targets + 1] = crawler end
  if lilSnake and lilSnake.alive then targets[#targets + 1] = lilSnake end
  if geometric then
    for _, target in ipairs(geometric:getTargets()) do
      targets[#targets + 1] = target
    end
  end
  if stuffing and stuffing.alive then targets[#targets + 1] = stuffing end
  if babyWidow and babyWidow.alive then targets[#targets + 1] = babyWidow end
  return targets
end

local function damageTarget(target, amount)
  if not target.alive then
    return
  end
  if target.takeDamage then
    local defeatedTarget = target:takeDamage(amount)
    if defeatedTarget then
      if target == babyWidow and target.onDeath then
        target.onDeath()
      end
      if target == crawler or target == lilSnake or target == geometric or target == stuffing then
        player.stats.dollars = player.stats.dollars + 8
      elseif target == babyWidow then
        player.stats.dollars = player.stats.dollars + 3
      elseif not target.geometricPart then
        player.stats.dollars = player.stats.dollars + 1
      end
    end
    return
  end
  target.health = math.max(0, target.health - amount)
  if target == babyWidow and target.onDamaged then
    target.onDamaged()
  end
  if target.health == 0 then
    target.alive = false
    if target == babyWidow and target.onDeath then
      target.onDeath()
    end
    if target == crawler or target == lilSnake or target == geometric or target == stuffing then
      player.stats.dollars = player.stats.dollars + 8
    elseif target == babyWidow then
      player.stats.dollars = player.stats.dollars + 3
    elseif not target.geometricPart then
      player.stats.dollars = player.stats.dollars + 1
    end
  end
end

local function damageRoom(amount, centerX, centerY, radius, fractionOfHealth)
  for _, target in ipairs(getLivingRoomTargets()) do
    local dx, dy = target.x - centerX, target.y - centerY
    if not radius or dx * dx + dy * dy <= radius * radius then
      local damage = amount
      if fractionOfHealth then
        damage = (target.maxHealth or target.health) * fractionOfHealth
      end
      damageTarget(target, damage)
    end
  end
end

function activateHeldItem()
  local definition = items and items.heldActive
  if not definition or items.cooldownRemaining > 0 or gameState ~= 'playing'
      or isPickingUpItem then
    return false
  end

  local successful = false
  if definition.activeAction == 'playdough_platform' then
    player.temporaryPlatform = {
      x = player.x,
      y = player.y,
      radius = 58,
      timer = 12,
    }
    successful = true
  elseif definition.activeAction == 'cake' then
    player.stats.health = math.min(player.stats.maxHealth, player.stats.health + 20)
    player.damageInvulnerabilityTimer = math.max(player.damageInvulnerabilityTimer, 5)
    successful = true
  elseif definition.activeAction == 'molotov' then
    local directions = {
      left = { -1, 0 },
      right = { 1, 0 },
      up = { 0, -1 },
      down = { 0, 1 },
    }
    local direction = directions[player.facing]
    activeFireZones[#activeFireZones + 1] = {
      x = player.x + direction[1] * 140,
      y = player.y + direction[2] * 140,
      radius = 92,
      timer = 6,
      tickTimer = 0,
    }
    successful = true
  elseif definition.activeAction == 'charger' then
    damageRoom(0, 0, 0, nil, 0.5)
    if player.stats.health <= 10 then
      player.stats.health = 0
      gameState = 'game_over'
      hardStopMusicSources()
    else
      player.stats.health = 10
    end
    successful = true
  elseif definition.activeAction == 'duality' then
    successful = items:rerollPassiveInventory(player, player.x, player.y)
  elseif definition.activeAction == 'snowman' then
    snowmanArmedTimer = 8
    successful = true
  elseif definition.activeAction == 'cultist_oath' then
    damageRoom(player.stats.damage, 0, 0)
    player.stats.health = math.max(0, player.stats.health - 20)
    if player.stats.health <= 0 then
      gameState = 'game_over'
      hardStopMusicSources()
    end
    successful = true
  elseif definition.activeAction == 'bread' then
    if math.random() < 0.5 then
      player.stats.health = player.stats.maxHealth
      player.damageInvulnerabilityTimer = math.max(player.damageInvulnerabilityTimer, 5)
    else
      player.stats.health = math.max(0, player.stats.health - 20)
      if player.stats.health <= 0 then
        gameState = 'game_over'
        hardStopMusicSources()
      end
    end
    successful = true
  elseif definition.activeAction == 'mallet' then
    local successChance = math.min(1, 0.25 + math.max(0, player.stats.luck) * 0.02)
    if math.random() < successChance then
      damageRoom(player.stats.damage * 0.25, 0, 0)
    elseif player.stats.health <= 10 then
      player.stats.health = 0
      gameState = 'game_over'
      hardStopMusicSources()
    else
      player.stats.health = 10
    end
    successful = true
  end

  if successful then
    items.cooldownRemaining = definition.cooldown or 0
  end
  return successful
end

function updateActiveEffects(dt)
  snowmanArmedTimer = math.max(0, snowmanArmedTimer - dt)
  for index = #activeFireZones, 1, -1 do
    local fire = activeFireZones[index]
    fire.timer = fire.timer - dt
    fire.tickTimer = fire.tickTimer - dt
    while fire.tickTimer <= 0 and fire.timer > 0 do
      damageRoom(player.stats.damage * 0.25, fire.x, fire.y, fire.radius)
      fire.tickTimer = fire.tickTimer + 0.6
    end
    if fire.timer <= 0 then
      table.remove(activeFireZones, index)
    end
  end

  if snowmanFamiliarTimer > 0 then
    snowmanFamiliarTimer = math.max(0, snowmanFamiliarTimer - dt)
    snowmanShotTimer = snowmanShotTimer - dt
    if snowmanShotTimer <= 0 then
      local target, nearestDistance
      for _, candidate in ipairs(getLivingRoomTargets()) do
        local dx, dy = candidate.x - player.x, candidate.y - player.y
        local distance = dx * dx + dy * dy
        if distance <= 420 * 420 and (not nearestDistance or distance < nearestDistance) then
          target, nearestDistance = candidate, distance
        end
      end
      if target then damageTarget(target, 5) end
      snowmanShotTimer = 0.7
    end
  end
end

function drawActiveEffects(camera)
  love.graphics.setColor(0.98, 0.35, 0.08, 0.42)
  for _, fire in ipairs(activeFireZones) do
    local pulse = 0.85 + math.sin(love.timer.getTime() * 12) * 0.15
    love.graphics.circle(
      'fill',
      math.floor(fire.x - camera.x),
      math.floor(fire.y - camera.y),
      fire.radius * pulse
    )
    love.graphics.setColor(1, 0.75, 0.18, 0.75)
    love.graphics.circle('line', math.floor(fire.x - camera.x), math.floor(fire.y - camera.y), fire.radius * pulse)
    love.graphics.setColor(0.98, 0.35, 0.08, 0.42)
  end
  if player.temporaryPlatform and player.temporaryPlatform.timer > 0 then
    local platform = player.temporaryPlatform
    love.graphics.setColor(0.55, 0.72, 0.76, 0.72)
    love.graphics.ellipse(
      'fill',
      math.floor(platform.x - camera.x),
      math.floor(platform.y - camera.y + 15),
      platform.radius,
      platform.radius * 0.38
    )
    love.graphics.setColor(0.85, 0.94, 0.95, 0.9)
    love.graphics.ellipse(
      'line',
      math.floor(platform.x - camera.x),
      math.floor(platform.y - camera.y + 15),
      platform.radius,
      platform.radius * 0.38
    )
  end
  if snowmanFamiliarTimer > 0 then
    love.graphics.setColor(0.82, 0.94, 1, 0.9)
    love.graphics.circle('fill', math.floor(player.x - camera.x + 44), math.floor(player.y - camera.y - 38), 12)
    love.graphics.circle('fill', math.floor(player.x - camera.x + 44), math.floor(player.y - camera.y - 18), 16)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function love.quit()
  if currentRoom and (gameState == 'playing' or gameState == 'paused' or gameState == 'boss_intro') then
    local saved, saveError = saveRun()
    if not saved then
      print('Save failed: ' .. tostring(saveError))
    end
  end
end

local function captureGameplayPauseFrame()
  if not mainMenu or not world then
    return
  end

  local width, height = love.graphics.getDimensions()
  if not mainMenu.pauseFrameCanvas or mainMenu.pauseFrameCanvas:getWidth() ~= width
      or mainMenu.pauseFrameCanvas:getHeight() ~= height then
    mainMenu.pauseFrameCanvas = love.graphics.newCanvas(width, height)
  end

  local previousCanvas = love.graphics.getCanvas()
  love.graphics.setCanvas(mainMenu.pauseFrameCanvas)
  love.graphics.clear(0.055, 0.07, 0.08)

  local shakeX, shakeY = getScreenShakeOffset()
  local cameraX, cameraY = world.camera.x, world.camera.y
  local screenWidth, screenHeight = love.graphics.getDimensions()
  local letterboxX = math.max(0, (screenWidth - world.width) / 2)
  local letterboxY = math.max(0, (screenHeight - world.height) / 2)
  world.camera.x = cameraX - shakeX - letterboxX
  world.camera.y = cameraY - shakeY - letterboxY
  drawWorld()
  items:draw(world.camera)
  drawActiveEffects(world.camera)
  drawSpecialRoomContents()
  for _, enemy in ipairs(enemies) do
    if enemy.kind == 'fly' then
      enemy:draw(world.camera)
    else
      renderer:drawEnemy(enemy, world.camera)
    end
  end
  for _, projectile in ipairs(acidProjectiles) do
    renderer:drawAcidProjectile(projectile, world.camera)
  end
  for _, projectile in ipairs(sweatProjectiles) do
    renderer:drawSweatProjectile(projectile, world.camera)
  end
  for _, splash in ipairs(sweatSplashes) do
    renderer:drawSweatSplash(splash, world.camera)
  end
  renderer:drawCrawler(crawler, world.camera)
  renderer:drawGeometric(geometric, world.camera)
  renderer:drawStuffing(stuffing, world.camera)
  if stuffing and stuffing.projectiles then
    for _, projectile in ipairs(stuffing.projectiles) do
      renderer:drawStuffingProjectile(projectile, world.camera)
    end
  end
  renderer:drawBabyWidow(babyWidow, world.camera)
  if lilSnake then
    lilSnake:draw(world.camera)
  end
  renderer:drawPlayer(player, world.camera)
  renderer:drawFireFoam(player, world.camera, fireFoam.beam)
  items:drawStatNotifications(world.camera)
  world.camera.x, world.camera.y = cameraX, cameraY
  renderer:drawHud(player, items)
  renderer:drawActiveItem(items.heldActive, items.cooldownRemaining)
  renderer:drawMinimap(rooms, roomIndex, seenRooms, exploredRooms)
  drawCultistChoiceOverlay()
  if currentRoom and currentRoom.boss then
    renderer:drawBossHealthBar(crawler or lilSnake or geometric or stuffing)
  end
  if pickupNotification then
    renderer:drawPickupNotification(pickupNotification, pickupNotificationElapsed, pickupNotificationDuration)
  end
  love.graphics.setCanvas(previousCanvas)
  mainMenu.pauseCaptureDirty = false
end

function love.draw()
  love.graphics.clear(0.055, 0.07, 0.08)

  if gameState == 'opening_cutscene' and openingCutscene then
    local screenWidth, screenHeight = love.graphics.getDimensions()
    local videoWidth, videoHeight = openingCutscene:getDimensions()
    local scale = math.min(screenWidth / videoWidth, screenHeight / videoHeight)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      openingCutscene,
      (screenWidth - videoWidth * scale) / 2,
      (screenHeight - videoHeight * scale) / 2,
      0,
      scale,
      scale
    )
    love.graphics.setColor(0, 0, 0, 0.52)
    love.graphics.rectangle('fill', 0, screenHeight - 44, screenWidth, 44)
    love.graphics.setColor(1, 0.9, 0.78, 1)
    love.graphics.setFont(renderer.smallFont)
    love.graphics.printf('PRESS ANY KEY OR BUTTON TO SKIP', 0, screenHeight - 32, screenWidth, 'center')
    return
  elseif gameState == 'cutscene_fallback' then
    local width, height = love.graphics.getDimensions()
    love.graphics.setColor(0.035, 0.022, 0.018, 1)
    love.graphics.rectangle('fill', 0, 0, width, height)
    love.graphics.setColor(1, 0.68, 0.28, 1)
    love.graphics.setFont(renderer.bigFont)
    love.graphics.printf('CUTSCENE TEMPLATE', 0, height * 0.44, width, 'center')
    love.graphics.setColor(0.82, 0.75, 0.62, 1)
    love.graphics.setFont(renderer.smallFont)
    love.graphics.printf('PRESS ANY KEY OR BUTTON TO CONTINUE', 0, height * 0.56, width, 'center')
    return
  end

  if gameState == 'title' then
    mainMenu:draw(input)
    return
  end

  if gameState == 'character_select' then
    if bossDebugMenuOpen then
      renderer:drawBossDebugMenu(debugBosses, bossDebugSelection)
      return
    end
    local offsetX, offsetY = mainMenu:getTransitionOffset()
    love.graphics.push()
    love.graphics.translate(offsetX, offsetY)
    drawMenu()
    love.graphics.pop()
    mainMenu:drawTransitionOverlay(love.graphics.getWidth(), love.graphics.getHeight())
    return
  end

  if gameState == 'boss_intro' then
    renderer:drawBossIntro(bossIntroType, bossIntroTimer / 1.8)
    return
  end

  if gameState == 'floor_complete' then
    drawWorld()
    love.graphics.setColor(0.95, 0.92, 0.82, 1)
    love.graphics.setFont(renderer.bigFont)
    love.graphics.printf('BASEMENT CLEARED', 0, love.graphics.getHeight() / 2 - 20, love.graphics.getWidth(), 'center')
    return
  end

  if gameState == 'floor_transition' then
    drawWorld()
    local transitionDuration = floorTransitionSoundDuration or floorTransitionDuration
    local fadeInProgress = math.min(1, (floorTransitionTimer or 0) / floorTransitionFadeDuration)
    local fadeOutProgress = math.min(
      1,
      (transitionDuration - (floorTransitionTimer or 0)) / floorTransitionFadeDuration
    )
    local overlayAlpha = 0.96 * fadeInProgress * fadeOutProgress
    love.graphics.setColor(0.02, 0.025, 0.035, overlayAlpha)
    love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    local textAlpha = math.min(1, (floorTransitionTimer or 0) / 0.3) * fadeOutProgress
    love.graphics.setColor(0.95, 0.92, 0.82, textAlpha)
    love.graphics.setFont(renderer.floorIntroFont or renderer.bigFont)
    love.graphics.printf(
      floorTransitionFloorName or 'ASCENDING',
      0,
      love.graphics.getHeight() / 2 - 28,
      love.graphics.getWidth(),
      'center'
    )
    return
  end

  if gameState == 'game_over' then
    drawWorld()
    love.graphics.setColor(0.04, 0.01, 0.02, 0.82)
    love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    if deathScreenImage then
      local width, height = love.graphics.getDimensions()
      local imageWidth, imageHeight = deathScreenImage:getDimensions()
      local scale = math.min((width * 0.68) / imageWidth, (height * 0.74) / imageHeight)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        deathScreenImage,
        width / 2,
        height / 2,
        0,
        scale,
        scale,
        imageWidth / 2,
        imageHeight / 2
      )
    else
      love.graphics.setColor(0.95, 0.25, 0.2, 1)
      love.graphics.setFont(renderer.bigFont)
      love.graphics.printf('GAME OVER', 0, love.graphics.getHeight() / 2 - 20, love.graphics.getWidth(), 'center')
    end

    love.graphics.setColor(0.96, 0.89, 0.82, 1)
    love.graphics.setFont(renderer.smallFont)
    love.graphics.printf('PRESS R OR SPACE TO RESTART', 0, love.graphics.getHeight() * 0.84, love.graphics.getWidth(), 'center')
    return
  end

  if gameState == 'paused' then
    if mainMenu and mainMenu.pauseCaptureDirty then
      captureGameplayPauseFrame()
    end
    mainMenu:drawPause(input, items)
    return
  end

  local shakeX, shakeY = getScreenShakeOffset()
  local cameraX, cameraY = world.camera.x, world.camera.y
  local screenWidth, screenHeight = love.graphics.getDimensions()
  local letterboxX = math.max(0, (screenWidth - world.width) / 2)
  local letterboxY = math.max(0, (screenHeight - world.height) / 2)
  world.camera.x = cameraX - shakeX - letterboxX
  world.camera.y = cameraY - shakeY - letterboxY
  drawWorld()
  items:draw(world.camera)
  drawActiveEffects(world.camera)
  drawSpecialRoomContents()
  for _, enemy in ipairs(enemies) do
    if enemy.kind == 'fly' then
      enemy:draw(world.camera)
    else
      renderer:drawEnemy(enemy, world.camera)
    end
  end
  for _, projectile in ipairs(acidProjectiles) do
    renderer:drawAcidProjectile(projectile, world.camera)
  end
  for _, projectile in ipairs(sweatProjectiles) do
    renderer:drawSweatProjectile(projectile, world.camera)
  end
  for _, splash in ipairs(sweatSplashes) do
    renderer:drawSweatSplash(splash, world.camera)
  end
  renderer:drawCrawler(crawler, world.camera)
  renderer:drawGeometric(geometric, world.camera)
  renderer:drawStuffing(stuffing, world.camera)
  if stuffing and stuffing.projectiles then
    for _, projectile in ipairs(stuffing.projectiles) do
      renderer:drawStuffingProjectile(projectile, world.camera)
    end
  end
  renderer:drawBabyWidow(babyWidow, world.camera)
  if lilSnake then
    lilSnake:draw(world.camera)
  end
  renderer:drawPlayer(player, world.camera)
  renderer:drawFireFoam(player, world.camera, fireFoam.beam)
  items:drawStatNotifications(world.camera)
  world.camera.x, world.camera.y = cameraX, cameraY

  renderer:drawHud(player, items)
  renderer:drawActiveItem(items.heldActive, items.cooldownRemaining)
  renderer:drawMinimap(rooms, roomIndex, seenRooms, exploredRooms)
  drawCultistChoiceOverlay()
  if currentRoom and currentRoom.boss then
    renderer:drawBossHealthBar(crawler or lilSnake or geometric or stuffing)
  end
  if pickupNotification then
    renderer:drawPickupNotification(
      pickupNotification,
      pickupNotificationElapsed,
      pickupNotificationDuration
    )
  end
  if gameState == 'paused' then
    mainMenu:drawPause(input, items)
  elseif gameState == 'item_selector' then
    mainMenu:drawItemSelector(items)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function logFullscreenColorState(label)
  local width, height, flags = love.window.getMode()
  local fullscreen, fullscreenType = love.window.getFullscreen()
  local activeCanvas = love.graphics.getCanvas()
  local canvasDescription = 'default framebuffer'

  local function describeCanvas(canvas)
    local canvasWidth, canvasHeight = canvas:getDimensions()
    return string.format(
      '%dx%d (%s)',
      canvasWidth,
      canvasHeight,
      tostring(canvas:getFormat())
    )
  end

  if type(activeCanvas) == 'table' then
    local descriptions = {}
    for index, canvas in ipairs(activeCanvas) do
      descriptions[index] = describeCanvas(canvas)
    end
    canvasDescription = 'canvases: ' .. table.concat(descriptions, ', ')
  elseif activeCanvas then
    canvasDescription = describeCanvas(activeCanvas)
  end

  local dpiScale = love.window.getDPIScale and love.window.getDPIScale() or 'unavailable'
  local graphicsWidth, graphicsHeight = love.graphics.getDimensions()
  local red, green, blue, alpha = love.graphics.getColor()
  local clearRed, clearGreen, clearBlue, clearAlpha = love.graphics.getBackgroundColor()
  local blendMode, alphaMode = love.graphics.getBlendMode()
  print(string.format(
    '[display color audit: %s] mode=%dx%d graphics=%dx%d dpiScale=%s fullscreen=%s type=%s fullscreenFlag=%s borderless=%s canvas=%s drawColor=%.3f,%.3f,%.3f,%.3f clearColor=%.3f,%.3f,%.3f,%.3f blend=%s alphaMode=%s',
    label,
    width,
    height,
    graphicsWidth,
    graphicsHeight,
    tostring(dpiScale),
    tostring(fullscreen),
    tostring(fullscreenType),
    tostring(flags and flags.fullscreen),
    tostring(flags and flags.borderless),
    canvasDescription,
    red,
    green,
    blue,
    alpha,
    clearRed,
    clearGreen,
    clearBlue,
    clearAlpha,
    tostring(blendMode),
    tostring(alphaMode)
  ))
end

function love.resize(width, height)
  updateCameraSize()
  if gameState == 'playing' then
    player:update(0, input, world)
  end
  logFullscreenColorState(string.format(
    'resize callback %dx%d',
    width or love.graphics.getWidth(),
    height or love.graphics.getHeight()
  ))
end

function love.keypressed(key)
  if key == 'f' then
    logFullscreenColorState('before maximized/windowed toggle')
    if type(love.window.isMaximized) ~= 'function'
        or type(love.window.maximize) ~= 'function'
        or type(love.window.restore) ~= 'function' then
      print('Unable to toggle maximized window: this LÖVE version lacks window maximize APIs')
      return
    end

    local modeChanged, modeError = true, nil
    if love.window.isMaximized() then
      love.window.restore()
      modeChanged, modeError = love.window.setMode(
        1280,
        720,
        {
          fullscreen = false,
          borderless = false,
          resizable = true,
          centered = true,
        }
      )
    else
      love.window.maximize()
    end
    if not modeChanged then
      print('Unable to restore 1280x720 window mode: ' .. tostring(modeError))
      return
    end
    love.resize(love.graphics.getWidth(), love.graphics.getHeight())
    logFullscreenColorState('after maximized/windowed toggle')
    return
  end

  if gameState == 'opening_cutscene' or gameState == 'cutscene_fallback' then
    finishOpeningCutscene()
    return
  end

  if gameState == 'item_selector' then
    local action = mainMenu:itemSelectorKeypressed(key, items, player)
    if action == 'close' then
      resumePausedAudio()
      gameState = 'playing'
    end
    return
  end

  if gameState == 'paused' then
    if mainMenu.pendingBinding then
      mainMenu:pauseKeypressed(key, input)
    elseif key == 'p' then
      resumePausedAudio()
      gameState = 'playing'
    elseif key == 'escape' and mainMenu.pauseScreen == 'main'
        and mainMenu.backInputCooldown <= 0 then
      mainMenu.backInputCooldown = 0.28
      menuCancelSound:stop()
      menuCancelSound:play()
      resumePausedAudio()
      gameState = 'playing'
    else
      local action = mainMenu:pauseKeypressed(key, input)
      if action == 'resume' then
        resumePausedAudio()
        gameState = 'playing'
      elseif action == 'quit_to_title' then
        local saved, saveError = saveRun()
        if not saved then
          mainMenu.message = 'Save failed: ' .. tostring(saveError)
          print(mainMenu.message)
        end
        bossIntroMusic:stop()
        bossActiveStartMusic:stop()
        bossLoopMusic:stop()
        bossMusicPhase = nil
        stopBasementMusic(false)
        backgroundMusic:stop()
        gameState = 'title'
        mainMenu:resetNavigation('main')
        mainMenu.selection = 1
        mainMenu.cursorY = 0
      end
    end
    return
  end

  if gameState == 'game_over' and (key == 'r' or key == 'space') then
    restartRunAfterDeath()
    return
  end

  if gameState == 'playing' and (key == 'p' or key == 'escape') then
    mainMenu:openPause()
    pauseGameAudio()
    gameState = 'paused'
    return
  end

  if gameState == 'playing' and key == 'f7' then
    mainMenu:openItemSelector(items)
    pauseGameAudio()
    gameState = 'item_selector'
    return
  end

  if gameState == 'playing' and key == 'f8' then
    local nextFloorIndex = world.floorIndex % #FLOOR_TYPES + 1
    local loaded, loadError = loadFloor(nextFloorIndex)
    if not loaded then
      print('Unable to load debug floor: ' .. tostring(loadError))
    end
    return
  end

  if gameState == 'cultist_choice' then
    if key == '1' then
      chooseCultistPrice('health')
    elseif key == '2' then
      chooseCultistPrice('speed')
    elseif key == 'escape' then
      cultistChoiceActive = false
      gameState = 'playing'
    end
    return
  end

  if gameState == 'title' then
    local action = mainMenu:keypressed(key)
    if action == 'new_game' then
      beginNewRunSelection()
    elseif action == 'continue_run' then
      local loaded, loadError = continueRun()
      if not loaded then
        mainMenu.message = tostring(loadError)
        print(mainMenu.message)
      end
    elseif action == 'quit' then
      love.event.quit()
    end
    return
  end

  if gameState == 'character_select' then
    if bossDebugMenuOpen then
      if key == 'f7' or key == 'escape' or key == 'backspace' then
        bossDebugMenuOpen = false
      elseif key == 'up' or key == 'w' then
        bossDebugSelection = (bossDebugSelection - 2) % #debugBosses + 1
        menuSwitchSound:stop()
        menuSwitchSound:play()
      elseif key == 'down' or key == 's' then
        bossDebugSelection = bossDebugSelection % #debugBosses + 1
        menuSwitchSound:stop()
        menuSwitchSound:play()
      elseif key == 'return' or key == 'space' then
        startBossDebug(debugBosses[bossDebugSelection].type)
      end
    elseif key == 'f7' then
      bossDebugMenuOpen = true
      bossDebugSelection = 1
    elseif key == 'escape' or key == 'backspace' then
      if mainMenu:back() then
        gameState = 'title'
      end
    elseif key == 'left' or key == 'a' then
      changeCharacter(-1)
    elseif key == 'right' or key == 'd' then
      changeCharacter(1)
    elseif key == 'return' or key == 'space' then
      startGame()
    end
    return
  end

  if gameState == 'boss_intro' then
    return
  end

  if key == input.bindings.interact or key == 'return' then
    if tryShopPurchase() or tryCultistOffer() then
      return
    end
  end

  if key == 'q' then
    activateHeldItem()
    return
  end

end

function love.gamepadpressed(_, button)
  if gameState == 'opening_cutscene' or gameState == 'cutscene_fallback' then
    finishOpeningCutscene()
    return
  end

  if gameState == 'title' then
    local action = mainMenu:gamepadpressed(button)
    if action == 'new_game' then
      beginNewRunSelection()
    elseif action == 'continue_run' then
      local loaded, loadError = continueRun()
      if not loaded then
        mainMenu.message = tostring(loadError)
        print(mainMenu.message)
      end
    elseif action == 'quit' then
      love.event.quit()
    end
    return
  end

  if gameState == 'paused' then
    if button == 'start' then
      resumePausedAudio()
      gameState = 'playing'
    else
      local action = mainMenu:pauseGamepadpressed(button, input)
      if action == 'resume' then
        resumePausedAudio()
        gameState = 'playing'
      elseif action == 'quit_to_title' then
        local saved, saveError = saveRun()
        if not saved then
          mainMenu.message = 'Save failed: ' .. tostring(saveError)
          print(mainMenu.message)
        end
        bossIntroMusic:stop()
        bossActiveStartMusic:stop()
        bossLoopMusic:stop()
        bossMusicPhase = nil
        stopBasementMusic(false)
        backgroundMusic:stop()
        gameState = 'title'
        mainMenu:resetNavigation('main')
        mainMenu.selection = 1
        mainMenu.cursorY = 0
      end
    end
    return
  end

  if gameState == 'character_select' then
    if bossDebugMenuOpen then
      if button == 'b' then
        bossDebugMenuOpen = false
      elseif button == 'dpup' then
        bossDebugSelection = (bossDebugSelection - 2) % #debugBosses + 1
      elseif button == 'dpdown' then
        bossDebugSelection = bossDebugSelection % #debugBosses + 1
      elseif button == 'a' or button == 'start' then
        startBossDebug(debugBosses[bossDebugSelection].type)
      end
      return
    end
    if button == 'b' then
      if mainMenu:back() then
        gameState = 'title'
      end
    elseif button == 'dpleft' then
      changeCharacter(-1)
      menuSwitchSound:stop()
      menuSwitchSound:play()
    elseif button == 'dpright' then
      changeCharacter(1)
      menuSwitchSound:stop()
      menuSwitchSound:play()
    elseif button == 'a' or button == 'start' then
      menuSelectSound:stop()
      menuSelectSound:play()
      startGame()
    end
  end
end

function love.gamepadaxis(_, axis, value)
  if (gameState == 'opening_cutscene' or gameState == 'cutscene_fallback')
      and math.abs(value) > 0.6 then
    finishOpeningCutscene()
    return
  end

  if gameState == 'paused' then
    mainMenu:pauseGamepadaxis(axis, value, input)
    return
  end

  if gameState == 'title' then
    local action = mainMenu:gamepadaxis(axis, value)
    if action == 'new_game' then
      beginNewRunSelection()
    elseif action == 'continue_run' then
      local loaded, loadError = continueRun()
      if not loaded then
        mainMenu.message = tostring(loadError)
        print(mainMenu.message)
      end
    elseif action == 'quit' then
      love.event.quit()
    end

  end
end

function drawWorld()
  local camera = world.camera
  local tileSize = world.tileSize

  love.graphics.push()
  love.graphics.translate(-camera.x, -camera.y)

  local isShop = currentRoom and currentRoom.shop
  local isCultistDeal = currentRoom and currentRoom.cultistDeal
  local palette = FLOOR_PALETTES[world.floorType] or FLOOR_PALETTES.basement
  local baseRed = isShop and 0.16 or isCultistDeal and 0.13 or palette.base[1]
  local baseGreen = isShop and 0.22 or isCultistDeal and 0.08 or palette.base[2]
  local baseBlue = isShop and 0.12 or isCultistDeal and 0.16 or palette.base[3]
  love.graphics.setColor(baseRed, baseGreen, baseBlue)
  love.graphics.rectangle('fill', 0, 0, world.width, world.height)

  local floorType = world.floorType
  local animationTime = love.timer.getTime()
  if floorType == 'sky' then
    love.graphics.setColor(0.8, 0.91, 1, 0.28)
    for index = 1, 8 do
      local cloudX = (index * 183 + animationTime * 12 - camera.x * 0.3) % (world.width + 240) - 120
      local cloudY = 100 + (index * 137) % (world.height - 200)
      love.graphics.ellipse('fill', cloudX, cloudY, 96, 24)
      love.graphics.circle('fill', cloudX - 42, cloudY - 10, 25)
      love.graphics.circle('fill', cloudX + 32, cloudY - 14, 32)
    end
  end

  for x = 0, world.width, tileSize do
    for y = 0, world.height, tileSize do
      local alternating = (x / tileSize + y / tileSize) % 2 == 0
      if isShop then
        love.graphics.setColor(0.25 + (alternating and 0.03 or 0), 0.18, 0.08, 1)
      elseif isCultistDeal then
        love.graphics.setColor(0.18, 0.07 + (alternating and 0.025 or 0), 0.16, 1)
      elseif floorType == 'kitchen' then
        local shade = alternating and 0.035 or -0.015
        love.graphics.setColor(
          palette.tile[1] + shade, palette.tile[2] + shade, palette.tile[3] + shade, 1
        )
      elseif floorType == 'sky' then
        love.graphics.setColor(palette.tile[1], palette.tile[2], palette.tile[3], 0.18)
      else
        local stripe = (y / tileSize) % 2 == 0 and 0.025 or 0
        if floorType == 'bedroom' then
          stripe = alternating and 0.025 or -0.012
        end
        love.graphics.setColor(
          palette.tile[1] + stripe,
          palette.tile[2] + stripe,
          palette.tile[3] + stripe,
          1
        )
      end
      if floorType == 'sky' then
        love.graphics.rectangle('line', x + 1, y + 1, tileSize - 2, tileSize - 2)
      else
        love.graphics.rectangle('fill', x + 2, y + 2, tileSize - 4, tileSize - 4)
        love.graphics.setColor(0.055, 0.06, 0.065, 0.52)
        love.graphics.rectangle('line', x + 1, y + 1, tileSize - 2, tileSize - 2)
      end

      if floorType == 'living_room' or floorType == 'attic' then
        love.graphics.setColor(0.08, 0.045, 0.025, floorType == 'attic' and 0.45 or 0.32)
        love.graphics.line(x + 4, y + tileSize / 2, x + tileSize - 4, y + tileSize / 2)
        if (x / tileSize + y / tileSize) % 2 == 0 then
          love.graphics.line(x + tileSize / 2, y + 4, x + tileSize / 2, y + tileSize / 2)
        else
          love.graphics.line(x + tileSize / 2, y + tileSize / 2, x + tileSize / 2, y + tileSize - 4)
        end
      elseif floorType == 'roof' then
        love.graphics.setColor(0.035, 0.045, 0.06, 0.55)
        love.graphics.line(x + 5, y + tileSize / 2, x + tileSize - 5, y + tileSize / 2)
        love.graphics.line(x + tileSize / 2, y + tileSize / 2, x + tileSize / 2, y + tileSize - 4)
      elseif floorType == 'bedroom' then
        love.graphics.setColor(0.8, 0.72, 0.78, 0.17)
        for dotX = x + 12, x + tileSize - 12, 20 do
          love.graphics.circle('fill', dotX, y + tileSize / 2, 1.5)
        end
      end
    end
  end

  if currentRoom then
    for _, decoration in ipairs(currentRoom.layout.decorations or {}) do
      local style = decoration.style or decoration.type
      if decoration.width then
        if style == 'couch' then
          love.graphics.setColor(0.35, 0.13, 0.09, 1)
          love.graphics.rectangle('fill', decoration.x, decoration.y, decoration.width, decoration.height, 12, 12)
          love.graphics.setColor(0.55, 0.25, 0.16, 1)
          love.graphics.rectangle('fill', decoration.x + 12, decoration.y + 12, decoration.width - 24, decoration.height * 0.55, 8, 8)
        elseif style == 'table' or style == 'dresser' then
          love.graphics.setColor(style == 'table' and 0.36 or 0.28, 0.16, 0.08, 1)
          love.graphics.rectangle('fill', decoration.x, decoration.y, decoration.width, decoration.height, 5, 5)
          love.graphics.setColor(0.58, 0.38, 0.22, 1)
          love.graphics.rectangle('line', decoration.x + 5, decoration.y + 5, decoration.width - 10, decoration.height - 10, 3, 3)
        elseif style == 'counter' or style == 'cabinet' then
          love.graphics.setColor(0.36, 0.38, 0.34, 1)
          love.graphics.rectangle('fill', decoration.x, decoration.y, decoration.width, decoration.height)
          love.graphics.setColor(0.68, 0.69, 0.62, 1)
          love.graphics.rectangle('fill', decoration.x, decoration.y, decoration.width, 14)
          love.graphics.rectangle('line', decoration.x + 8, decoration.y + 20, decoration.width - 16, decoration.height - 28)
        elseif style == 'bed' then
          love.graphics.setColor(0.28, 0.18, 0.14, 1)
          love.graphics.rectangle('fill', decoration.x, decoration.y, decoration.width, decoration.height, 8, 8)
          love.graphics.setColor(0.67, 0.61, 0.67, 1)
          love.graphics.rectangle('fill', decoration.x + 14, decoration.y + 28, decoration.width - 28, decoration.height - 42, 8, 8)
          love.graphics.setColor(0.86, 0.82, 0.76, 1)
          love.graphics.rectangle('fill', decoration.x + 22, decoration.y + 34, 72, 36, 6, 6)
        elseif style == 'cloud_platform' then
          love.graphics.setColor(0.9, 0.97, 1, 0.9)
          love.graphics.ellipse('fill', decoration.x + decoration.width / 2, decoration.y + 12, decoration.width / 2, 22)
          love.graphics.circle('fill', decoration.x + 38, decoration.y + 5, 20)
          love.graphics.circle('fill', decoration.x + decoration.width - 32, decoration.y + 3, 24)
        else
          love.graphics.setColor(0.32, 0.25, 0.17, 1)
          love.graphics.rectangle('fill', decoration.x, decoration.y, decoration.width, decoration.height)
          love.graphics.setColor(0.7, 0.54, 0.32, 1)
          love.graphics.rectangle('line', decoration.x, decoration.y, decoration.width, decoration.height)
        end
      elseif style == 'cobweb' then
        love.graphics.setColor(0.82, 0.8, 0.72, 0.55)
        for segment = 0, 4 do
          love.graphics.line(decoration.x, decoration.y, decoration.x + (segment - 2) * 22, decoration.y + 56)
          love.graphics.line(decoration.x, decoration.y, decoration.x + 56, decoration.y + (segment - 2) * 22)
        end
      elseif style == 'rafter' then
        love.graphics.setColor(0.28, 0.19, 0.11, 1)
        love.graphics.rectangle('fill', 0, decoration.y, world.width, 20)
        love.graphics.setColor(0.52, 0.36, 0.22, 1)
        for rafterX = 80, world.width, 240 do
          love.graphics.rectangle('fill', rafterX, decoration.y, 22, 78)
        end
      elseif style == 'roof_edge' then
        love.graphics.setColor(0.12, 0.16, 0.21, 0.75)
        love.graphics.rectangle('fill', 0, 0, 26, world.height)
        love.graphics.rectangle('fill', world.width - 26, 0, 26, world.height)
        love.graphics.setColor(0.75, 0.35, 0.28, 0.8)
        love.graphics.line(34, 48, 34, world.height - 48)
        love.graphics.line(world.width - 34, 48, world.width - 34, world.height - 48)
      elseif style == 'cloud' then
        love.graphics.setColor(0.86, 0.95, 1, 0.7)
        local cloudX = (decoration.x + animationTime * 9 - camera.x * 0.35) % (world.width + 240) - 120
        love.graphics.ellipse('fill', cloudX, decoration.y, 90 * decoration.scale, 28 * decoration.scale)
        love.graphics.circle('fill', cloudX - 35, decoration.y - 8, 24 * decoration.scale)
        love.graphics.circle('fill', cloudX + 32, decoration.y - 12, 30 * decoration.scale)
      end
    end

    if floorType == 'bedroom' then
      for radius = 220, 40, -30 do
        love.graphics.setColor(0.78, 0.7, 0.9, 0.012)
        love.graphics.circle('fill', world.width / 2, world.height / 2, radius)
      end
    end

    for _, hole in ipairs(currentRoom.layout.floorHoles or {}) do
      love.graphics.setColor(0.035, 0.025, 0.02, 1)
      love.graphics.ellipse('fill', hole.x, hole.y + 5, hole.radius + 5, hole.radius * 0.72)
      love.graphics.setColor(0.25, 0.2, 0.16, 1)
      love.graphics.ellipse('line', hole.x, hole.y + 5, hole.radius + 5, hole.radius * 0.72)
      love.graphics.setColor(0.08, 0.06, 0.045, 1)
      love.graphics.ellipse('fill', hole.x, hole.y, hole.radius, hole.radius * 0.68)
    end
    love.graphics.setColor(isShop and 0.32 or isCultistDeal and 0.25 or 0.18, isShop and 0.2 or isCultistDeal and 0.08 or 0.17, isShop and 0.08 or isCultistDeal and 0.24 or 0.17, 1)
    for _, wall in ipairs(currentRoom.layout.walls) do
      love.graphics.rectangle('fill', wall.x, wall.y, wall.width, wall.height)
      love.graphics.setColor(0.28, 0.25, 0.22, 1)
      love.graphics.rectangle('line', wall.x, wall.y, wall.width, wall.height)
      love.graphics.setColor(0.18, 0.17, 0.17, 1)
    end
  end

  -- Thick concrete walls with exposed pipe accents around the room perimeter.
  love.graphics.setColor(0.23, 0.24, 0.24, 1)
  love.graphics.setLineWidth(18)
  love.graphics.rectangle('line', 9, 9, world.width - 18, world.height - 18)
  love.graphics.setColor(0.34, 0.3, 0.25, 0.9)
  love.graphics.setLineWidth(5)
  love.graphics.line(24, 34, world.width - 24, 34)
  love.graphics.line(world.width - 34, 34, world.width - 34, world.height - 24)

  local function drawDoor(direction, x, y, width, height)
    local destination = rooms[currentRoom.connections[direction]]
    local locked = doorsLocked or (currentRoom.doors and currentRoom.doors[direction]
      and currentRoom.doors[direction].locked)
    local color
    if destination and destination.roomType == 'shop' then
      color = locked and { 0.4, 0.13, 0.17, 1 } or { 0.66, 0.27, 0.31, 1 }
    elseif destination and destination.roomType == 'item' then
      color = locked and { 0.68, 0.45, 0.08, 1 } or { 1, 0.8, 0.2, 1 }
    else
      color = locked and { 0.45, 0.12, 0.08, 1 } or { 0.2, 0.75, 0.35, 1 }
    end
    love.graphics.setColor(color)
    love.graphics.rectangle('fill', x, y, width, height)
  end

  if currentRoom and currentRoom.connections.right and not (currentRoom.boss and currentRoom.dealDirection == 'right' and not currentRoom.dealUnlocked) then
    drawDoor('right', world.width - 24, world.height / 2 - 64, 24, 128)
  end
  if currentRoom and currentRoom.connections.left and not (currentRoom.boss and currentRoom.dealDirection == 'left' and not currentRoom.dealUnlocked) then
    drawDoor('left', 0, world.height / 2 - 64, 24, 128)
  end
  if currentRoom and currentRoom.connections.up and not (currentRoom.boss and currentRoom.dealDirection == 'up' and not currentRoom.dealUnlocked) then
    drawDoor('up', world.width / 2 - 64, 0, 128, 24)
  end
  if currentRoom and currentRoom.connections.down and not (currentRoom.boss and currentRoom.dealDirection == 'down' and not currentRoom.dealUnlocked) then
    drawDoor('down', world.width / 2 - 64, world.height - 24, 128, 24)
  end
  if currentRoom and currentRoom.boss and currentRoom.dealUnlocked and currentRoom.dealDirection then
    love.graphics.setColor(0.72, 0.18, 0.7, 1)
    if currentRoom.dealDirection == 'right' then
      love.graphics.rectangle('fill', world.width - 24, world.height / 2 - 64, 24, 128)
    elseif currentRoom.dealDirection == 'left' then
      love.graphics.rectangle('fill', 0, world.height / 2 - 64, 24, 128)
    elseif currentRoom.dealDirection == 'up' then
      love.graphics.rectangle('fill', world.width / 2 - 64, 0, 128, 24)
    else
      love.graphics.rectangle('fill', world.width / 2 - 64, world.height - 24, 128, 24)
    end
  end
  if ladder then
    drawLadder()
  end
  drawFloorBanner()
  if isShop or isCultistDeal then
    love.graphics.setColor(isShop and 0.95 or 0.76, isShop and 0.72 or 0.22, isShop and 0.2 or 0.8, 1)
    love.graphics.rectangle('fill', world.width / 2 - 110, 56, 220, 44)
    love.graphics.setColor(0.06, 0.04, 0.03, 1)
    love.graphics.setFont(renderer.smallFont)
    love.graphics.printf(isShop and 'SHOPKEEPER' or 'CULTIST DEAL', world.width / 2 - 110, 69, 220, 'center')
  end
  love.graphics.pop()
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

function drawLadder()
  if not ladder then
    return
  end

  local x = ladder.x
  local y = ladder.y
  if ladderImage then
    local imageScale = 1.7
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      ladderImage,
      math.floor(x),
      math.floor(y),
      0,
      imageScale,
      imageScale,
      ladderImage:getWidth() / 2,
      ladderImage:getHeight() / 2
    )
    return
  end

  love.graphics.setColor(0.08, 0.055, 0.04, 0.45)
  love.graphics.ellipse('fill', x, y + 26, 34, 10)
  love.graphics.setColor(0.58, 0.39, 0.2, 1)
  love.graphics.setLineWidth(8)
  love.graphics.line(x - 22, y - 30, x - 22, y + 28)
  love.graphics.line(x + 22, y - 30, x + 22, y + 28)
  love.graphics.setLineWidth(5)
  for rung = -20, 20, 10 do
    love.graphics.line(x - 22, y + rung, x + 22, y + rung)
  end
  love.graphics.setLineWidth(1)
end

local function spawnBossDeathParticles(boss)
  local particleCount = 32
  for _ = 1, particleCount do
    local radius = 12
    bossDeathParticles[#bossDeathParticles + 1] = {
      x = boss.x + math.random(-radius, radius),
      y = boss.y + math.random(-radius, radius),
      vx = math.random(-160, 160),
      vy = math.random(-190, 40),
      radius = math.random(2, 6),
      life = 0.9 + math.random() * 0.8,
      maxLife = 1.7,
      color = {
        1,
        0.46 + math.random() * 0.35,
        0.1 + math.random() * 0.18,
      },
    }
  end
end

function startFloorMusic()
  if world.floorType == 'kitchen' then
    startKitchenMusic()
  elseif world.floorType == 'basement' then
    startBasementMusic()
  elseif world.floorType == 'sky' then
    startSkyMusic()
  else
    stopKitchenMusic(false)
    stopBasementMusic(false)
    stopSkyMusic(false)
    setFloorMusicVolume()
    backgroundMusic:play()
  end
end

function startBossDeathSequence(boss)
  if not boss or boss.deathSequence then
    return
  end

  boss.isDying = true
  boss.deathSequence = {
    duration = 1.8,
    timer = 1.8,
    particles = {},
    explosion = 0,
  }
  bossDeathParticles = {}
  spawnBossDeathParticles(boss)
  bossDefeated = true
  isAudioLocked = false
  profile.bossesDefeated = profile.bossesDefeated + 1
  saveProfile()
  refreshMenuExtras()

  unlockBossRoom()
  hardStopMusicSources()
  bossMusicPhase = nil

  if bossDefeatSound then
    bossDefeatSound:setVolume(audioSfxVolume)
    bossDefeatSound:stop()
    bossDefeatSound:play()
  end
  triggerScreenShake(14)
end

function updateBossDeathParticles(dt)
  if not bossDeathParticles then
    bossDeathParticles = {}
    return
  end

  for index = #bossDeathParticles, 1, -1 do
    local particle = bossDeathParticles[index]
    if particle then
      particle.x = particle.x + (particle.vx or 0) * dt
      particle.y = particle.y + (particle.vy or 0) * dt
      particle.vy = (particle.vy or 0) + 120 * dt
      particle.life = (particle.life or 0) - dt
      if particle.life <= 0 then
        table.remove(bossDeathParticles, index)
      end
    else
      table.remove(bossDeathParticles, index)
    end
  end

  if screenShakeTime and screenShakeTime > 0 then
    screenShakeTime = math.max(0, screenShakeTime - dt)
  end
end

function updateBossDeathSequence(dt, boss)
  if not boss or not boss.deathSequence then
    return
  end

  local sequence = boss.deathSequence
  sequence.timer = math.max(0, sequence.timer - dt)
  sequence.explosion = math.min(1, (1.8 - sequence.timer) / 1.8)

  if sequence.timer <= 0 then
    if not sequence.finished then
      sequence.finished = true
      if crawler == boss then
        crawler = nil
      elseif lilSnake == boss then
        lilSnake = nil
      elseif geometric == boss then
        geometric = nil
      elseif stuffing == boss then
        stuffing = nil
      end
      startFloorMusic()
      unlockBossRoom()
    end
    return
  end

  bossDeathParticles = bossDeathParticles or {}
  for _, particle in ipairs(bossDeathParticles) do
    particle.x = particle.x + (math.random() - 0.5) * 18 * dt
    particle.y = particle.y + (math.random() - 0.5) * 18 * dt
  end
end

function areAllRoomEnemiesDefeated()
  for _, enemy in ipairs(enemies) do
    if enemy.alive then
      return false
    end
  end

  return (not crawler or not crawler.alive)
    and (not lilSnake or not lilSnake.alive)
    and (not geometric or not geometric.alive)
    and (not stuffing or not stuffing.alive)
    and (not babyWidow or not babyWidow.alive)
end

local function attachGeometricFeedback(boss)
  boss.onScreenShake = function(strength)
    triggerScreenShake(strength)
  end
end

function spawnRoomEnemies(room)
  enemies = {}
  crawler = nil
  lilSnake = nil
  geometric = nil
  stuffing = nil
  babyWidow = nil

  if room.cleared then
    return
  end

  for _, definition in ipairs(room.enemies) do
    local enemy
    if definition.type == 'scar' then
      enemy = Scar.new(definition)
    elseif definition.type == 'spider' then
      enemy = Spider.new(definition)
    elseif definition.type == 'fly' then
      enemy = Fly:new(definition.x, definition.y)
    elseif definition.type == 'centipede' then
      enemy = Centipede.new(definition)
    elseif definition.type == 'crawler' then
      crawler = Crawler.new(world)
    elseif definition.type == 'lilsnake' then
      lilSnake = LilSnake.new(world)
      room.layout.floorHoles = room.layout.floorHoles or {}
      lilSnake.holes = room.layout.floorHoles
    elseif definition.type == 'geometric' then
      geometric = TheGeometric.new(world)
      attachGeometricFeedback(geometric)
    elseif definition.type == 'stuffing' then
      stuffing = TheStuffing.new(world)
    else
      enemy = Enemy.new(definition)
    end
    if enemy then
      table.insert(enemies, enemy)
    end
  end
end

function enterRoom(index, entryDirection, skipBossIntro, suppressRoomReward)
  sweatProjectiles = {}
  sweatSplashes = {}
  roomIndex = index
  currentRoom = rooms[roomIndex]
  currentRoom.explored = true
  exploredRooms[roomIndex] = true
  seenRooms[roomIndex] = true
  for _, connectedId in pairs(currentRoom.connections) do
    seenRooms[connectedId] = true
  end
  roomRewardSpawned = currentRoom.cleared
  doorsLocked = not currentRoom.cleared
  for _, door in pairs(currentRoom.doors or {}) do
    door.locked = doorsLocked
  end
  shopOffers = nil
  cultistOffer = nil
  cultistChoiceActive = false
  if currentRoom.shop then
    if not currentRoom.shopOffers then
      currentRoom.shopOffers = {
        items:makeOffer('shop', world.width / 2 - 180, world.height / 2),
        items:makeOffer('shop', world.width / 2 + 180, world.height / 2),
      }
    end
    shopOffers = currentRoom.shopOffers
  elseif currentRoom.cultistDeal then
    if not currentRoom.cultistOffer then
      currentRoom.cultistOffer = items:makeOffer('cultistdeal', world.width / 2, world.height / 2)
    end
    cultistOffer = currentRoom.cultistOffer
  end
  if currentRoom.itemRoom and not currentRoom.rewardSpawned and not suppressRoomReward then
    currentRoom.rewardSpawned = items:spawnFloorReward(world.width / 2, world.height / 2)
  end
  spiderSpawnTimer = 0
  bossDefeated = currentRoom.cleared and currentRoom.boss or false
  bossIntroType = currentRoom.bossType or 'crawler'
  babyWidow = nil
  acidProjectiles = {}
  ladder = nil
  spawnRoomEnemies(currentRoom)
  if entryDirection == 'left' then
    player.x = world.width - 120
    player.y = world.height / 2
  elseif entryDirection == 'right' then
    player.x = 120
    player.y = world.height / 2
  elseif entryDirection == 'up' then
    player.x = world.width / 2
    player.y = world.height - 120
  elseif entryDirection == 'down' then
    player.x = world.width / 2
    player.y = 120
  else
    player.x = world.width / 2
    player.y = world.height / 2
  end

  if currentRoom.boss and not currentRoom.cleared and not skipBossIntro then
    stopBasementMusic(true)
    stopKitchenMusic(true)
    stopSkyMusic(false)
    backgroundMusic:stop()
    bossIntroMusic:stop()
    bossActiveStartMusic:stop()
    bossLoopMusic:stop()
    bossIntroMusic:play()
    bossMusicPhase = 'title'
    bossIntroTimer = 0
    gameState = 'boss_intro'
  else
    if currentRoom.boss and currentRoom.cleared and not ladder
        and world.floorIndex < #FLOOR_TYPES then
      ladder = { x = 104, y = 104 }
    end
    if world.floorType == 'kitchen' then
      startKitchenMusic()
    elseif world.floorType == 'basement' then
      startBasementMusic()
    elseif world.floorType == 'sky' then
      stopKitchenMusic(false)
      stopBasementMusic(false)
      if skyMusic and skyMusic:isPlaying() then
        skyMusic:setVolume(audioMusicVolume)
      else
        startSkyMusic()
      end
    else
      stopKitchenMusic(false)
      stopBasementMusic(false)
      stopSkyMusic(false)
      backgroundMusic:play()
    end
    gameState = 'playing'
  end
  if not suppressRoomReward and saveRun then
    local saved, saveError = saveRun()
    if not saved then
      mainMenu.message = 'Save failed: ' .. tostring(saveError)
      print(mainMenu.message)
    end
  end
end

function tryRoomTransition()
  if not currentRoom then
    return false
  end

  if currentRoom.boss and not currentRoom.dealUnlocked then
    return false
  end

  local direction
  if player.x >= world.width - 104 and currentRoom.connections.right then
    direction = 'right'
  elseif player.x <= 104 and currentRoom.connections.left then
    direction = 'left'
  elseif player.y <= 104 and currentRoom.connections.up then
    direction = 'up'
  elseif player.y >= world.height - 104 and currentRoom.connections.down then
    direction = 'down'
  end

  if currentRoom.boss then
    direction = currentRoom.dealDirection
    local atDoor = direction == 'right' and player.x >= world.width - 104
      or direction == 'left' and player.x <= 104
      or direction == 'up' and player.y <= 104
      or direction == 'down' and player.y >= world.height - 104
    if not atDoor then
      return false
    end
  end

  if not direction then
    return false
  end

  enterRoom(currentRoom.connections[direction], direction == 'right' and 'right'
    or direction == 'left' and 'left'
    or direction == 'up' and 'up'
    or 'down')
  return true
end

function love.mousemoved(x, y)
  if gameState == 'title' then
    mainMenu:mousemoved(x, y)
  end
end

function love.mousepressed(x, y, button)
  if gameState == 'opening_cutscene' or gameState == 'cutscene_fallback' then
    finishOpeningCutscene()
    return
  end

  if gameState == 'item_selector' and button == 1 then
    mainMenu:itemSelectorClick(x, y, items, player)
    return
  end

  if button ~= 1 then
    return
  end

  function love.wheelmoved(_, y)
    if gameState == 'item_selector' then
      mainMenu:moveItemSelector(-y * 3)
    end
  end

  function love.textinput(text)
    if gameState == 'item_selector' then
      mainMenu:itemSelectorTextinput(text, items)
    end
  end

  if gameState == 'title' then
    local action = mainMenu:mousepressed(x, y)
    if action == 'new_game' then
      beginNewRunSelection()
    elseif action == 'continue_run' then
      local loaded, loadError = continueRun()
      if not loaded then
        mainMenu.message = tostring(loadError)
        print(mainMenu.message)
      end
    elseif action == 'quit' then
      love.event.quit()
    end
  elseif gameState == 'character_select' then
    if not bossDebugMenuOpen then
      startGame()
    end
  end
end

function changeCharacter(direction)
  characterIndex = (characterIndex - 1 + direction) % #characters + 1
  selectedCharacter = characters[characterIndex]
  characterCarouselTarget = characterIndex
end

function startGame(debugBossType)
  if selectedCharacter and selectedCharacter.isUnlocked == false then
    if menuSelectSound then
      menuSelectSound:stop()
      menuSelectSound:play()
    end
    return false
  end

  local saveCleared, clearError = clearSavedRun()
  if not saveCleared then
    mainMenu.message = clearError
    print(clearError)
    return false
  end
  resetPlayerRunState()
  local debugBoss
  if debugBossType then
    for _, boss in ipairs(debugBosses) do
      if boss.type == debugBossType then
        debugBoss = boss
        break
      end
    end
    assert(debugBoss, 'Unknown debug boss: ' .. tostring(debugBossType))
    world.floorIndex = debugBoss.floorIndex
    world.floorType = floorTypeForIndex(world.floorIndex)
    world.roomType = world.floorType
  end
  runSeed = math.random(1, 2147483646)
  math.randomseed(runSeed)
  if selectedCharacter.spriteSheetPath then
    renderer:setCharacter(selectedCharacter.spriteSheetPath)
  end
  rooms = generateCurrentFloorRooms(runSeed)
  local bossRoomIndex
  if debugBoss then
    for index, room in ipairs(rooms) do
      if room.boss then
        bossRoomIndex = index
        room.bossType = debugBoss.type
        room.name = debugBoss.name
        room.enemies = { { type = debugBoss.type } }
        break
      end
    end
    assert(bossRoomIndex, 'Generated floor has no boss room for debug run.')
  end
  if world.floorType == 'kitchen' then
    startKitchenMusic()
  elseif world.floorType == 'basement' then
    startBasementMusic()
  else
    stopKitchenMusic(false)
    stopBasementMusic(false)
    setFloorMusicVolume()
    backgroundMusic:play()
  end
  exploredRooms = {}
  seenRooms = {}
  isPickingUpItem = false
  pickupTimer = 0
  pickupNotification = nil
  pickupNotificationElapsed = 0
  waitingForPickupSound = false
  bossDebugMenuOpen = false
  enterRoom(debugBoss and bossRoomIndex or 1, nil, debugBoss ~= nil)
  profile.runsStarted = profile.runsStarted + 1
  saveProfile()
  refreshMenuExtras()
  return true
end

function startBossDebug(bossType)
  return startGame(bossType)
end

function spawnSpider()
  local offset = 58
  local x = crawler.x
  local y = crawler.y
  local margin = world.tileSize * 0.8

  if crawler.y <= margin + 1 then
    y = y + offset
  elseif crawler.x >= world.width - margin - 1 then
    x = x - offset
  elseif crawler.y >= world.height - margin - 1 then
    y = y - offset
  else
    x = x + offset
  end

  table.insert(enemies, Spider.new({ x = x, y = y }))
end

function spawnBabyWidow()
  if babyWidow or not crawler then
    return
  end

  babyWidow = BabyWidow.new(world, {
    onDamaged = function()
      babyWidowSounds.coughing:play()
    end,
    onDeath = function()
      babyWidowSounds.death:play()
    end,
    onAttackStart = function()
      babyWidowSounds.inhale:play()
    end,
    onAttackRelease = function(targetX, targetY)
      triggerScreenShake(14)
      babyWidowSounds.throwup:play()
      table.insert(acidProjectiles, AcidProjectile.new(babyWidow.x, babyWidow.y, targetX, targetY))
    end,
  })
  babyWidow.x = crawler.x
  babyWidow.y = crawler.y
  babyWidowSounds.enter:play()
end

function spawnBabySpider()
  if not babyWidow then
    return
  end

  local offset = 52
  local x = babyWidow.x
  local y = babyWidow.y
  local margin = world.tileSize * 0.8

  if babyWidow.y <= margin + 1 then
    y = y + offset
  elseif babyWidow.x >= world.width - margin - 1 then
    x = x - offset
  elseif babyWidow.y >= world.height - margin - 1 then
    y = y - offset
  else
    x = x + offset
  end

  babyWidowSounds.summon:play()
  table.insert(enemies, Spider.new({ x = x, y = y }))
end

function drawMenu()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  mainMenu:drawCharacterSelectBackground(width, height)
  renderer:drawCharacterCarousel(characters, characterCarouselPosition)
end

function playFloorTransitionSound()
  if floorTransitionSound then
    floorTransitionSound:stop()
    floorTransitionSound:play()
    floorTransitionSoundDuration = floorTransitionSound:getDuration()
  else
    floorTransitionSoundDuration = floorTransitionDuration
  end
end

function drawFloorBanner()
  if not renderer or not world then
    return
  end

  local floorName = currentFloorDisplayName or getFloorDisplayName(world.floorType)
  if not floorName or floorName == '' or currentFloorBannerTimer <= 0 then
    return
  end

  local width = love.graphics.getWidth()
  local screenHeight = love.graphics.getHeight()
  local y = screenHeight * 0.18
  local alpha = math.max(0, 1 - (3 - currentFloorBannerTimer) / 3)
  local font = renderer.floorIntroFont or renderer.bigFont
  love.graphics.setFont(font)
  love.graphics.setColor(0, 0, 0, 0.48 * alpha)
  love.graphics.printf(floorName, 0, y + 6, width, 'center')
  love.graphics.setColor(0.96, 0.94, 0.89, alpha)
  love.graphics.printf(floorName, 0, y, width, 'center')
  love.graphics.setColor(1, 1, 1, 1)
end

function updateBasementMusicFade(dt)
  if not basementMusicFade then
    return
  end

  basementMusicFade.elapsed = math.min(basementMusicFade.elapsed + dt, basementMusicFade.duration)
  local progress = basementMusicFade.elapsed / basementMusicFade.duration
  local volume = (basementMusicFade.from
    + (basementMusicFade.to - basementMusicFade.from) * progress) * audioMusicVolume
  basementOscMusic:setVolume(volume)

  if progress >= 1 then
    local stopping = basementMusicFade.to == 0
    basementMusicFade = nil
    if stopping then
      basementOscMusic:stop()
      basementOscMusic:setVolume(0)
    end
  end
end

function updateKitchenMusicFade(dt)
  if not kitchenMusicFade then
    return
  end

  kitchenMusicFade.elapsed = math.min(kitchenMusicFade.elapsed + dt, kitchenMusicFade.duration)
  local progress = kitchenMusicFade.elapsed / kitchenMusicFade.duration
  local volume = (kitchenMusicFade.from + (kitchenMusicFade.to - kitchenMusicFade.from) * progress) * audioMusicVolume
  if kitchenMusic then
    kitchenMusic:setVolume(volume)
  end

  if progress >= 1 then
    local stopping = kitchenMusicFade.to == 0
    kitchenMusicFade = nil
    if stopping and kitchenMusic then
      kitchenMusic:stop()
      kitchenMusic:setVolume(0)
    end
  end
end

updateMainMenuMusic = function(dt)
  local shouldPlay = gameState == 'title' or gameState == 'character_select'
  if shouldPlay ~= menuMusicActive then
    menuMusicActive = shouldPlay
    local currentVolume = menuMusic:getVolume()
    if shouldPlay then
      if not menuMusic:isPlaying() then
        menuMusic:play()
      end
      menuMusicFade = { elapsed = 0, duration = 0.75, from = currentVolume, to = audioMusicVolume }
    elseif menuMusic:isPlaying() then
      menuMusicFade = { elapsed = 0, duration = 0.75, from = currentVolume, to = 0 }
    end
  end

  if not menuMusicFade then
    return
  end

  menuMusicFade.elapsed = math.min(menuMusicFade.elapsed + dt, menuMusicFade.duration)
  local progress = menuMusicFade.elapsed / menuMusicFade.duration
  local volume = menuMusicFade.from + (menuMusicFade.to - menuMusicFade.from) * progress
  menuMusic:setVolume(volume)

  if progress >= 1 then
    local stopping = menuMusicFade.to == 0
    menuMusicFade = nil
    if stopping then
      menuMusic:stop()
    end
  end
end

function startBasementMusic()
  if isAudioLocked then
    return
  end
  if not basementOscMusic then
    return
  end

  if basementOscMusic:isPlaying() then
    basementMusicFade = nil
    basementOscMusic:setVolume(audioMusicVolume)
    return
  end

  basementOscMusic:stop()
  basementOscMusic:setVolume(0)
  basementOscMusic:play()
  basementMusicFade = { elapsed = 0, duration = 0.75, from = 0, to = 1 }
end

function stopBasementMusic(fade)
  if not basementOscMusic then
    return
  end

  if not fade then
    basementOscMusic:stop()
    basementOscMusic:setVolume(0)
    basementMusicFade = nil
    return
  end

  local currentVolume = basementOscMusic:getVolume()
  if audioMusicVolume > 0 then
    currentVolume = currentVolume / audioMusicVolume
  end
  basementMusicFade = { elapsed = 0, duration = 0.75, from = currentVolume, to = 0 }
end

function startKitchenMusic()
  if isAudioLocked then
    return
  end
  if not kitchenMusic then
    return
  end

  if kitchenMusic:isPlaying() then
    kitchenMusicFade = nil
    kitchenMusic:setVolume(audioMusicVolume)
    return
  end

  stopBasementMusic(false)
  backgroundMusic:stop()
  kitchenMusic:stop()
  kitchenMusic:setVolume(0)
  kitchenMusic:play()
  kitchenMusicFade = { elapsed = 0, duration = 0.75, from = 0, to = 1 }
end

function stopKitchenMusic(fade)
  if not kitchenMusic then
    return
  end

  if not fade then
    kitchenMusic:stop()
    kitchenMusic:setVolume(0)
    kitchenMusicFade = nil
    return
  end

  local currentVolume = kitchenMusic:getVolume()
  if audioMusicVolume > 0 then
    currentVolume = currentVolume / audioMusicVolume
  end
  kitchenMusicFade = { elapsed = 0, duration = 0.75, from = currentVolume, to = 0 }
end

function startSkyMusic()
  if isAudioLocked then
    return
  end
  if not skyMusic then
    return
  end

  if skyMusic:isPlaying() then
    skyMusicFade = nil
    skyMusic:setVolume(audioMusicVolume)
    return
  end

  stopBasementMusic(false)
  stopKitchenMusic(false)
  if backgroundMusic then
    backgroundMusic:stop()
    backgroundMusic:setVolume(0)
  end
  if not skyMusic:isPlaying() then
    skyMusic:stop()
    skyMusic:setVolume(0)
    skyMusic:play()
  end
  skyMusicFade = { elapsed = 0, duration = 0.75, from = 0, to = 1 }
end

function stopSkyMusic(fade)
  if not skyMusic then
    return
  end

  if not fade then
    skyMusic:stop()
    skyMusic:setVolume(0)
    skyMusicFade = nil
    return
  end

  local currentVolume = skyMusic:getVolume()
  if audioMusicVolume > 0 then
    currentVolume = currentVolume / audioMusicVolume
  end
  skyMusicFade = { elapsed = 0, duration = 0.75, from = currentVolume, to = 0 }
end

function updateSkyMusicFade(dt)
  if not skyMusicFade then
    return
  end

  skyMusicFade.elapsed = math.min(skyMusicFade.elapsed + dt, skyMusicFade.duration)
  local progress = skyMusicFade.elapsed / skyMusicFade.duration
  local volume = (skyMusicFade.from + (skyMusicFade.to - skyMusicFade.from) * progress) * audioMusicVolume
  if skyMusic then
    skyMusic:setVolume(volume)
  end

  if progress >= 1 then
    local stopping = skyMusicFade.to == 0
    skyMusicFade = nil
    if stopping and skyMusic then
      skyMusic:stop()
      skyMusic:setVolume(0)
    end
  end
end

function pauseGameAudio()
  local function duck(source)
    if source then
      source:setVolume(0)
      if source:isPlaying() then
        source:pause()
      end
    end
  end

  duck(backgroundMusic)
  duck(bossIntroMusic)
  duck(bossActiveStartMusic)
  duck(bossLoopMusic)
  duck(basementOscMusic)
  duck(kitchenMusic)
  duck(skyMusic)
end

function resumeGameAudio()
  if isAudioLocked then
    return
  end

  local function restore(source, targetVolume)
    if source and targetVolume ~= nil then
      source:setVolume(targetVolume)
      if not source:isPlaying() then
        source:play()
      end
    end
  end

  if world.floorType == 'basement' then
    if not bossDefeated then
      restore(basementOscMusic, audioMusicVolume)
    end
  elseif world.floorType == 'kitchen' then
    if kitchenMusic and not bossDefeated then
      restore(kitchenMusic, audioMusicVolume)
    end
  elseif world.floorType == 'sky' then
    if backgroundMusic then
      backgroundMusic:stop()
      backgroundMusic:setVolume(0)
    end

    local bossEncounterActive = currentRoom and currentRoom.boss and not currentRoom.cleared
    local bossBattleActive = bossEncounterActive or (currentRoom and currentRoom.boss and (crawler or lilSnake or geometric or stuffing))
    if bossBattleActive or gameState == 'boss_intro' then
      if skyMusic then
        skyMusic:stop()
        skyMusic:setVolume(0)
      end
      return
    end

    if skyMusic and not bossDefeated then
      restore(skyMusic, audioMusicVolume)
    end
  else
    restore(backgroundMusic, audioMusicVolume * math.min(1, 0.75 + math.max(0, (world and world.floorIndex or 1) - 1) * 0.04))
  end
end

function resumePausedAudio()
  if isAudioLocked then
    return
  end

  local activeBoss = crawler or lilSnake or geometric or stuffing
  if currentRoom and currentRoom.boss and activeBoss and activeBoss.alive then
    if bossMusicPhase == 'active_start' then
      bossActiveStartMusic:play()
      bossLoopMusic:setVolume(0)
      bossLoopMusic:play()
    else
      bossLoopMusic:setVolume(audioMusicVolume)
      bossLoopMusic:play()
    end
  else
    resumeGameAudio()
  end
end

function playerTouchesLadder()
  if not ladder then
    return false
  end

  local distanceX = player.x - ladder.x
  local distanceY = player.y - ladder.y
  return distanceX * distanceX + distanceY * distanceY <= 72 * 72
end

function transitionToNextFloor()
  if world.floorIndex >= #FLOOR_TYPES then
    return false
  end

  isAudioLocked = true
  stopBasementMusic(false)
  stopKitchenMusic(false)
  stopSkyMusic(false)
  hardStopMusicSources()
  bossIntroMusic:stop()
  bossActiveStartMusic:stop()
  bossLoopMusic:stop()
  bossMusicPhase = nil
  playFloorTransitionSound()
  floorTransitionTimer = 0
  floorTransitionTargetIndex = world.floorIndex + 1
  local nextFloorType = floorTypeForIndex(floorTransitionTargetIndex)
  floorTransitionFloorName = getFloorDisplayName(nextFloorType)
  floorTransitionLoaded = false
  floorTransitionSoundDuration = floorTransitionSound and floorTransitionSound:getDuration() or floorTransitionDuration
  pauseGameAudio()
  playFloorTransitionSound()
  gameState = 'floor_transition'
  return true
end

loadFloor = function(floorIndex)
  runSeed = runSeed or love.math.random(1, 9999999)
  if not runSeed or type(runSeed) ~= 'number' then
    runSeed = love.math.random(1, 9999999)
  end

  local nextFloorType = floorTypeForIndex(floorIndex)
  if not nextFloorType then
    return false, 'Unsupported floor index: ' .. tostring(floorIndex)
  end

  isAudioLocked = false
  stopBasementMusic(false)
  stopKitchenMusic(false)
  stopSkyMusic(false)
  bossIntroMusic:stop()
  bossActiveStartMusic:stop()
  bossLoopMusic:stop()
  bossMusicPhase = nil
  backgroundMusic:stop()

  world.floorIndex = floorIndex
  world.floorType = nextFloorType
  world.roomType = nextFloorType
  if player then
    player.currentFloorType = world.floorType
  end
  updatePlayerSpriteForFloor()
  currentFloorDisplayName = getFloorDisplayName(nextFloorType)
  currentFloorBannerTimer = 3
  bossDefeated = false
  rooms = Rooms.generate(15, nextFloorType, runSeed + floorIndex, floorIndex)
  roomIndex = 1
  currentRoom = nil
  exploredRooms = {}
  seenRooms = {}
  enemies = {}
  crawler = nil
  lilSnake = nil
  geometric = nil
  babyWidow = nil
  acidProjectiles = {}
  ladder = nil
  bossDeathParticles = {}
  roomRewardSpawned = false
  doorsLocked = true
  if world.floorType == 'basement' then
    startBasementMusic()
  elseif world.floorType == 'kitchen' then
    startKitchenMusic()
  elseif world.floorType == 'sky' then
    if backgroundMusic then
      backgroundMusic:stop()
      backgroundMusic:setVolume(0)
    end
    startSkyMusic()
  else
    setFloorMusicVolume()
    backgroundMusic:play()
  end
  enterRoom(1)
  return true
end

function finishFloorTransition()
  local transitionDuration = (floorTransitionSound and floorTransitionSound:getDuration()) or floorTransitionDuration
  if not floorTransitionLoaded and floorTransitionTimer >= transitionDuration then
    local loaded, loadError = loadFloor(floorTransitionTargetIndex)
    if not loaded then
      print('Floor transition failed: ' .. tostring(loadError))
      isAudioLocked = false
      gameState = 'playing'
      floorTransitionTimer = nil
      floorTransitionTargetIndex = nil
      floorTransitionFloorName = nil
      floorTransitionLoaded = nil
      return false
    end
    floorTransitionLoaded = true
  end

  if floorTransitionTimer >= transitionDuration + 0.08 then
    isAudioLocked = false
    gameState = 'playing'
    floorTransitionTimer = nil
    floorTransitionTargetIndex = nil
    floorTransitionFloorName = nil
    floorTransitionLoaded = nil
  end
  return true
end

function triggerScreenShake(strength)
  if not screenShakeEnabled then
    return
  end
  screenShakeTime = screenShakeDuration
  screenShakeStrength = math.max(screenShakeStrength or 0, strength)
end

function getScreenShakeOffset()
  if not screenShakeTime or screenShakeTime <= 0 then
    return 0, 0
  end

  local progress = screenShakeTime / screenShakeDuration
  local strength = screenShakeStrength * progress * progress
  return (math.random() * 2 - 1) * strength, (math.random() * 2 - 1) * strength
end

function getOfferDistance(offer)
  local distanceX = player.x - offer.x
  local distanceY = player.y - offer.baseY
  return math.sqrt(distanceX * distanceX + distanceY * distanceY)
end

function tryShopPurchase()
  if not shopOffers then
    return false
  end
  for _, offer in ipairs(shopOffers) do
    if not offer.purchased and getOfferDistance(offer) <= 100 then
      local price = offer.definition.shopPrice
      if player.stats.dollars >= price then
        player.stats.dollars = player.stats.dollars - price
        items:acquire(offer.definition, player)
        offer.purchased = true
        pickupNotification = offer.definition
        pickupNotificationElapsed = 0
      end
      return true
    end
  end
  return false
end

function tryCultistOffer()
  if not cultistOffer or cultistOffer.purchased or getOfferDistance(cultistOffer) > 110 then
    return false
  end
  cultistChoiceActive = true
  gameState = 'cultist_choice'
  return true
end

function chooseCultistPrice(stat)
  if stat == 'health' then
    player:reduceMaxHealth(20)
  else
    player.speed = math.max(40, player.speed - 15)
  end
  items:acquire(cultistOffer.definition, player)
  cultistOffer.purchased = true
  pickupNotification = cultistOffer.definition
  pickupNotificationElapsed = 0
  cultistChoiceActive = false
  gameState = player.stats.health <= 0 and 'game_over' or 'playing'
end

function drawSpecialRoomContents()
  local function drawOffer(offer)
    if not offer or offer.purchased then
      return
    end
    local definition = offer.definition
    local screenX = math.floor(offer.x - world.camera.x)
    local screenY = math.floor(offer.baseY - world.camera.y + math.sin(offer.timer or 0) * 3)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(definition.image, screenX, screenY, 0, 2, 2, definition.image:getWidth() / 2, definition.image:getHeight() / 2)
    love.graphics.setColor(0.98, 0.88, 0.45, 1)
    love.graphics.setFont(renderer.smallFont)
    love.graphics.printf(definition.name, screenX - 100, screenY + 44, 200, 'center')
    if currentRoom.shop then
      love.graphics.printf(string.format('$%d', definition.shopPrice), screenX - 100, screenY + 62, 200, 'center')
    else
      love.graphics.printf('Choose a card: E', screenX - 100, screenY + 62, 200, 'center')
    end
  end

  local activeBoss = crawler or lilSnake or geometric or stuffing
  if activeBoss and activeBoss.deathSequence then
    local progress = 1 - activeBoss.deathSequence.timer / activeBoss.deathSequence.duration
    local radius = 18 + progress * 110
    love.graphics.setColor(1, 0.52 + progress * 0.46, 0.1, 0.8 - progress * 0.7)
    love.graphics.circle('line', math.floor(activeBoss.x - world.camera.x), math.floor(activeBoss.y - world.camera.y), radius)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if #bossDeathParticles > 0 then
    for _, particle in ipairs(bossDeathParticles) do
      love.graphics.setColor(particle.color[1], particle.color[2], particle.color[3], math.max(0, particle.life / particle.maxLife))
      love.graphics.circle('fill', math.floor(particle.x - world.camera.x), math.floor(particle.y - world.camera.y), particle.radius)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  if currentRoom and currentRoom.shop then
    for _, offer in ipairs(shopOffers or {}) do
      drawOffer(offer)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(string.format('Dollars: $%d | E to buy', player.stats.dollars), 0, 128, world.camera.width, 'center')
  elseif currentRoom and currentRoom.cultistDeal then
    drawOffer(cultistOffer)
  end
end

function drawCultistChoiceOverlay()
  if not cultistChoiceActive then
    return
  end
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  love.graphics.setColor(0.03, 0.015, 0.04, 0.94)
  love.graphics.rectangle('fill', 0, 0, width, height)
  love.graphics.setColor(0.95, 0.82, 0.55, 1)
  love.graphics.setFont(renderer.bigFont)
  love.graphics.printf('CHOOSE YOUR PRICE', 0, 34, width, 'center')
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(cultistCardImages.health, width / 2 - 170, height / 2 - 90, 0, 4, 4, 16, 16)
  love.graphics.draw(cultistCardImages.speed, width / 2 + 170, height / 2 - 90, 0, 4, 4, 16, 16)
  love.graphics.setFont(renderer.smallFont)
  love.graphics.printf('1: Lose 1 heart container', width / 2 - 250, height / 2 + 100, 200, 'center')
  love.graphics.printf('2: Lose 15 speed', width / 2 + 50, height / 2 + 100, 200, 'center')
  love.graphics.printf('Esc: Leave the deal', 0, height - 44, width, 'center')
end