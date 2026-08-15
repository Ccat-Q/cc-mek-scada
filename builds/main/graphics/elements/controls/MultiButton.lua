
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
element.assert(type(args.options) == "table", "options is a required field")
element.assert(#args.options > 0, "at least one option is required")
element.assert(type(args.callback) == "function", "callback is a required field")
element.assert(type(args.default) == "nil" or (type(args.default) == "number" and args.default > 0), "default must be nil or a number > 0")
element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")
args.height = 1
local max_width = 1
for i = 1, #args.options do
local opt = args.options[i]
if string.len(opt.text) > max_width then
max_width = string.len(opt.text)
end
end
local button_width = math.max(max_width, args.min_width or 0)
args.width = (button_width * #args.options) + #args.options + 1
local e = element.new(args)
e.value = args.default or 1
local next_x = 2
for i = 1, #args.options do
local opt = args.options[i]
opt._start_x = next_x
opt._end_x = next_x + button_width - 1
next_x = next_x + (button_width + 1)
end
function e.redraw()
for i = 1, #args.options do
local opt = args.options[i]
e.w_set_cur(opt._start_x, 1)
if e.value == i then
e.w_set_fgd(opt.active_fg_bg.fgd)
e.w_set_bkg(opt.active_fg_bg.bkg)
else
e.w_set_fgd(opt.fg_bg.fgd)
e.w_set_bkg(opt.fg_bg.bkg)
end
e.w_write(util.pad(opt.text, button_width))
end
end
local function which_button(x)
for i = 1, #args.options do
local opt = args.options[i]
if x >= opt._start_x and x <= opt._end_x then return i end
end
return nil
end
function e.handle_mouse(event)
if e.enabled and core.events.was_clicked(event.type) then
local button_ini = which_button(event.initial.x)
local button_cur = which_button(event.current.x)
if button_ini == button_cur and button_cur ~= nil then
e.value = button_cur
e.redraw()
args.callback(e.value)
end
end
end
function e.set_value(val)
e.value = val
e.redraw()
end
local MultiButton, id = e.complete(true)
return MultiButton, id
end
