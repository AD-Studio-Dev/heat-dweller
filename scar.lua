local Enemy = require('enemy')

local Scar = {}
Scar.__index = Scar

function Scar.new(config)
  config = config or {}
  config.kind = config.kind or 'scar'
  return setmetatable(Enemy.new(config), Scar)
end

function Scar:update(dt, player)
  return Enemy.update(self, dt, player)
end

return Scar
