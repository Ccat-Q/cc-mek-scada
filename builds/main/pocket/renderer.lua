
local main_view  = require("pocket.ui.main")
local style      = require("pocket.ui.style")
local core       = require("graphics.core")
local flasher    = require("graphics.flasher")
local DisplayBox = require("graphics.elements.DisplayBox")
local renderer = {}
local ui = {
display = nil
}
function renderer.try_start_ui()
local status, msg = true, nil
if ui.display == nil then
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
for i = 1, #style.colors do
term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
end
status, msg = pcall(function ()
ui.display = DisplayBox{window=term.current(),fg_bg=style.root}
main_view(ui.display)
end)
if status then
flasher.run()
else
msg = core.extract_assert_msg(msg)
renderer.close_ui()
end
end
return status, msg
end
function renderer.close_ui()
if ui.display ~= nil then
flasher.clear()
ui.display.hide()
ui.display = nil
for i = 1, #style.colors do
local r, g, b = term.nativePaletteColor(style.colors[i].c)
term.setPaletteColor(style.colors[i].c, r, g, b)
end
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
end
end
function renderer.ui_ready() return ui.display ~= nil end
function renderer.handle_mouse(event)
if ui.display ~= nil and event ~= nil then
ui.display.handle_mouse(event)
end
end
function renderer.handle_key(event)
if ui.display ~= nil and event ~= nil then
ui.display.handle_key(event)
end
end
function renderer.handle_paste(text)
if ui.display ~= nil then
ui.display.handle_paste(text)
end
end
return renderer
