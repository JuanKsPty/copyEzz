-- copyEzz: el botón lateral del mouse (o ⌃⌥⌘A) captura la pantalla donde está el mouse y la envía al server local.
-- Cargar desde ~/.hammerspoon/init.lua con: dofile(os.getenv("HOME") .. "/dev/copyEzz/legacy/hammerspoon/copyezz.lua")

local URL = "http://127.0.0.1:8765/solve"
local SHOT = (os.getenv("TMPDIR") or "/tmp/") .. "copyezz-shot.png"
-- Botones laterales del Keychron M3 mini: 3 = atrás, 4 = adelante.
local MOUSE_BUTTON = 4

local function capture()
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local image = screen:snapshot()
  if not image or not image:saveToFile(SHOT) then
    hs.alert.show("copyEzz: no se pudo capturar (¿permiso de Grabación de pantalla?)")
    return
  end

  local file = io.open(SHOT, "rb")
  local png = file:read("a")
  file:close()

  hs.http.asyncPost(URL, png, { ["Content-Type"] = "image/png" }, function(status)
    if status ~= 202 then
      hs.alert.show("copyEzz: el server no responde (uv run copyezz.py)")
    end
  end)
end

copyezzHotkey = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "A", capture)

local types = hs.eventtap.event.types
copyezzMouse = hs.eventtap.new({ types.otherMouseDown, types.otherMouseUp }, function(event)
  if event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) ~= MOUSE_BUTTON then
    return false
  end
  if event:getType() == types.otherMouseDown then
    hs.timer.doAfter(0, capture) -- fuera del callback: macOS desactiva los eventtaps lentos
  end
  return true -- se consume el clic para que el navegador no haga "adelante"
end)
copyezzMouse:start()
