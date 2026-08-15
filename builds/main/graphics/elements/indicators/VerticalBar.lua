
local util    = require("scada-common.util")
local element = require("graphics.element")
return function (args)
local e = element.new(args)
e.value = 0.0
local last_num_bars = -1
local fgd = string.rep(e.fg_bg.blit_fgd, e.frame.w)
local bkg = string.rep(e.fg_bg.blit_bkg, e.frame.w)
local spaces = util.spaces(e.frame.w)
local one_third = string.rep("\x8f", e.frame.w)
local two_thirds = string.rep("\x83", e.frame.w)
function e.on_update(fraction)
e.value = fraction
if fraction < 0 then
fraction = 0.0
elseif fraction > 1 then
fraction = 1.0
end
local num_bars = util.round(fraction * (e.frame.h * 3))
if num_bars ~= last_num_bars then
last_num_bars = num_bars
local y = e.frame.h
e.w_set_cur(1, y)
for _ = 1, num_bars / 3 do
e.w_blit(spaces, bkg, fgd)
y = y - 1
e.w_set_cur(1, y)
end
if num_bars % 3 == 1 then
e.w_blit(one_third, bkg, fgd)
y = y - 1
elseif num_bars % 3 == 2 then
e.w_blit(two_thirds, bkg, fgd)
y = y - 1
end
while y > 0 do
e.w_set_cur(1, y)
e.w_blit(spaces, fgd, bkg)
y = y - 1
end
end
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
last_num_bars = -1
e.on_update(e.value)
end
function e.recolor(fg_bg)
fgd = string.rep(fg_bg.blit_fgd, e.frame.w)
bkg = string.rep(fg_bg.blit_bkg, e.frame.w)
e.redraw()
end
local VerticalBar, id = e.complete(true)
return VerticalBar, id
end
