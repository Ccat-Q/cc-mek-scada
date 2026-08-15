
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
local digits = {}
local wn_prec = args.whole_num_precision
local fr_prec = args.fractional_precision
element.assert(util.is_int(wn_prec), "whole number precision must be an integer")
element.assert(util.is_int(fr_prec), "fractional precision must be an integer")
local fmt, fmt_init
if fr_prec > 0 then
fmt = "%" .. (wn_prec + fr_prec + 1) .. "." .. fr_prec .. "f"
fmt_init = "%0" .. (wn_prec + fr_prec + 1) .. "." .. fr_prec .. "f"
else
fmt = "%" .. wn_prec .. "d"
fmt_init = "%0" .. wn_prec .. "d"
end
local dec_point_x = args.whole_num_precision + 1
element.assert(type(args.arrow_fg_bg) == "table", "arrow_fg_bg is a required field")
args.width = wn_prec + fr_prec + util.trinary(fr_prec > 0, 1, 0)
args.height = 3
local e = element.new(args)
e.value = args.default or 0
local function draw_arrows(color)
e.w_set_bkg(args.arrow_fg_bg.bkg)
e.w_set_fgd(color)
e.w_set_cur(1, 1)
e.w_write(string.rep("\x1e", wn_prec))
e.w_set_cur(1, 3)
e.w_write(string.rep("\x1f", wn_prec))
if fr_prec > 0 then
e.w_set_cur(1 + wn_prec, 1)
e.w_write(" " .. string.rep("\x1e", fr_prec))
e.w_set_cur(1 + wn_prec, 3)
e.w_write(" " .. string.rep("\x1f", fr_prec))
end
end
local function set_digits()
local initial_str = util.sprintf(fmt_init, e.value)
digits = {}
initial_str:gsub("%d", function (char) table.insert(digits, char) end)
end
local function update_value()
e.value = 0
for i = 1, #digits do
local pow = math.abs(wn_prec - i)
if i <= wn_prec then
e.value = e.value + (digits[i] * (10 ^ pow))
else
e.value = e.value + (digits[i] * (10 ^ -pow))
end
end
end
local function show_num()
if (type(args.min) == "number") and (e.value < args.min) then
e.value = args.min
set_digits()
elseif e.value < 0 then
e.value = 0
set_digits()
else
if string.len(util.sprintf(fmt, e.value)) > args.width then
for i = 1, #digits do digits[i] = 9 end
update_value()
elseif (type(args.max) == "number") and (e.value > args.max) then
e.value = args.max
set_digits()
else
set_digits()
end
end
e.w_set_bkg(e.fg_bg.bkg)
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_cur(1, 2)
e.w_write(util.sprintf(fmt, e.value))
end
function e.handle_mouse(event)
if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) and
(event.current.x ~= dec_point_x) and (event.current.y ~= 2) and
(event.current.x == event.initial.x) and (event.current.y == event.initial.y) then
local idx = util.trinary(event.current.x > dec_point_x, event.current.x - 1, event.current.x)
if digits[idx] ~= nil then
if event.current.y == 1 then
digits[idx] = digits[idx] + 1
elseif event.current.y == 3 then
digits[idx] = digits[idx] - 1
end
update_value()
show_num()
if type(args.callback) == "function" then args.callback(e.value) end
end
end
end
function e.set_value(val)
e.value = val
show_num()
end
function e.set_min(min)
if min >= 0 then
args.min = min
show_num()
end
end
function e.set_max(max)
args.max = max
show_num()
end
function e.on_enabled() draw_arrows(args.arrow_fg_bg.fgd) end
function e.on_disabled() draw_arrows(args.arrow_disable or colors.lightGray) end
function e.redraw()
show_num()
draw_arrows(util.trinary(e.enabled, args.arrow_fg_bg.fgd, args.arrow_disable or colors.lightGray))
end
local NumericSpinbox, id = e.complete(true)
return NumericSpinbox, id
end
