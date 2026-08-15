
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
element.assert(util.is_int(args.reactor_l), "reactor_l is a required field")
element.assert(util.is_int(args.reactor_w), "reactor_w is a required field")
args.width = 18
args.height = 18
args.fg_bg = core.cpair(args.parent.get_fg_bg().fgd, colors.gray)
local e = element.new(args)
e.value = 0
local alternator = true
local core_l = args.reactor_l - 2
local core_w = args.reactor_w - 2
local shift_x = 8 - math.floor(core_l / 2)
local shift_y = 8 - math.floor(core_w / 2)
local start_x = 2 + shift_x
local start_y = 2 + shift_y
local inner_width = core_l
local inner_height = core_w
local function draw_frame()
e.w_set_fgd(colors.white)
for x = 0, (inner_width - 1) do
e.w_set_cur(x + start_x, 1)
e.w_write(util.sprintf("%X", x))
end
for y = 0, (inner_height - 1) do
e.w_set_cur(1, y + start_y)
e.w_write(util.sprintf("%X", y))
end
e.w_set_fgd(e.fg_bg.bkg)
e.w_set_bkg(args.parent.get_fg_bg().bkg)
e.w_set_cur(1, e.frame.h)
e.w_write(string.rep("\x8f", e.frame.w))
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
end
local function draw_core(t)
local i = 1
local back_c = "F"
local text_c
if t <= 300 then
text_c = "8"
elseif t <= 350 then
text_c = "3"
elseif t < 600 then
text_c = "D"
elseif t < 1000 then
text_c = "4"
elseif t < 1200 then
text_c = "1"
elseif t < 1300 then
text_c = "E"
else
text_c = "2"
end
for y = start_y, inner_height + (start_y - 1) do
e.w_set_cur(start_x, y)
for _ = 1, inner_width do
if alternator then
i = i + 1
e.w_blit("\x07", text_c, back_c)
else
e.w_blit("\x07", "7", "8")
end
alternator = not alternator
end
if inner_width % 2 == 0 then alternator = not alternator end
end
alternator = true
end
function e.on_update(temperature)
e.value = temperature
draw_core(e.value)
end
function e.set_value(val) e.on_update(val) end
function e.resize(reactor_l, reactor_w)
if reactor_l > 18 then reactor_l = 18 elseif reactor_l < 3 then reactor_l = 3 end
if reactor_w > 18 then reactor_w = 18 elseif reactor_w < 3 then reactor_w = 3 end
core_l = reactor_l - 2
core_w = reactor_w - 2
shift_x = 8 - math.floor(core_l / 2)
shift_y = 8 - math.floor(core_w / 2)
start_x = 2 + shift_x
start_y = 2 + shift_y
inner_width = core_l
inner_height = core_w
e.window.clear()
draw_frame()
e.on_update(e.value)
end
function e.redraw()
draw_frame()
draw_core(e.value)
end
local CoreMap, id = e.complete(true)
return CoreMap, id
end
