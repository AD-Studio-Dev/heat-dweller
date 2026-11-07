function love.conf(t)
  t.gammacorrect = false
  t.window.title = 'Heat Dweller'
  -- Launch as a BORDERLESS WINDOW, not fullscreen: main.lua sizes it to the
  -- desktop in love.load. Press F or F11 to toggle to a normal window.
  t.window.fullscreen = false
  t.window.display = 1
  t.window.width = 1344   -- windowed size = the internal 16:9 canvas at 1x
  t.window.height = 756
  t.window.minwidth = 672
  t.window.minheight = 378
  t.window.borderless = true
  t.window.resizable = false
  t.window.highdpi = true -- real physical pixels, so Windows never bitmap-stretches the window
  t.window.vsync = true
end