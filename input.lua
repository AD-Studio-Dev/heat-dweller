-- Continuous movement input. The game reads this state during update().
---@diagnostic disable: undefined-global
local Input = {}
Input.__index = Input

function Input.new()
  return setmetatable({
    bindings = {
      moveLeft = 'a',
      moveRight = 'd',
      moveUp = 'w',
      moveDown = 's',
      attackLeft = 'left',
      attackRight = 'right',
      attackUp = 'up',
      attackDown = 'down',
      interact = 'e',
    },
    left = false,
    right = false,
    up = false,
    down = false,
    attackDirections = { up = false, down = false, left = false, right = false },
  }, Input)
end

-- Placing a Flame: either Shift key, or the gamepad's right shoulder button. These
-- are kept out of `bindings`; a Shift key the player assigns to another action in
-- the keybind menu stops placing Flames, so one press never does both.
function Input:isFlameKey(key)
  if key ~= 'lshift' and key ~= 'rshift' then
    return false
  end
  for _, bound in pairs(self.bindings) do
    if bound == key then
      return false
    end
  end
  return true
end

function Input:isFlameButton(button)
  return button == 'rightshoulder'
end

function Input:getAttackDirection(key)
  for direction, binding in pairs({
    up = self.bindings.attackUp,
    down = self.bindings.attackDown,
    left = self.bindings.attackLeft,
    right = self.bindings.attackRight,
  }) do
    if key == binding then
      return direction
    end
  end
end

function Input:update()
  self.left = love.keyboard.isDown(self.bindings.moveLeft)
  self.right = love.keyboard.isDown(self.bindings.moveRight)
  self.up = love.keyboard.isDown(self.bindings.moveUp)
  self.down = love.keyboard.isDown(self.bindings.moveDown)
  local attackDirections = {
    up = love.keyboard.isDown(self.bindings.attackUp),
    down = love.keyboard.isDown(self.bindings.attackDown),
    left = love.keyboard.isDown(self.bindings.attackLeft),
    right = love.keyboard.isDown(self.bindings.attackRight),
  }
  for _, joystick in ipairs(love.joystick.getJoysticks()) do
    if joystick:isGamepad() then
      attackDirections.up = attackDirections.up or joystick:isGamepadDown('dpup')
      attackDirections.down = attackDirections.down or joystick:isGamepadDown('dpdown')
      attackDirections.left = attackDirections.left or joystick:isGamepadDown('dpleft')
      attackDirections.right = attackDirections.right or joystick:isGamepadDown('dpright')
    end
  end
  self.attackDirections = {
    up = attackDirections.up,
    down = attackDirections.down,
    left = attackDirections.left,
    right = attackDirections.right,
  }
end

function Input:getHeldAttackDirection()
  for _, direction in ipairs({ 'up', 'down', 'left', 'right' }) do
    if self.attackDirections[direction] then
      return direction
    end
  end
end

return Input