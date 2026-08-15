
local util    = require("scada-common.util")
local element = require("graphics.element")
local flasher = require("graphics.flasher")
return function (args)
element.assert(type(args.label) == "string", "label is a required field")
element.assert(type(args.colors) == "table", "colors is a required field")
if args.flash then
element.assert(util.is_int(args.period), "period is a required field if flash is enabled")
end
args.height = 1
args.width = math.max(args.min_label_width or 1, string.len(args.label)) + 2
local flash_on = true
local e = element.new(args)
e.value = false
local function flash_callback()
e.w_set_cur(1, 1)
if flash_on then
e.w_blit(" \x95", "0" .. args.colors.blit_a, args.colors.blit_a .. e.fg_bg.blit_bkg)
else
e.w_blit(" \x95", "0" .. args.colors.blit_b, args.colors.blit_b .. e.fg_bg.blit_bkg)
end
flash_on = not flash_on
end
local function enable()
if args.flash then
flash_on = true
flasher.start(flash_callback, args.period)
else
e.w_set_cur(1, 1)
e.w_blit(" \x95", "0" .. args.colors.blit_a, args.colors.blit_a .. e.fg_bg.blit_bkg)
end
end
local function disable()
if args.flash then
flash_on = false
flasher.stop(flash_callback)
end
e.w_set_cur(1, 1)
e.w_blit(" \x95", "0" .. args.colors.blit_b, args.colors.blit_b .. e.fg_bg.blit_bkg)
end
function e.on_update(new_state)
e.value = new_state
if new_state then enable() else disable() end
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
e.on_update(false)
e.w_set_cur(3, 1)
e.w_write(args.label)
end
local IndicatorLight, id = e.complete(true)
return IndicatorLight, id
end
