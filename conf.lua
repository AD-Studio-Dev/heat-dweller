function love.conf(t)
  t.gammacorrect = false
  t.window.title = 'Heat Dweller'
  -- Launch as a standard BORDERED window, maximized: it fills the screen but keeps
  -- the OS frame, title bar and minimize / maximize / close buttons. Not fullscreen.
  -- main.lua re-applies these flags in love.load (View.setNormalWindow) and calls
  -- love.window.maximize(), which works on every LÖVE 11.x build. Press F or F11 to
  -- toggle between this window and a borderless desktop window.
  t.window.fullscreen = false
  t.window.display = 1
  t.window.width = 1344   -- restored (un-maximized) size = the internal 16:9 canvas at 1x
  t.window.height = 756
  t.window.minwidth = 672
  t.window.minheight = 378
  t.window.borderless = false
  t.window.resizable = true
  t.window.maximized = true -- honoured by builds that support it; ignored by older ones
  t.window.highdpi = true -- real physical pixels, so Windows never bitmap-stretches the window
  t.window.vsync = true
end