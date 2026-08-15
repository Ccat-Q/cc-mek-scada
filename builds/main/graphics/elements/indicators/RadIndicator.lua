
local types   = require("scada-common.types")
local util    = require("scada-common.util")
local element = require("graphics.element")
return function (args)
element.assert(type(args.label) == "string", "label is a required field")
element.assert(type(args.format) == "string", "format is a required field")
element.assert(util.is_int(args.width), "width is a required field")
args.height = 1
local e = element.new(args)
e.value = args.value or types.new_zero_radiation_reading()
local label_len = string.len(args.label)
local data_start = 1
local clear_width = args.width
if label_len > 0 then
data_start = data_start + (label_len + 1)
clear_width = args.width - (label_len + 1)
end
function e.on_update(value)
e.value = value.radiation
e.w_set_cur(data_start, 1)
e.w_write(util.spaces(clear_width))
local data_str = util.sprintf(args.format, e.value)
e.w_set_cur(data_start, 1)
e.w_set_fgd(e.fg_bg.fgd)
if args.commas then
e.w_write(util.comma_format(data_str))
else
e.w_write(data_str)
end
if args.lu_colors ~= nil then
e.w_set_fgd(args.lu_colors.color_b)
end
e.w_write(" " .. value.unit)
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
if args.lu_colors ~= nil then e.w_set_fgd(args.lu_colors.color_a) end
e.w_set_cur(1, 1)
e.w_write(args.label)
e.on_update(e.value)
end
local RadIndicator, id = e.complete(true)
return RadIndicator, id
end
