
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
element.assert(type(args.pipes) == "table", "pipes is a required field")
args.width = 0
args.height = 0
for i = 1, #args.pipes do
local pipe = args.pipes[i]
local true_w = pipe.w + math.min(pipe.x1, pipe.x2)
local true_h = pipe.h + math.min(pipe.y1, pipe.y2)
if true_w > args.width  then args.width  = true_w end
if true_h > args.height then args.height = true_h end
end
args.x = args.x or 1
args.y = args.y or 1
if args.bg ~= nil then
args.fg_bg = core.cpair(args.bg, args.bg)
end
local e = element.new(args)
local any_thin = false
for p = 1, #args.pipes do
any_thin = args.pipes[p].thin
if any_thin then break end
end
local function vector_draw()
for p = 1, #args.pipes do
local pipe = args.pipes[p]
local x = 1 + pipe.x1
local y = 1 + pipe.y1
local x_step = util.trinary(pipe.x1 >= pipe.x2, -1, 1)
local y_step = util.trinary(pipe.y1 >= pipe.y2, -1, 1)
if pipe.thin then
x_step = util.trinary(pipe.x1 == pipe.x2, 0, x_step)
y_step = util.trinary(pipe.y1 == pipe.y2, 0, y_step)
end
e.w_set_cur(x, y)
local c = core.cpair(pipe.color, e.fg_bg.bkg)
if pipe.align_tr then
for i = 1, pipe.w do
if pipe.thin then
if i == pipe.w then
if y_step > 0 then
e.w_blit("\x93", c.blit_bkg, c.blit_fgd)
else
e.w_blit("\x8e", c.blit_fgd, c.blit_bkg)
end
else
e.w_blit("\x8c", c.blit_fgd, c.blit_bkg)
end
else
if i == pipe.w and y_step > 0 then
e.w_blit(" ", c.blit_bkg, c.blit_fgd)
else
e.w_blit("\x8f", c.blit_fgd, c.blit_bkg)
end
end
x = x + x_step
e.w_set_cur(x, y)
end
x = x - x_step
for _ = 1, pipe.h - 1 do
y = y + y_step
e.w_set_cur(x, y)
if pipe.thin then
e.w_blit("\x95", c.blit_bkg, c.blit_fgd)
else
e.w_blit(" ", c.blit_bkg, c.blit_fgd)
end
end
else
for i = 1, pipe.h do
if pipe.thin then
if i == pipe.h then
if y_step < 0 then
e.w_blit("\x97", c.blit_bkg, c.blit_fgd)
elseif y_step > 0 then
e.w_blit("\x8d", c.blit_fgd, c.blit_bkg)
else
e.w_blit("\x8c", c.blit_fgd, c.blit_bkg)
end
else
e.w_blit("\x95", c.blit_fgd, c.blit_bkg)
end
else
if i == pipe.h and y_step < 0 then
e.w_blit("\x83", c.blit_bkg, c.blit_fgd)
else
e.w_blit(" ", c.blit_bkg, c.blit_fgd)
end
end
y = y + y_step
e.w_set_cur(x, y)
end
y = y - y_step
for _ = 1, pipe.w - 1 do
x = x + x_step
e.w_set_cur(x, y)
if pipe.thin then
e.w_blit("\x8c", c.blit_fgd, c.blit_bkg)
else
e.w_blit("\x83", c.blit_bkg, c.blit_fgd)
end
end
end
end
end
local function draw_map_cell(map, x, y)
local entry = map[x][y]
local char
local invert = false
local function check(cx, cy)
return (map[cx] ~= nil) and (map[cx][cy] ~= nil) and (map[cx][cy] ~= false) and (map[cx][cy].fg == entry.fg)
end
if entry.thin then
if check(x - 1, y) then
if check(x, y - 1) then
if check(x + 1, y) then
if check(x, y + 1) then
char = util.trinary(entry.atr, "\x91", "\x9d")
invert = entry.atr
else
char = util.trinary(entry.atr, "\x8e", "\x8d")
end
else
if check(x, y + 1) then
char = util.trinary(entry.atr, "\x91", "\x95")
invert = entry.atr
else
char = util.trinary(entry.atr, "\x8e", "\x85")
end
end
elseif check(x, y + 1) then
if check(x + 1, y) then
char = util.trinary(entry.atr, "\x93", "\x9c")
invert = entry.atr
else
char = util.trinary(entry.atr, "\x93", "\x94")
invert = entry.atr
end
else
char = "\x8c"
end
elseif check(x + 1, y) then
if check(x, y - 1) then
if check(x, y + 1) then
char = util.trinary(entry.atr, "\x95", "\x9d")
invert = entry.atr
else
char = util.trinary(entry.atr, "\x8a", "\x8d")
end
else
if check(x, y + 1) then
char = util.trinary(entry.atr, "\x97", "\x9c")
invert = entry.atr
else
char = "\x8c"
end
end
else
char = "\x95"
invert = entry.atr
end
else
if check(x, y - 1) then
if (not check(x, y + 1)) and (check(x - 1, y) or check(x + 1, y)) then
char = util.trinary(entry.atr, "\x8f", " ")
invert = not entry.atr
else
char = " "
invert = true
end
elseif check(x, y + 1) then
if (check(x - 1, y) or check(x + 1, y)) then
char = "\x83"
invert = true
else
char = " "
invert = true
end
else
char = util.trinary(entry.atr, "\x8f", "\x83")
invert = not entry.atr
end
end
e.w_set_cur(x, y)
if invert then
e.w_blit(char, entry.bg, entry.fg)
else
e.w_blit(char, entry.fg, entry.bg)
end
end
local function map_draw()
local map = {}
for x = 1, args.width do
table.insert(map, {})
for _ = 1, args.height do table.insert(map[x], false) end
end
for p = 1, #args.pipes do
local pipe = args.pipes[p]
local x = 1 + pipe.x1
local y = 1 + pipe.y1
local x_step = util.trinary(pipe.x1 >= pipe.x2, -1, 1)
local y_step = util.trinary(pipe.y1 >= pipe.y2, -1, 1)
local entry = { atr = pipe.align_tr, thin = pipe.thin, fg = colors.toBlit(pipe.color), bg = e.fg_bg.blit_bkg }
if pipe.align_tr then
for _ = 1, pipe.w do
map[x][y] = entry
x = x + x_step
end
x = x - x_step
for _ = 1, pipe.h do
map[x][y] = entry
y = y + y_step
end
else
for _ = 1, pipe.h do
map[x][y] = entry
y = y + y_step
end
y = y - y_step
for _ = 1, pipe.w do
map[x][y] = entry
x = x + x_step
end
end
end
for x = 1, args.width do
for y = 1, args.height do
if map[x][y] ~= false then draw_map_cell(map, x, y) end
end
end
end
function e.redraw()
if any_thin then map_draw() else vector_draw() end
end
local PipeNetwork, id = e.complete(true)
return PipeNetwork, id
end
