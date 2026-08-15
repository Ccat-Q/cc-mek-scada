
local tcd     = require("scada-common.tcd")
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
local MOUSE_CLICK = core.events.MOUSE_CLICK
return function (args)
args.width = 3
local e = element.new(args)
e.value = 1
local was_pressed = false
local tabs = {}
local function draw(pressed, pressed_idx)
pressed = util.trinary(pressed == nil, was_pressed, pressed)
was_pressed = pressed
pressed_idx = pressed_idx or e.value
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
for y = 1, e.frame.h do
e.w_set_cur(1, y)
e.w_write("   ")
end
for i = 1, #tabs do
local tab = tabs[i]
local y = tab.y_start
e.w_set_cur(1, y)
if pressed and i == pressed_idx then
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
else
e.w_set_fgd(tab.color.fgd)
e.w_set_bkg(tab.color.bkg)
end
if tab.tall then
e.w_write("   ")
e.w_set_cur(1, y + 1)
end
e.w_write(tab.label)
if tab.tall then
e.w_set_cur(1, y + 2)
e.w_write("   ")
end
end
end
local function find_tab(y)
for i = 1, #tabs do
local tab = tabs[i]
if y >= tab.y_start and y <= tab.y_end then
return i
end
end
end
function e.handle_mouse(event)
if e.enabled then
local cur_idx = find_tab(event.current.y)
local ini_idx = find_tab(event.initial.y)
local tab = tabs[cur_idx]
if tab ~= nil and type(tab.callback) == "function" then
if event.type == MOUSE_CLICK.TAP then
e.value = cur_idx
draw(true)
tcd.dispatch(0.25, function () draw(false) end)
tab.callback()
elseif event.type == MOUSE_CLICK.DOWN then
draw(true, cur_idx)
elseif event.type == MOUSE_CLICK.UP then
if cur_idx == ini_idx and e.in_frame_bounds(event.current.x, event.current.y) then
e.value = cur_idx
draw(false)
tab.callback()
else draw(false) end
end
elseif event.type == MOUSE_CLICK.UP then
draw(false)
end
end
end
function e.set_value(val)
e.value = val
draw(false)
end
function e.on_update(items)
local next_y = 1
tabs = {}
for i = 1, #items do
local item = items[i]
local height = util.trinary(item.tall, 3, 1)
local entry = {
y_start = next_y,
y_end = next_y + height - 1,
tall = item.tall,
label = item.label,
color = item.color,
callback = item.callback
}
next_y = next_y + height
tabs[i] = entry
end
draw()
end
e.redraw = draw
local Sidebar, id = e.complete(true)
return Sidebar, id
end
