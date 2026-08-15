
local tcd     = require("scada-common.tcd")
local core    = require("graphics.core")
local element = require("graphics.element")
local MOUSE_CLICK = core.events.MOUSE_CLICK
return function (args)
element.assert(type(args.text) == "string", "text is a required field")
element.assert(type(args.title) == "string", "title is a required field")
element.assert(type(args.callback) == "function", "callback is a required field")
element.assert(type(args.app_fg_bg) == "table", "app_fg_bg is a required field")
args.height = 4
args.width = 7
local e = element.new(args)
local function draw()
local fgd = args.app_fg_bg.fgd
local bkg = args.app_fg_bg.bkg
if e.value then
fgd = args.active_fg_bg.fgd
bkg = args.active_fg_bg.bkg
end
e.w_set_cur(2, 1)
e.w_set_fgd(fgd)
e.w_set_bkg(bkg)
e.w_write("\x9f\x83\x83\x83")
e.w_set_fgd(bkg)
e.w_set_bkg(fgd)
e.w_write("\x90")
e.w_set_fgd(fgd)
e.w_set_bkg(bkg)
e.w_set_cur(2, 2)
e.w_write("\x95   ")
e.w_set_fgd(bkg)
e.w_set_bkg(fgd)
e.w_write("\x95")
e.w_set_cur(2, 3)
e.w_write("\x82\x8f\x8f\x8f\x81")
e.w_set_cur(4, 2)
e.w_set_fgd(fgd)
e.w_set_bkg(bkg)
e.w_write(args.text)
end
local function show_pressed()
if e.enabled and args.active_fg_bg ~= nil then
e.value = true
e.w_set_fgd(args.active_fg_bg.fgd)
e.w_set_bkg(args.active_fg_bg.bkg)
draw()
end
end
local function show_unpressed()
if e.enabled and args.active_fg_bg ~= nil then
e.value = false
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
draw()
end
end
function e.handle_mouse(event)
if e.enabled then
if event.type == MOUSE_CLICK.TAP then
show_pressed()
if args.active_fg_bg ~= nil then tcd.dispatch(0.25, show_unpressed) end
args.callback()
elseif event.type == MOUSE_CLICK.DOWN then
show_pressed()
elseif event.type == MOUSE_CLICK.UP then
show_unpressed()
if e.in_frame_bounds(event.current.x, event.current.y) then
args.callback()
end
end
end
end
function e.set_value(val)
if val then e.handle_mouse(core.events.mouse_generic(core.events.MOUSE_CLICK.UP, 1, 1)) end
end
function e.redraw()
e.w_set_cur(math.floor((e.frame.w - string.len(args.title)) / 2) + 1, 4)
e.w_write(args.title)
draw()
end
local App, id = e.complete(true)
return App, id
end
