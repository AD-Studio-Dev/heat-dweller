-- Character atlas data and LÖVE Quad creation.
---@diagnostic disable: undefined-global
local Atlas = {
  imagePath = 'resources/gfx/characters/character_001_matthew.png',
  frames = {
    head_forward_1 = { x = 0, y = 0, w = 40, h = 40 },
    head_forward_blink = { x = 40, y = 0, w = 40, h = 40 },
    head_right_1 = { x = 80, y = 0, w = 40, h = 40 },
    head_right_blink = { x = 120, y = 0, w = 40, h = 40 },
    head_back_1 = { x = 160, y = 0, w = 40, h = 40 },
    head_back_blink = { x = 200, y = 0, w = 40, h = 40 },

    body_idle = { x = 0, y = 40, w = 40, h = 40 },
    walk_down_0 = { x = 40, y = 40, w = 40, h = 40 },
    walk_down_1 = { x = 80, y = 40, w = 40, h = 40 },
    walk_down_2 = { x = 120, y = 40, w = 40, h = 40 },
    walk_down_3 = { x = 160, y = 40, w = 40, h = 40 },
    walk_down_4 = { x = 200, y = 40, w = 40, h = 40 },

    walk_right_0 = { x = 120, y = 80,  w = 40, h = 40 },
    walk_right_1 = { x = 160, y = 80,  w = 40, h = 40 },
    walk_right_2 = { x = 200, y = 80,  w = 40, h = 40 },
    walk_right_3 = { x = 0,   y = 120, w = 40, h = 40 },
    walk_right_4 = { x = 40,  y = 120, w = 40, h = 40 },
    walk_right_5 = { x = 80,  y = 120, w = 40, h = 40 },
    walk_right_6 = { x = 120, y = 120, w = 40, h = 40 },

    hurt_0 = { x = 160, y = 120, w = 40, h = 40 },
    hurt_1 = { x = 200, y = 120, w = 40, h = 40 },
    hurt_2 = { x = 0,   y = 160, w = 40, h = 40 },
    hurt_3 = { x = 40,  y = 160, w = 40, h = 40 },
  },
}

function Atlas:load()
  self.image = love.graphics.newImage(self.imagePath)
  self.image:setFilter('nearest', 'nearest')
  local imageWidth, imageHeight = self.image:getDimensions()

  for _, frame in pairs(self.frames) do
    frame.quad = love.graphics.newQuad(
      frame.x, frame.y, frame.w, frame.h, imageWidth, imageHeight
    )
  end

  return self
end

return Atlas