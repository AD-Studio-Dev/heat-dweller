-- Rendering for the player and character atlas.
local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(atlas)
  local self = setmetatable({}, Renderer)
  self.atlas = atlas
  self.image = nil
  self.quads = {}
  return self
end

function Renderer:load()
  self.image = love.graphics.newImage(self.atlas.image)
  self.image:setFilter('nearest', 'nearest')
  local imageWidth, imageHeight = self.image:getDimensions()

  for name, frame in pairs(self.atlas.frames) do
    self.quads[name] = love.graphics.newQuad(
      frame.x, frame.y, frame.w, frame.h, imageWidth, imageHeight
    )
  end
end

function Renderer:drawPlayer(game, camera)
  if not self.image then
    return
  end

  local bodyFrame = game:getBodyFrame()
  local headFrame = game:getHeadFrame()
  local drawX = math.floor(game.player.x - camera.x - game.player.width / 2)
  local drawY = math.floor(game.player.y - camera.y - game.player.height / 2)
  local scaleX = game.player.facing == 'left' and -1 or 1
  local offsetX = scaleX < 0 and game.player.width or 0
  local scale = 2

  self:drawFrame(bodyFrame, drawX + offsetX, drawY, scaleX * scale, scale)
  if not game.player.isHurt then
    self:drawFrame(headFrame, drawX + offsetX, drawY, scaleX * scale, scale)
  end
end

function Renderer:drawFrame(frameName, x, y, scaleX, scaleY)
  local quad = self.quads[frameName]
  if quad then
    love.graphics.draw(self.image, quad, math.floor(x), math.floor(y), 0, scaleX, scaleY)
  end
end

return Renderer