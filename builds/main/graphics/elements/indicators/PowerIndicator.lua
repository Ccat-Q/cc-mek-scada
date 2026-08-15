
local util    = require("scada-common.util")
local element = require("graphics.element")
return function (args)
element.assert(type(args.label) == "string", "label is a required field")
element.assert(type(args.unit) == "string", "unit is a required field")
element.assert(type(args.value) == "number", "value is a required field")
element.assert(util.is_int(args.width), "width is a required field")
args.height = 1
local e = element.new(args)
e.value = args.value
local data_start = 0
function e.on_update(value)
e.value = value
local data_str, unit = util.power_format(value, args.unit, false, args.format)
e.w_set_cur(data_start, 1)
e.w_set_fgd(e.fg_bg.fgd)
e.w_write(util.comma_format(data_str))
if args.lu_colors ~= nil then
e.w_set_fgd(args.lu_colors.color_b)
end
if args.rate == true then
unit = unit .. "/t"
end
unit = util.strminw(unit, 5)
e.w_write(" " .. unit)
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
if args.lu_colors ~= nil then e.w_set_fgd(args.lu_colors.color_a) end
e.w_set_cur(1, 1)
e.w_write(args.label)
data_start = string.len(args.label) + 2
if string.len(args.label) == 0 then data_start = 1 end
e.on_update(e.value)
end
local PowerIndicator, id = e.complete(true)
return PowerIndicator, id
end
