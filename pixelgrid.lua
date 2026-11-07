-- Strict pixel-grid enforcement for LÖVE.
--
-- Every sprite, icon, text and UI rectangle is drawn on a whole-pixel position
-- with a whole-number scale, so every texel stays the same size on screen.
--
--   PixelGrid.install()      wraps love.graphics.draw / print / printf /
--                            rectangle / translate / scale. Call it once, in
--                            love.load, after the default filter is set.
--   PixelGrid.raw            the original, unwrapped functions. Use raw.draw for
--                            the one place that SHOULD scale by a fractional
--                            amount: presenting the finished canvas to the window.
--   PixelGrid.snap(v)        v rounded to the nearest whole pixel.
--   PixelGrid.snapScale(s)   s as a pixel-safe scale (see below).
--
-- Scale rule:
--   s >= 1  -> nearest whole number (1.25 -> 1, 1.5 -> 2, 3.3 -> 3).
--   s <  1  -> 1/n with n = ceil(1/s). A whole-number scale below 1 would be 0
--              (invisible) or 1 (art LARGER than the slot it was fitted to), so
--              the art shrinks by an exact whole-number divisor instead, which
--              keeps every texel uniform and never overflows.
--   s == 0 stays 0; the sign (mirroring) is always preserved.

local PixelGrid = {}

local floor, ceil, abs = math.floor, math.ceil, math.abs

local function snap(value)
  if type(value) ~= 'number' then
    return value
  end
  return floor(value + 0.5)
end

local function snapScale(scale)
  if type(scale) ~= 'number' or scale == 0 then
    return scale
  end
  local magnitude = abs(scale)
  local snapped
  if magnitude >= 1 then
    snapped = floor(magnitude + 0.5)
  else
    snapped = 1 / ceil(1 / magnitude)
  end
  return scale < 0 and -snapped or snapped
end

PixelGrid.snap = snap
PixelGrid.snapScale = snapScale

-- Snaps both edges of a rectangle (not just x and width) so neighbouring
-- rectangles never gain or lose a pixel to rounding.
function PixelGrid.snapRect(x, y, width, height)
  local left, top = snap(x), snap(y)
  return left, top, snap(x + width) - left, snap(y + height) - top
end

local installed = false
PixelGrid.raw = {}

function PixelGrid.install()
  if installed then
    return
  end
  installed = true

  local graphics = love.graphics
  local raw = PixelGrid.raw
  raw.draw, raw.print, raw.printf = graphics.draw, graphics.print, graphics.printf
  raw.rectangle, raw.translate, raw.scale = graphics.rectangle, graphics.translate, graphics.scale

  -- Video is not pixel art: it keeps its fitted scale (position is still snapped).
  local function drawSnapped(drawable, quad, x, y, r, sx, sy, ox, oy, kx, ky)
    local snappedX = sx ~= nil and snapScale(sx) or nil
    local snappedY = sy ~= nil and snapScale(sy) or snappedX
    if (snappedX ~= sx or snappedY ~= sy) and drawable.typeOf and drawable:typeOf('Video') then
      snappedX, snappedY = sx, sy
    end
    x, y = snap(x), snap(y)
    if ox ~= nil then ox = floor(ox) end
    if oy ~= nil then oy = floor(oy) end
    if quad then
      return raw.draw(drawable, quad, x, y, r, snappedX, snappedY, ox, oy, kx, ky)
    end
    return raw.draw(drawable, x, y, r, snappedX, snappedY, ox, oy, kx, ky)
  end

  -- draw(drawable, x, y, ...) or draw(drawable, quad, x, y, ...)
  graphics.draw = function(drawable, a, b, c, d, e, f, g, h, i, j)
    if type(a) == 'number' then
      return drawSnapped(drawable, nil, a, b, c, d, e, f, g, h, i)
    end
    return drawSnapped(drawable, a, b, c, d, e, f, g, h, i, j)
  end

  -- print(text, x, y, r, sx, sy, ox, oy, kx, ky)
  graphics.print = function(text, x, y, r, sx, sy, ox, oy, kx, ky)
    local snappedX = sx ~= nil and snapScale(sx) or nil
    local snappedY = sy ~= nil and snapScale(sy) or snappedX
    if ox ~= nil then ox = floor(ox) end
    if oy ~= nil then oy = floor(oy) end
    return raw.print(text, snap(x), snap(y), r, snappedX, snappedY, ox, oy, kx, ky)
  end

  -- printf(text, x, y, limit, align, r, sx, sy, ox, oy, kx, ky)
  graphics.printf = function(text, x, y, limit, align, r, sx, sy, ox, oy, kx, ky)
    local snappedX = sx ~= nil and snapScale(sx) or nil
    local snappedY = sy ~= nil and snapScale(sy) or snappedX
    if ox ~= nil then ox = floor(ox) end
    if oy ~= nil then oy = floor(oy) end
    return raw.printf(text, snap(x), snap(y), snap(limit), align, r, snappedX, snappedY, ox, oy, kx, ky)
  end

  -- rectangle(mode, x, y, width, height, rx, ry, segments)
  graphics.rectangle = function(mode, x, y, width, height, rx, ry, segments)
    x, y, width, height = PixelGrid.snapRect(x, y, width, height)
    return raw.rectangle(mode, x, y, width, height, rx, ry, segments)
  end

  -- Camera follow and screen shake translate by fractional amounts.
  graphics.translate = function(dx, dy)
    return raw.translate(snap(dx), snap(dy))
  end

  graphics.scale = function(sx, sy)
    local snappedX = snapScale(sx)
    return raw.scale(snappedX, sy ~= nil and snapScale(sy) or snappedX)
  end
end

return PixelGrid