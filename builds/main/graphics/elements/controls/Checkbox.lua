
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
element.assert(type(args.label) == "string", "label is a required field")
element.assert(type(args.box_fg_bg) == "table", "box_fg_bg is a required field")
args.can_focus = true
args.height = 1
args.width = 2 + string.len(args.label)
local e = element.new(args)
e.value = args.default == true
local function draw()
e.w_set_cur(1, 1)
local fgd, bkg = args.box_fg_bg.fgd, args.box_fg_bg.bkg
if (not e.enabled) and type(args.disable_fg_bg) == "table" then
fgd = args.disable_fg_bg.bkg
bkg = args.disable_fg_bg.fgd
end
if e.value then
e.w_set_fgd(bkg)
e.w_set_bkg(fgd)
e.w_write("\x88")
e.w_set_fgd(fgd)
e.w_set_bkg(e.fg_bg.bkg)
e.w_write("\x95")
else
e.w_set_fgd(e.fg_bg.bkg)
e.w_set_bkg(bkg)
e.w_write("\x88")
e.w_set_fgd(bkg)
e.w_set_bkg(e.fg_bg.bkg)
e.w_write("\x95")
end
end
local function draw_label()
if e.enabled and e.is_focused() then
e.w_set_fgd(e.fg_bg.bkg)
e.w_set_bkg(e.fg_bg.fgd)
elseif (not e.enabled) and type(args.disable_fg_bg) == "table" then
e.w_set_fgd(args.disable_fg_bg.fgd)
e.w_set_bkg(args.disable_fg_bg.bkg)
else
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
end
e.w_set_cur(3, 1)
e.w_write(args.label)
end
function e.handle_mouse(event)
if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) then
e.value = not e.value
draw()
if type(args.callback) == "function" then args.callback(e.value) end
end
end
function e.handle_key(event)
if event.type == core.events.KEY_CLICK.DOWN then
if event.key == keys.space or event.key == keys.enter or event.key == keys.numPadEnter then
e.value = not e.value
draw()
if type(args.callback) == "function" then args.callback(e.value) end
end
end
end
function e.set_value(val)
e.value = val
draw()
end
function e.redraw()
draw()
draw_label()
end
e.on_focused = draw_label
e.on_unfocused = draw_label
e.on_enabled = e.redraw
e.on_disabled = e.redraw
local Checkbox, id = e.complete(true)
return Checkbox, id
end
