
local log         = require("scada-common.log")
local util        = require("scada-common.util")
local coordinator = require("coordinator.coordinator")
local ioctl       = require("coordinator.ioctl")
local style       = require("coordinator.ui.style")
local pgi         = require("coordinator.ui.pgi")
local flow_view   = require("coordinator.ui.layout.flow_view")
local panel_view  = require("coordinator.ui.layout.front_panel")
local main_view   = require("coordinator.ui.layout.main_view")
local unit_view   = require("coordinator.ui.layout.unit_view")
local core        = require("graphics.core")
local flasher     = require("graphics.flasher")
local DisplayBox  = require("graphics.elements.DisplayBox")
local log_render = coordinator.log_render
local renderer = {}
local engine = {
config = nil,
color_mode = 1,
monitors = nil,
dmesg_window = nil,
ui_ready = false,
fp_ready = false,
ui = {
front_panel = nil,
main_display = nil,
flow_display = nil,
unit_displays = {}
}
}
local function _init_display(monitor)
monitor.setTextScale(0.5)
monitor.setTextColor(colors.white)
monitor.setBackgroundColor(colors.black)
monitor.clear()
monitor.setCursorPos(1, 1)
for i = 1, #style.theme.colors do
monitor.setPaletteColor(style.theme.colors[i].c, style.theme.colors[i].hex)
end
local c_mode_overrides = style.theme.color_modes[engine.color_mode]
for i = 1, #c_mode_overrides do
monitor.setPaletteColor(c_mode_overrides[i].c, c_mode_overrides[i].hex)
end
end
local function _print_too_small(monitor)
monitor.setCursorPos(1, 1)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.red)
monitor.clear()
monitor.write("monitor too small")
end
function renderer.configure(config)
engine.config = config
engine.color_mode = config.ColorMode
style.set_themes(config.MainTheme, config.FrontPanelTheme, config.ColorMode)
end
function renderer.init_displays(monitors)
engine.monitors = monitors
_init_display(engine.monitors.main)
_init_display(engine.monitors.flow)
for _, monitor in ipairs(engine.monitors.unit_displays) do
_init_display(monitor)
end
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
for i = 1, #style.fp_theme.colors do
term.setPaletteColor(style.fp_theme.colors[i].c, style.fp_theme.colors[i].hex)
end
local c_mode_overrides = style.fp_theme.color_modes[engine.color_mode]
for i = 1, #c_mode_overrides do
term.setPaletteColor(c_mode_overrides[i].c, c_mode_overrides[i].hex)
end
end
function renderer.init_dmesg()
local disp_w, disp_h = engine.monitors.main.getSize()
engine.dmesg_window = window.create(engine.monitors.main, 1, 1, disp_w, disp_h)
log.direct_dmesg(engine.dmesg_window)
end
function renderer.try_start_fp()
local status, msg = true, nil
if not engine.fp_ready then
status, msg = pcall(function ()
engine.ui.front_panel = DisplayBox{window=term.current(),fg_bg=style.fp.root}
panel_view(engine.ui.front_panel, engine.config)
end)
if status then
flasher.run()
engine.fp_ready = true
else
msg = core.extract_assert_msg(msg)
renderer.close_fp()
end
end
return status, msg
end
function renderer.close_fp()
if engine.fp_ready then
if not engine.ui_ready then
flasher.clear()
end
pgi.unlink()
engine.ui.front_panel.hide()
engine.ui.front_panel = nil
engine.fp_ready = false
for i = 1, #style.fp_theme.colors do
local r, g, b = term.nativePaletteColor(style.fp_theme.colors[i].c)
term.setPaletteColor(style.fp_theme.colors[i].c, r, g, b)
end
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
end
end
function renderer.try_start_ui()
local status, msg = true, nil
if not engine.ui_ready then
engine.dmesg_window.setVisible(false)
status, msg = pcall(function ()
if engine.monitors.main ~= nil then
engine.ui.main_display = DisplayBox{window=engine.monitors.main,fg_bg=style.root}
main_view(engine.ui.main_display)
ioctl.fp_monitor_state("main", 3)
util.nop()
end
if engine.monitors.flow ~= nil then
engine.ui.flow_display = DisplayBox{window=engine.monitors.flow,fg_bg=style.root}
flow_view(engine.ui.flow_display)
ioctl.fp_monitor_state("flow", 3)
util.nop()
end
for idx, display in pairs(engine.monitors.unit_displays) do
engine.ui.unit_displays[idx] = DisplayBox{window=display,fg_bg=style.root}
unit_view(engine.ui.unit_displays[idx], idx)
ioctl.fp_monitor_state(idx, 3)
util.nop()
end
end)
if status then
flasher.run()
engine.ui_ready = true
else
msg = core.extract_assert_msg(msg)
renderer.close_ui()
end
end
return status, msg
end
function renderer.close_ui()
if not engine.fp_ready then
flasher.clear()
end
if engine.ui.main_display ~= nil then
engine.ui.main_display.delete()
ioctl.fp_monitor_state("main", 2)
end
if engine.ui.flow_display ~= nil then
engine.ui.flow_display.delete()
ioctl.fp_monitor_state("flow", 2)
end
for idx, display in pairs(engine.ui.unit_displays) do
display.delete()
ioctl.fp_monitor_state(idx, 2)
end
engine.ui_ready = false
engine.ui.main_display = nil
engine.ui.flow_display = nil
engine.ui.unit_displays = {}
for _, monitor in ipairs(engine.monitors.unit_displays) do monitor.clear() end
engine.monitors.flow.clear()
engine.dmesg_window.setVisible(true)
engine.dmesg_window.redraw()
end
function renderer.fp_ready() return engine.fp_ready end
function renderer.ui_ready() return engine.ui_ready end
function renderer.handle_disconnect(iface)
if not engine.monitors then return false end
if engine.monitors.main_iface == iface then
if engine.ui.main_display ~= nil then
engine.ui.main_display.delete()
log_render("closed main view due to monitor disconnect")
end
engine.monitors.main = nil
engine.ui.main_display = nil
elseif engine.monitors.flow_iface == iface then
if engine.ui.flow_display ~= nil then
engine.ui.flow_display.delete()
log_render("closed flow view due to monitor disconnect")
end
engine.monitors.flow = nil
engine.ui.flow_display = nil
else
for idx, u_iface in pairs(engine.monitors.unit_ifaces) do
if u_iface == iface then
if engine.ui.unit_displays[idx] ~= nil then
engine.ui.unit_displays[idx].delete()
log_render("closed unit" .. idx .. "view due to monitor disconnect")
end
engine.monitors.unit_displays[idx] = nil
engine.ui.unit_displays[idx] = nil
break
end
end
end
end
function renderer.handle_reconnect(name)
renderer.handle_resize(name)
end
function renderer.handle_resize(name)
local is_used = false
local is_ok = true
local ui = engine.ui
if not engine.monitors then return false, false end
if engine.monitors.main_iface == name and engine.monitors.main then
local device = engine.monitors.main
_init_display(device)
is_used = true
local disp_w, disp_h = engine.monitors.main.getSize()
local dmsg_w, _ = engine.dmesg_window.getSize()
engine.dmesg_window.reposition(1, 1, math.max(disp_w, dmsg_w), disp_h, engine.monitors.main)
if ui.main_display then
ui.main_display.delete()
ui.main_display = nil
end
ioctl.fp_monitor_state("main", 2)
engine.dmesg_window.setVisible(not engine.ui_ready)
if engine.ui_ready then
local draw_start = util.time_ms()
local ok = pcall(function ()
ui.main_display = DisplayBox{window=device,fg_bg=style.root}
main_view(ui.main_display)
end)
if ok then
ioctl.fp_monitor_state("main", 3)
log_render("main view re-draw completed in " .. (util.time_ms() - draw_start) .. "ms")
else
if ui.main_display then
ui.main_display.delete()
ui.main_display = nil
end
_print_too_small(device)
is_ok = false
end
else engine.dmesg_window.redraw() end
elseif engine.monitors.flow_iface == name and engine.monitors.flow then
local device = engine.monitors.flow
_init_display(device)
is_used = true
if ui.flow_display then
ui.flow_display.delete()
ui.flow_display = nil
end
ioctl.fp_monitor_state("flow", 2)
if engine.ui_ready then
local draw_start = util.time_ms()
local ok = pcall(function ()
ui.flow_display = DisplayBox{window=device,fg_bg=style.root}
flow_view(ui.flow_display)
end)
if ok then
ioctl.fp_monitor_state("flow", 3)
log_render("flow view re-draw completed in " .. (util.time_ms() - draw_start) .. "ms")
else
if ui.flow_display then
ui.flow_display.delete()
ui.flow_display = nil
end
_print_too_small(device)
is_ok = false
end
end
else
for idx, monitor in ipairs(engine.monitors.unit_ifaces) do
local device = engine.monitors.unit_displays[idx]
if monitor == name and device then
_init_display(device)
is_used = true
if ui.unit_displays[idx] then
ui.unit_displays[idx].delete()
ui.unit_displays[idx] = nil
end
ioctl.fp_monitor_state(idx, 2)
if engine.ui_ready then
local draw_start = util.time_ms()
local ok = pcall(function ()
ui.unit_displays[idx] = DisplayBox{window=device,fg_bg=style.root}
unit_view(ui.unit_displays[idx], idx)
end)
if ok then
ioctl.fp_monitor_state(idx, 3)
log_render("unit " .. idx .. " view re-draw completed in " .. (util.time_ms() - draw_start) .. "ms")
else
if ui.unit_displays[idx] then
ui.unit_displays[idx].delete()
ui.unit_displays[idx] = nil
end
_print_too_small(device)
is_ok = false
end
end
break
end
end
end
return is_used, is_ok
end
function renderer.handle_mouse(event)
if event ~= nil then
if engine.fp_ready and event.monitor == "terminal" then
engine.ui.front_panel.handle_mouse(event)
elseif engine.ui_ready then
if event.monitor == engine.monitors.main_iface then
if engine.ui.main_display then engine.ui.main_display.handle_mouse(event) end
elseif event.monitor == engine.monitors.flow_iface then
if engine.ui.flow_display then engine.ui.flow_display.handle_mouse(event) end
else
for id, monitor in ipairs(engine.monitors.unit_ifaces) do
local display = engine.ui.unit_displays[id]
if event.monitor == monitor and display then
if display then display.handle_mouse(event) end
end
end
end
end
end
end
return renderer
