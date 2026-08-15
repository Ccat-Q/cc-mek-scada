
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
local ALIGN = core.ALIGN
return function (args)
element.assert(type(args.text) == "string", "text is a required field")
if args.anchor == true then args.can_focus = true end
local function constrain(frame)
local new_height = math.max(1, #util.strwrap(args.text, frame.w))
if args.height then
new_height = math.max(frame.h, new_height)
end
return frame.w, new_height
end
local e = element.new(args, constrain)
e.value = args.text
local alignment = args.alignment or ALIGN.LEFT
function e.redraw()
e.window.clear()
local lines = util.strwrap(e.value, e.frame.w)
for i = 1, #lines do
if i > e.frame.h then break end
if args.trim_whitespace == true then
lines[i] = util.trim(lines[i])
end
local len = string.len(lines[i])
if alignment == ALIGN.CENTER then
e.w_set_cur(math.floor((e.frame.w - len) / 2) + 1, i)
elseif alignment == ALIGN.RIGHT then
e.w_set_cur((e.frame.w - len) + 1, i)
else
e.w_set_cur(1, i)
end
e.w_write(lines[i])
end
end
function e.set_value(val)
e.value = val
e.redraw()
end
function e.recolor(c)
e.w_set_fgd(c)
e.redraw()
end
local TextBox, id = e.complete(true)
return TextBox, id
end
