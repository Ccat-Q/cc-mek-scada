
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
element.assert(type(args.tabs) == "table", "tabs is a required field")
element.assert(#args.tabs > 0, "at least one tab is required")
element.assert(type(args.callback) == "function", "callback is a required field")
element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")
args.height = 1
local max_width = 1
for i = 1, #args.tabs do
local opt = args.tabs[i]
if string.len(opt.name) > max_width then
max_width = string.len(opt.name)
end
end
local button_width = math.max(max_width, args.min_width or 0)
local e = element.new(args)
element.assert(e.frame.w >= (button_width * #args.tabs), "width insufficent to display all tabs")
e.value = 1
local next_x = 1
for i = 1, #args.tabs do
local tab = args.tabs[i]
tab._start_x = next_x
tab._end_x = next_x + button_width - 1
next_x = next_x + button_width
end
function e.redraw()
for i = 1, #args.tabs do
local tab = args.tabs[i]
e.w_set_cur(tab._start_x, 1)
if e.value == i then
e.w_set_fgd(tab.color.fgd)
e.w_set_bkg(tab.color.bkg)
else
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
end
e.w_write(util.pad(tab.name, button_width))
end
end
local function which_tab(x)
for i = 1, #args.tabs do
local tab = args.tabs[i]
if x >= tab._start_x and x <= tab._end_x then return i end
end
return nil
end
function e.handle_mouse(event)
if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) then
local tab_ini = which_tab(event.initial.x)
local tab_cur = which_tab(event.current.x)
if tab_ini == tab_cur and tab_cur ~= nil then
e.value = tab_cur
e.redraw()
args.callback(e.value)
end
end
end
function e.set_value(val)
e.value = val
e.redraw()
end
local TabBar, id = e.complete(true)
return TabBar, id
end
