
local util    = require("scada-common.util")
local element = require("graphics.element")
return function (args)
element.assert(type(args.fill_c) == "table", "fill_c is a required field")
local e = element.new(args)
local fill_a = args.fill_c.blit_a
local fill_b = args.fill_c.blit_b
local even = args.even == true
local start_x = 1
local start_y = 1
local inner_width = math.floor(e.frame.w / util.trinary(even, 2, 1))
local inner_height = e.frame.h
if args.border_c ~= nil then
start_x = 1 + util.trinary(even, 2, 1)
start_y = 2
inner_width = math.floor((e.frame.w - 2 * util.trinary(even, 2, 1)) / util.trinary(even, 2, 1))
inner_height = e.frame.h - 2
end
element.assert(inner_width > 0, "inner_width <= 0")
element.assert(inner_height > 0, "inner_height <= 0")
element.assert(start_x <= inner_width, "start_x > inner_width")
element.assert(start_y <= inner_height, "start_y > inner_height")
function e.redraw()
local alternator = true
if args.border_c ~= nil then
e.w_set_bkg(args.border_c)
e.window.clear()
end
for y = start_y, inner_height + (start_y - 1) do
e.w_set_cur(start_x, y)
for _ = 1, inner_width do
if alternator then
if even then
e.w_blit("  ", "00", fill_a .. fill_a)
else
e.w_blit(" ", "0", fill_a)
end
else
if even then
e.w_blit("  ", "00", fill_b .. fill_b)
else
e.w_blit(" ", "0", fill_b)
end
end
alternator = not alternator
end
if inner_width % 2 == 0 then alternator = not alternator end
end
end
local Tiling, id = e.complete(true)
return Tiling, id
end
