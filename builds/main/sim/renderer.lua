
local panel_view = require("sim.panel.front_panel")
local style = require("sim.panel.style")
local core = require("graphics.core")
local flasher = require("graphics.flasher")
local DisplayBox = require("graphics.elements.DisplayBox")
local renderer = {}
local ui = {
display = nil
}
function renderer.try_start_ui(config, control)
local status, msg = true, nil
if ui.display == nil then
style.set_theme(config.FrontPanelTheme or 1, config.ColorMode or 1)
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
for i = 1, #style.theme.colors do
term.setPaletteColor(style.theme.colors[i].c, style.theme.colors[i].hex)
end
local c_mode_overrides = style.theme.color_modes[config.ColorMode or 1]
for i = 1, #c_mode_overrides do
term.setPaletteColor(c_mode_overrides[i].c, c_mode_overrides[i].hex)
end
status, msg = pcall(function ()
ui.display = DisplayBox{window=term.current(),fg_bg=style.fp.root}
panel_view(ui.display, config, control)
end)
if status then
flasher.run()
else
msg = core.extract_assert_msg(msg)
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
print("SIM UI ERROR: " .. tostring(msg))
print("Check /log.txt for details")
end
end
return status, msg
end
function renderer.close_ui()
if ui.display ~= nil then
flasher.clear()
ui.display.delete()
ui.display = nil
for i = 1, #style.theme.colors do
local r, g, b = term.nativePaletteColor(style.theme.colors[i].c)
term.setPaletteColor(style.theme.colors[i].c, r, g, b)
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
return renderer
