
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
return function (args)
element.assert(type(args.text) == "string", "text is a required field")
element.assert(type(args.callback) == "function", "callback is a required field")
element.assert((type(args.min_width) == "nil") or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")
element.assert((type(args.active_text) == "string") or (type(args.active_fg_bg) == "table"), "active_text or active_fg_bg must be set")
local text_width = string.len(args.text)
args.height = 1
args.min_width = args.min_width or 0
args.width = math.max(text_width, args.min_width)
local e = element.new(args)
e.value = args.default or false
local h_pad = math.floor((e.frame.w - text_width) / 2) + 1
local v_pad = math.floor(e.frame.h / 2) + 1
function e.redraw()
if e.enabled then
if e.value and args.active_fg_bg then
e.w_set_fgd(args.active_fg_bg.fgd)
e.w_set_bkg(args.active_fg_bg.bkg)
else
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
end
elseif args.dis_fg_bg ~= nil then
e.w_set_fgd(args.dis_fg_bg.fgd)
e.w_set_bkg(args.dis_fg_bg.bkg)
end
e.window.clear()
e.w_set_cur(h_pad, v_pad)
e.w_write(util.trinary(e.value and args.active_text, args.active_text, args.text))
end
function e.handle_mouse(event)
if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) then
e.value = not e.value
e.redraw()
args.callback(e.value)
end
end
function e.set_value(val)
if e.value ~= val then
e.value = val
e.redraw()
args.callback(e.value)
end
end
function e.on_enabled()
if args.dis_fg_bg ~= nil then e.redraw() end
end
function e.on_disabled()
if args.dis_fg_bg ~= nil then e.redraw() end
end
local SwitchButton, id = e.complete(true)
return SwitchButton, id
end
