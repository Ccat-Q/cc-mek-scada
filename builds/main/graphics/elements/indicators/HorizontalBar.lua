
local util    = require("scada-common.util")
local element = require("graphics.element")
return function (args)
local e = element.new(args)
e.value = 0.0
local bar_width = util.trinary(args.show_percent, e.frame.w - 5, e.frame.w)
element.assert(bar_width > 0, "too small for bar")
local last_num_bars = -1
local bar_bkg = e.fg_bg.blit_bkg
local bar_fgd = e.fg_bg.blit_fgd
if args.bar_fg_bg ~= nil then
bar_bkg = args.bar_fg_bg.blit_bkg
bar_fgd = args.bar_fg_bg.blit_fgd
end
function e.on_update(fraction)
e.value = fraction
if fraction < 0 then
fraction = 0.0
elseif fraction > 1 then
fraction = 1.0
end
local num_bars = util.round(fraction * (bar_width * 2))
if num_bars ~= last_num_bars then
last_num_bars = num_bars
local fgd = ""
local bkg = ""
local spaces = ""
for _ = 1, num_bars / 2 do
spaces = spaces .. " "
fgd = fgd .. bar_fgd
bkg = bkg .. bar_bkg
end
if num_bars % 2 == 1 then
spaces = spaces .. "\x95"
fgd = fgd .. bar_bkg
bkg = bkg .. bar_fgd
end
for _ = 1, ((bar_width * 2) - num_bars) / 2 do
spaces = spaces .. " "
fgd = fgd .. bar_bkg
bkg = bkg .. bar_bkg
end
for y = 1, e.frame.h do
e.w_set_cur(1, y)
e.w_blit(spaces, bkg, fgd)
end
end
if args.show_percent then
e.w_set_cur(bar_width + 2, math.max(1, math.ceil(e.frame.h / 2)))
e.w_write(util.sprintf("%3.0f%%", fraction * 100))
end
end
function e.recolor(bar_fg_bg)
bar_bkg = bar_fg_bg.blit_bkg
bar_fgd = bar_fg_bg.blit_fgd
e.redraw()
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
last_num_bars = -1
e.on_update(e.value)
end
local HorizontalBar, id = e.complete(true)
return HorizontalBar, id
end
