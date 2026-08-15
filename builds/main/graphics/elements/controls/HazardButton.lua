
local tcd     = require("scada-common.tcd")
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
element.assert(type(args.text) == "string", "text is a required field")
element.assert(type(args.accent) == "number", "accent is a required field")
element.assert(type(args.callback) == "function", "callback is a required field")
args.height = 3
args.width = string.len(args.text) + 4
local timeout = args.timeout or 1.5
local e = element.new(args)
local function draw_border(accent)
e.w_set_fgd(accent)
e.w_set_bkg(args.fg_bg.bkg)
e.w_set_cur(1, 1)
e.w_write("\x99" .. string.rep("\x89", args.width - 2) .. "\x99")
e.w_set_cur(1, 2)
e.w_set_fgd(args.fg_bg.bkg)
e.w_set_bkg(accent)
e.w_write("\x99")
e.w_set_fgd(args.fg_bg.bkg)
e.w_set_bkg(accent)
e.w_set_cur(args.width, 2)
e.w_write("\x99")
e.w_set_fgd(accent)
e.w_set_bkg(args.fg_bg.bkg)
e.w_set_cur(1, 3)
e.w_write("\x99" .. string.rep("\x98", args.width - 2) .. "\x99")
end
local function on_timeout(n)
if n == nil then n = 0 end
if n == 0 then
e.w_set_fgd(args.fg_bg.fgd)
e.w_set_cur(3, 2)
e.w_write(args.text)
end
if n >= 4 then
elseif n % 2 == 0 then
tcd.dispatch(0.25, function ()
e.w_set_fgd(args.accent)
e.w_set_cur(3, 2)
e.w_write(args.text)
on_timeout(n + 1)
on_timeout(n + 1)
end)
elseif n % 1 then
tcd.dispatch(0.25, function ()
e.w_set_fgd(args.fg_bg.fgd)
e.w_set_cur(3, 2)
e.w_write(args.text)
on_timeout(n + 1)
end)
end
end
local function on_success()
e.w_set_fgd(args.fg_bg.fgd)
e.w_set_cur(3, 2)
e.w_write(args.text)
end
local function on_failure(n)
if n == nil then n = 0 end
if n == 0 then
e.w_set_fgd(args.fg_bg.fgd)
e.w_set_cur(3, 2)
e.w_write(args.text)
end
if n >= 2 then
elseif n % 2 == 0 then
tcd.dispatch(0.5, function ()
e.w_set_fgd(args.accent)
e.w_set_cur(3, 2)
e.w_write(args.text)
on_failure(n + 1)
end)
elseif n % 1 then
tcd.dispatch(0.25, function ()
e.w_set_fgd(args.fg_bg.fgd)
e.w_set_cur(3, 2)
e.w_write(args.text)
on_failure(n + 1)
end)
end
end
function e.handle_mouse(event)
if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) then
e.w_set_fgd(args.accent)
e.w_set_cur(3, 2)
e.w_write(args.text)
tcd.abort(on_timeout)
tcd.abort(on_success)
tcd.abort(on_failure)
tcd.dispatch(timeout, on_timeout)
args.callback()
end
end
function e.set_value(val)
if val then e.handle_mouse(core.events.mouse_generic(core.events.MOUSE_CLICK.UP, 1, 1)) end
end
function e.on_disabled()
if args.dis_colors then
draw_border(args.dis_colors.color_a)
e.w_set_fgd(args.dis_colors.color_b)
e.w_set_cur(3, 2)
e.w_write(args.text)
end
end
function e.on_enabled()
draw_border(args.accent)
e.w_set_fgd(args.fg_bg.fgd)
e.w_set_cur(3, 2)
e.w_write(args.text)
end
function e.redraw()
e.w_set_cur(3, 2)
e.w_write(args.text)
draw_border(args.accent)
end
local HazardButton, id = e.complete(true)
function HazardButton.on_response(success)
tcd.abort(on_timeout)
if success then on_success() else on_failure(0) end
end
return HazardButton, id
end
