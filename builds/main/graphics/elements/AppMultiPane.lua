
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
local events  = require("graphics.events")
local MOUSE_CLICK = core.events.MOUSE_CLICK
return function (args)
element.assert(type(args.panes) == "table", "panes is a required field")
local e = element.new(args)
e.value = 1
local nav_x_start = math.floor((e.frame.w / 2) - (#args.panes / 2)) + 1
local nav_x_end   = math.floor((e.frame.w / 2) - (#args.panes / 2)) + #args.panes
function e.redraw()
for i = 1, #args.panes do args.panes[i].hide() end
args.panes[e.value].show()
for i = 1, #args.panes do
e.w_set_cur(nav_x_start + (i - 1), e.frame.h)
e.w_set_fgd(util.trinary(i == e.value, args.nav_colors.color_a, args.nav_colors.color_b))
e.w_write("\x07")
end
end
function e.handle_mouse(event)
local initial = e.value
if e.enabled then
if event.current.y == e.frame.h and event.current.x >= nav_x_start and event.current.x <= nav_x_end then
local id = event.current.x - nav_x_start + 1
if event.type == MOUSE_CLICK.TAP then
e.set_value(id)
elseif event.type == MOUSE_CLICK.UP then
e.set_value(id)
end
end
end
if args.scroll_nav then
if event.type == events.MOUSE_CLICK.SCROLL_DOWN then
e.set_value(e.value + 1)
elseif event.type == events.MOUSE_CLICK.SCROLL_UP then
e.set_value(e.value - 1)
end
end
if args.drag_nav then
local x1, x2 = event.initial.x, event.current.x
if event.type == events.MOUSE_CLICK.UP and e.in_frame_bounds(x1, event.initial.y) and e.in_frame_bounds(x1, event.current.y) then
if x2 > x1 then
e.set_value(e.value - 1)
elseif x2 < x1 then
e.set_value(e.value + 1)
end
end
end
if e.value ~= initial and type(args.callback) == "function" then args.callback(e.value) end
end
function e.set_value(value)
if (e.value ~= value) and (value > 0) and (value <= #args.panes) then
e.value = value
e.redraw()
end
end
local AppMultiPane, id = e.complete(true)
return AppMultiPane, id
end
