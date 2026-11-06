function love.conf(t)
  t.gammacorrect = false
  t.window.title = 'Heat Dweller'
  -- Launch in desktop fullscreen (borderless, native desktop resolution) so it
  -- adapts to any monitor size / aspect ratio. Press F or F11 to toggle; the
  -- windowed size below is what you get back.
  t.window.fullscreen = true
  t.window.fullscreentype = 'desktop'
  t.window.display = 1
  t.window.width = 1344   -- windowed size = the internal 16:9 canvas at 1x
  t.window.height = 756
  t.window.minwidth = 672
  t.window.minheight = 378
  t.window.borderless = false
  t.window.resizable = true
  t.window.highdpi = false
  t.window.vsync = true
end