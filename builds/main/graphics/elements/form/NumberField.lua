
local util    = require("scada-common.util")
local core    = require("graphics.core")
local element = require("graphics.element")
local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK
return function (args)
element.assert(args.max_int_digits == nil or (util.is_int(args.max_int_digits) and args.max_int_digits > 0), "max_int_digits must be an integer greater than zero if supplied")
element.assert(args.max_frac_digits == nil or (util.is_int(args.max_frac_digits) and args.max_frac_digits > 0), "max_frac_digits must be an integer greater than zero if supplied")
args.height = 1
args.can_focus = true
local e = element.new(args)
local has_decimal = false
args.max_chars = args.max_chars or e.frame.w
local format = "%d"
if args.allow_decimal then
if args.max_frac_digits then
format = "%."..args.max_frac_digits.."f"
else format = "%f" end
end
local function _set_value(num)
local str = util.sprintf(format, num)
if args.allow_decimal then
local found_nonzero = false
local str_table = {}
for i = #str, 1, -1 do
local c = string.sub(str, i, i)
if found_nonzero then
str_table[i] = c
else
if c == "." then
found_nonzero = true
elseif c ~= "0" then
str_table[i] = c
found_nonzero = true
end
end
end
e.value = table.concat(str_table)
else
e.value = str
end
end
_set_value(args.default or 0)
local ifield = core.new_ifield(e, args.max_chars, args.fg_bg, args.dis_fg_bg, args.align_right)
local function _parse_input()
local val, max, min = tonumber(e.value), tonumber(args.max), tonumber(args.min)
if val then
if args.max_int_digits or args.max_frac_digits then
local str = e.value
local ceil = false
if string.find(str, "-") then str = string.sub(e.value, 2) end
local parts = util.strtok(str, ".")
if parts[1] and args.max_int_digits then
if string.len(parts[1]) > args.max_int_digits then
parts[1] = string.rep("9", args.max_int_digits)
ceil = true
end
end
if args.allow_decimal and args.max_frac_digits then
if ceil then
parts[2] = string.rep("9", args.max_frac_digits)
elseif parts[2] and (string.len(parts[2]) > args.max_frac_digits) then
local scaled = math.fmod(val, 1) * (10 ^ (args.max_frac_digits))
local value = math.floor(scaled + 0.5)
local unscaled = value * (10 ^ (-args.max_frac_digits))
parts[2] = string.sub(tostring(unscaled), 3) -- remove starting "0."
end
end
if parts[2] then parts[2] = "." .. parts[2] else parts[2] = "" end
val = tonumber((parts[1] or "") .. parts[2]) or 0
end
if max and val > max then
_set_value(max)
ifield.nav_start()
elseif min and val < min then
_set_value(min)
ifield.nav_start()
else
_set_value(val)
ifield.nav_end()
end
else
e.value = ""
end
ifield.show()
end
function e.handle_mouse(event)
if e.enabled and e.in_frame_bounds(event.current.x, event.current.y) then
if core.events.was_clicked(event.type) then
local x = event.current.x
if not e.is_focused() then
x = ifield.get_cursor_align_shift(x)
end
e.take_focus()
if event.type == MOUSE_CLICK.UP then
ifield.move_cursor(x)
end
elseif event.type == MOUSE_CLICK.DOUBLE_CLICK then
ifield.select_all()
end
end
end
function e.handle_key(event)
if event.type == KEY_CLICK.CHAR and string.len(e.value) < args.max_chars then
if tonumber(event.name) then
if e.value == 0 then e.value = "" end
ifield.try_insert_char(event.name)
end
elseif event.type == KEY_CLICK.DOWN or event.type == KEY_CLICK.HELD then
if (event.key == keys.backspace or event.key == keys.delete) and (string.len(e.value) > 0) then
ifield.backspace()
has_decimal = string.find(e.value, "%.") ~= nil
elseif (event.key == keys.period or event.key == keys.numPadDecimal) and (not has_decimal) and args.allow_decimal then
has_decimal = true
ifield.try_insert_char(".")
elseif (event.key == keys.minus or event.key == keys.numPadSubtract) and (string.len(e.value) == 0) and args.allow_negative then
ifield.set_value("-")
elseif event.key == keys.left then
ifield.nav_left()
elseif event.key == keys.right then
ifield.nav_right()
elseif event.key == keys.a and event.ctrl then
ifield.select_all()
elseif event.key == keys.home or event.key == keys.up then
ifield.nav_start()
elseif event.key == keys["end"] or event.key == keys.down then
ifield.nav_end()
end
end
end
function e.set_value(val)
local num, max, min = tonumber(val), tonumber(args.max), tonumber(args.min)
if max and num > max then
_set_value(max)
elseif min and num < min then
_set_value(min)
elseif num then
_set_value(num)
end
ifield.set_value(e.value)
end
function e.set_min(min)
args.min = min
_parse_input()
end
function e.set_max(max)
args.max = max
_parse_input()
end
function e.handle_paste(text)
if tonumber(text) then
ifield.set_value("" .. tonumber(text))
else
ifield.set_value("0")
end
end
function e.on_unfocused()
_parse_input()
if type(args.on_unfocus) == "function" then args.on_unfocus(tonumber(e.value)) end
end
e.on_focused = ifield.show
e.on_enabled = ifield.show
e.on_disabled = ifield.show
e.redraw = ifield.show
local NumberField, id = e.complete(true)
function NumberField.get_numeric()
return tonumber(e.value) or 0
end
return NumberField, id
end
