
local util    = require("scada-common.util")
local element = require("graphics.element")
return function (args)
element.assert(args.border ~= nil or args.thin ~= true, "thin requires border to be provided")
if args.thin == true then
args.border.width = 1
args.border.even = true
end
local offset_x = 0
local offset_y = 0
if args.border ~= nil then
offset_x = args.border.width
offset_y = args.border.width
if args.border.even then
local width_x2 = (2 * args.border.width)
offset_y = math.floor(width_x2 / 3) + util.trinary(width_x2 % 3 > 0, 1, 0)
end
end
local e = element.new(args, nil, offset_x, offset_y)
e.content_window = window.create(e.window, 1 + offset_x, 1 + offset_y, e.frame.w - (2 * offset_x), e.frame.h - (2 * offset_y))
e.content_window.setBackgroundColor(e.fg_bg.bkg)
e.content_window.setTextColor(e.fg_bg.fgd)
e.content_window.clear()
if args.border ~= nil then
e.w_set_cur(1, 1)
local border_width = offset_x
local border_height = offset_y
local border_blit = colors.toBlit(args.border.color)
local width_x2 = border_width * 2
local inner_width = e.frame.w - width_x2
element.assert(width_x2 <= e.frame.w, "border too thick for width")
element.assert(width_x2 <= e.frame.h, "border too thick for height")
local spaces = util.spaces(e.frame.w)
local blit_fg = string.rep(e.fg_bg.blit_fgd, e.frame.w)
local blit_fg_sides = blit_fg
local blit_bg_sides = ""
local blit_bg_top_bot = string.rep(border_blit, e.frame.w)
local p_a, p_b, p_s
if args.thin == true then
if args.even_inner == true then
p_a = "\x9c" .. string.rep("\x8c", inner_width) .. "\x93"
p_b = "\x8d" .. string.rep("\x8c", inner_width) .. "\x8e"
else
p_a = "\x97" .. string.rep("\x83", inner_width) .. "\x94"
p_b = "\x8a" .. string.rep("\x8f", inner_width) .. "\x85"
end
p_s = "\x95" .. util.spaces(inner_width) .. "\x95"
else
if args.even_inner == true then
p_a = string.rep("\x83", inner_width + width_x2)
p_b = string.rep("\x8f", inner_width + width_x2)
else
p_a = util.spaces(border_width) .. string.rep("\x8f", inner_width) .. util.spaces(border_width)
p_b = util.spaces(border_width) .. string.rep("\x83", inner_width) .. util.spaces(border_width)
end
p_s = spaces
end
local p_inv_fg = string.rep(border_blit, border_width) .. string.rep(e.fg_bg.blit_bkg, inner_width) ..
string.rep(border_blit, border_width)
local p_inv_bg = string.rep(e.fg_bg.blit_bkg, border_width) .. string.rep(border_blit, inner_width) ..
string.rep(e.fg_bg.blit_bkg, border_width)
if args.thin == true then
p_inv_fg = e.fg_bg.blit_bkg .. string.rep(e.fg_bg.blit_bkg, inner_width) .. string.rep(border_blit, border_width)
p_inv_bg = border_blit .. string.rep(border_blit, inner_width) .. string.rep(e.fg_bg.blit_bkg, border_width)
blit_fg_sides = border_blit .. string.rep(e.fg_bg.blit_bkg, inner_width) .. e.fg_bg.blit_bkg
end
for x = 1, e.frame.w do
if x <= border_width or x > (e.frame.w - border_width) then
if args.thin and x == 1 then
blit_bg_sides = blit_bg_sides .. e.fg_bg.blit_bkg
else
blit_bg_sides = blit_bg_sides .. border_blit
end
else
blit_bg_sides = blit_bg_sides .. e.fg_bg.blit_bkg
end
end
function e.redraw()
for y = 1, e.frame.h do
e.w_set_cur(1, y)
if y <= border_height then
if args.border.even and y == border_height then
if args.thin == true then
e.w_blit(p_a, p_inv_bg, p_inv_fg)
else
local _fg = util.trinary(args.even_inner == true, string.rep(e.fg_bg.blit_bkg, e.frame.w), p_inv_bg)
local _bg = util.trinary(args.even_inner == true, blit_bg_top_bot, p_inv_fg)
if width_x2 % 3 == 1 then
e.w_blit(p_b, _fg, _bg)
elseif width_x2 % 3 == 2 then
e.w_blit(p_a, _fg, _bg)
else
e.w_blit(spaces, blit_fg, blit_bg_sides)
end
end
else
e.w_blit(spaces, blit_fg, blit_bg_top_bot)
end
elseif y > (e.frame.h - border_width) then
if args.border.even and y == ((e.frame.h - border_width) + 1) then
if args.thin == true then
if args.even_inner == true then
e.w_blit(p_b, blit_bg_top_bot, string.rep(e.fg_bg.blit_bkg, e.frame.w))
else
e.w_blit(p_b, string.rep(e.fg_bg.blit_bkg, e.frame.w), blit_bg_top_bot)
end
else
local _fg = util.trinary(args.even_inner == true, blit_bg_top_bot, p_inv_fg)
local _bg = util.trinary(args.even_inner == true, string.rep(e.fg_bg.blit_bkg, e.frame.w), blit_bg_top_bot)
if width_x2 % 3 == 1 then
e.w_blit(p_a, _fg, _bg)
elseif width_x2 % 3 == 2 then
e.w_blit(p_b, _fg, _bg)
else
e.w_blit(spaces, blit_fg, blit_bg_sides)
end
end
else
e.w_blit(spaces, blit_fg, blit_bg_top_bot)
end
else
if args.thin == true then
e.w_blit(p_s, blit_fg_sides, blit_bg_sides)
else
e.w_blit(p_s, blit_fg, blit_bg_sides)
end
end
end
end
e.redraw()
end
local Rectangle, id = e.complete()
return Rectangle, id
end
