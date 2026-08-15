
local util    = require("scada-common.util")
local element = require("graphics.element")
local flasher = require("graphics.flasher")
return function (args)
element.assert(type(args.label) == "string", "label is a required field")
element.assert(type(args.c1) == "number", "c1 is a required field")
element.assert(type(args.c2) == "number", "c2 is a required field")
element.assert(type(args.c3) == "number", "c3 is a required field")
if args.flash then
element.assert(util.is_int(args.period), "period is a required field if flash is enabled")
end
args.height = 1
args.width = math.max(args.min_label_width or 1, string.len(args.label)) + 2
local e = element.new(args)
e.value = 1
local flash_on = true
local c1 = colors.toBlit(args.c1)
local c2 = colors.toBlit(args.c2)
local c3 = colors.toBlit(args.c3)
local function flash_callback()
e.w_set_cur(1, 1)
if flash_on then
if e.value == 2 then
e.w_blit(" \x95", "0" .. c2, c2 .. e.fg_bg.blit_bkg)
elseif e.value == 3 then
e.w_blit(" \x95", "0" .. c3, c3 .. e.fg_bg.blit_bkg)
end
else
e.w_blit(" \x95", "0" .. c1, c1 .. e.fg_bg.blit_bkg)
end
flash_on = not flash_on
end
function e.on_update(new_state)
local was_off = e.value <= 1
e.value = new_state
e.w_set_cur(1, 1)
if args.flash then
if was_off and (new_state > 1) then
flash_on = true
flasher.start(flash_callback, args.period)
elseif new_state <= 1 then
flash_on = false
flasher.stop(flash_callback)
e.w_blit(" \x95", "0" .. c1, c1 .. e.fg_bg.blit_bkg)
end
elseif new_state == 2 then
e.w_blit(" \x95", "0" .. c2, c2 .. e.fg_bg.blit_bkg)
elseif new_state == 3 then
e.w_blit(" \x95", "0" .. c3, c3 .. e.fg_bg.blit_bkg)
else
e.w_blit(" \x95", "0" .. c1, c1 .. e.fg_bg.blit_bkg)
end
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
e.on_update(1)
e.w_write(args.label)
end
local TriIndicatorLight, id = e.complete(true)
return TriIndicatorLight, id
end
