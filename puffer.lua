-- Puffer: Breathless variant with its own sprite sheet (same behavior for now).
local Breathless = require('breathless')

local Puffer = {}

function Puffer.new(config)
  config = config or {}
  config.kind = 'puffer'
  return Breathless.new(config)
end

return Puffer