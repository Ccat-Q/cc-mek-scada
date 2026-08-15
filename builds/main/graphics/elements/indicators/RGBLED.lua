
local element = require("graphics.element")
return function (args)
element.assert(type(args.label) == "string", "label is a required field")
element.assert(type(args.colors) == "table", "colors is a required field")
args.height = 1
args.width = math.max(args.min_label_width or 0, string.len(args.label)) + 2
local e = element.new(args)
e.value = 1
function e.on_update(new_state)
e.value = new_state
e.w_set_cur(1, 1)
if type(args.colors[new_state]) == "number" then
e.w_blit("\x8c", colors.toBlit(args.colors[new_state]), e.fg_bg.blit_bkg)
end
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
e.on_update(e.value)
if string.len(args.label) > 0 then
e.w_set_cur(3, 1)
e.w_write(args.label)
end
end
local RGBLED, id = e.complete(true)
return RGBLED, id
end
