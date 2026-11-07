-- Panicker: Breathless variant with its own sprite sheet (same behavior for now).
local Breathless = require('breathless')

local Panicker = {}

function Panicker.new(config)
  config = config or {}
  config.kind = 'panicker'
  return Breathless.new(config)
end

return Panicker