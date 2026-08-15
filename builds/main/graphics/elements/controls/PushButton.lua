
local tcd     = require("scada-common.tcd")
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
local ALIGN = core.ALIGN
local MOUSE_CLICK = core.events.MOUSE_CLICK
local KEY_CLICK = core.events.KEY_CLICK
return function (args)
element.assert(type(args.text) == "string", "text is a required field")
element.assert(type(args.callback) == "function", "callback is a required field")
element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")
local text_width = string.len(args.text)
local alignment = args.alignment or ALIGN.CENTER
args.can_focus = true
args.min_width = args.min_width or 0
args.width = math.max(text_width, args.min_width)
local function constrain(frame)
return frame.w, math.max(1, #util.strwrap(args.text, frame.w))
end
local e = element.new(args, constrain)
local text_lines = util.strwrap(args.text, e.frame.w)
function e.redraw()
e.window.clear()
for i = 1, #text_lines do
if i > e.frame.h then break end
local len = string.len(text_lines[i])
if alignment == ALIGN.CENTER then
e.w_set_cur(math.floor((e.frame.w - len) / 2) + 1, i)
elseif alignment == ALIGN.RIGHT then
e.w_set_cur((e.frame.w - len) + 1, i)
else
e.w_set_cur(1, i)
end
e.w_write(text_lines[i])
end
end
local function show_pressed()
if e.enabled and args.active_fg_bg ~= nil then
e.value = true
e.w_set_fgd(args.active_fg_bg.fgd)
e.w_set_bkg(args.active_fg_bg.bkg)
e.redraw()
end
end
local function show_unpressed()
if e.enabled and args.active_fg_bg ~= nil then
e.value = false
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
e.redraw()
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
function e.handle_key(event)
if event.type == KEY_CLICK.DOWN then
if event.key == keys.space or event.key == keys.enter or event.key == keys.numPadEnter then
args.callback()
show_unpressed()
if args.active_fg_bg ~= nil then tcd.dispatch(0.25, show_pressed) end
end
end
end
function e.set_value(val)
if val then e.handle_mouse(core.events.mouse_generic(core.events.MOUSE_CLICK.UP, 1, 1)) end
end
function e.on_enabled()
if args.dis_fg_bg ~= nil then
e.value = false
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
e.redraw()
end
end
function e.on_disabled()
if args.dis_fg_bg ~= nil then
e.value = false
e.w_set_fgd(args.dis_fg_bg.fgd)
e.w_set_bkg(args.dis_fg_bg.bkg)
e.redraw()
end
end
e.on_focused = show_pressed
e.on_unfocused = show_unpressed
local PushButton, id = e.complete(true)
return PushButton, id
end
