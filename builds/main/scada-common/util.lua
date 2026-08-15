
local cc_strings = require("cc.strings")
local const      = require("scada-common.constants")
local math = math
local string = string
local table = table
local os = os
local getmetatable = getmetatable
local print = print
local tostring = tostring
local type = type
local t_concat = table.concat
local t_insert = table.insert
local t_pack   = table.pack
local util = {}
util.version = "1.10.4"
util.TICK_TIME_S = 0.05
util.TICK_TIME_MS = 50
function util.trinary(cond, a, b)
if cond then return a else return b end
end
local p_time = "[%H:%M:%S] "
function util.print(message) term.write(tostring(message)) end
function util.println(message) print(tostring(message)) end
function util.print_ts(message) term.write(os.date(p_time) .. tostring(message)) end
function util.println_ts(message) print(os.date(p_time) .. tostring(message)) end
function util.strval(val)
local t = type(val)
if t == "string" then return val end
if (t == "table" and (getmetatable(val) == nil or getmetatable(val).__tostring == nil)) or t == "function" then
return t_concat{"[", tostring(val), "]"}
else return tostring(val) end
end
function util.strtok(str, sep)
local list = {}
for part in string.gmatch(str, "([^" .. sep .. "]+)") do t_insert(list, part) end
return list
end
function util.spaces(n) return string.rep(" ", n) end
function util.pad(str, n)
local len = string.len(str)
local lpad = math.floor((n - len) / 2)
local rpad = (n - len) - lpad
return t_concat{util.spaces(lpad), str, util.spaces(rpad)}
end
function util.trim(s)
local str = s:gsub("^%s*(.-)%s*$", "%1")
return str
end
function util.strwrap(str, limit)
assert(limit > 0, "util.strwrap() limit not greater than 0")
return cc_strings.wrap(str, limit)
end
function util.strminw(str, width) return cc_strings.ensure_width(str, width) end
function util.concat(...)
local args, strings = t_pack(...), {}
for i = 1, args.n do strings[i] = util.strval(args[i]) end
return t_concat(strings)
end
util.c = util.concat
function util.sprintf(format, ...) return string.format(format, ...) end
function util.comma_format(num)
local formatted = num
local commas = 0
local i = 1
while i > 0 do
formatted, i = formatted:gsub("^(%s-%d+)(%d%d%d)", "%1,%2")
if i > 0 then commas = commas + 1 end
end
local _, num_spaces = formatted:gsub(" %s-", "")
local remove = math.min(num_spaces, commas)
formatted = string.sub(formatted, remove + 1)
return formatted
end
function util.is_int(x) return type(x) == "number" and x == math.floor(x) end
function util.sign(x) return util.trinary(x < 0, -1, 1) end
function util.round(x) return math.floor(x + 0.5) end
function util.mov_avg(length)
local data = {}
local index = 1
local last_t = 0
local public = {}
function public.reset(x)
index = 1
data = {}
if x then
for _ = 1, length do t_insert(data, x) end
end
end
function public.record(x, t)
if type(t) == "number" and last_t == t then return end
data[index] = x
last_t = t
index = index + 1
if index > length then index = 1 end
end
function public.compute()
if #data == 0 then return 0 end
local sum = 0
for i = 1, #data do
sum = sum + data[i]
end
return sum / #data
end
return public
end
function util.ema_filter(alpha)
local state = nil
local last_t = 0
local public = {}
function public.reset(x) state = x end
function public.update(x, t)
if type(t) == "number" and last_t == t then return end
if state then
state = state + (alpha * (x - state))
else state = x end
last_t = t
end
function public.get() return state or 0.0 end
return public
end
function util.time_ms() return os.epoch("local") end
function util.time_s() return os.epoch("local") / 1000.0 end
function util.time() return util.time_ms() end
function util.get_tps()
local t_start = util.time_ms()
util.nop()
local t_end = util.time_ms()
return 1000 / (t_end - t_start)
end
function util.pull_event(target_event) return os.pullEventRaw(target_event) end
function util.push_event(event, param1, param2, param3, param4, param5)
return os.queueEvent(event, param1, param2, param3, param4, param5)
end
function util.start_timer(t) return os.startTimer(t) end
function util.cancel_timer(timer) os.cancelTimer(timer) end
function util.psleep(t) return pcall(os.sleep, t) end
function util.nop() util.psleep(0.05) end
function util.adaptive_delay(target_timing, last_update)
local sleep_for = target_timing - (util.time() - last_update)
if sleep_for >= 50 then util.psleep(sleep_for / 1000.0) end
return util.time()
end
function util.filter_table(t, f, on_delete)
local move_to = 1
for i = 1, #t do
local element = t[i]
if element ~= nil then
if f(element) then
if t[move_to] == nil then
t[move_to] = element
t[i] = nil
end
move_to = move_to + 1
else
if on_delete then on_delete(element) end
t[i] = nil
end
end
end
end
function util.table_contains(t, element)
for i = 1, #t do
if t[i] == element then return true end
end
return false
end
function util.table_len(t)
local n = 0
for _, _ in pairs(t) do n = n + 1 end
return n
end
function util.joules_to_fe_rf(J) return (J * 0.4) end
function util.fe_rf_to_joules(FE) return (FE * 2.5) end
function util.power_format(e, label, combine_label, format)
local unit, value
if type(format) ~= "string" then format = "%.2f" end
local a = math.abs(e)
if a < 1000.0 then
unit = ""
value = e
elseif a < 1000000.0 then
unit = "k"
value = e / 1000.0
elseif a < 1000000000.0 then
unit = "M"
value = e / 1000000.0
elseif a < 1000000000000.0 then
unit = "G"
value = e / 1000000000.0
elseif a < 1000000000000000.0 then
unit = "T"
value = e / 1000000000000.0
elseif a < 1000000000000000000.0 then
unit = "P"
value = e / 1000000000000000.0
elseif a < 1000000000000000000000.0 then
unit = "E"
value = e / 1000000000000000000.0
else
unit = "Z"
value = e / 1000000000000000000000.0
end
unit = unit .. label
if combine_label then
return util.sprintf(util.c(format, " %s"), value, unit), unit
else
return util.sprintf(format, value), unit
end
end
function util.turbine_rotation(turbine)
local build = turbine.build
local inner_vol = build.steam_cap / const.mek.TURBINE_GAS_PER_TANK
local disp_rate = (build.dispersers * const.mek.TURBINE_DISPERSER_FLOW) * inner_vol
local vent_rate = build.vents * const.mek.TURBINE_VENT_FLOW
local max_rate = math.min(disp_rate, vent_rate)
local flow = math.min(max_rate, turbine.tanks.steam.amount)
return (flow * (turbine.tanks.steam.amount / build.steam_cap)) / max_rate
end
function util.new_watchdog(timeout)
local self = { timeout = timeout, wd_timer = util.start_timer(timeout) }
local public = {}
function public.is_timer(timer) return self.wd_timer == timer end
function public.feed()
public.cancel()
self.wd_timer = util.start_timer(self.timeout)
end
function public.cancel()
if self.wd_timer ~= nil then util.cancel_timer(self.wd_timer) end
end
return public
end
function util.new_clock(period)
local self = { period = period, timer = nil }
local public = {}
function public.is_clock(timer) return self.timer == timer end
function public.start() self.timer = util.start_timer(self.period) end
return public
end
function util.new_validator()
local valid = true
local public = {}
function public.assert_type_bool(value) valid = valid and type(value) == "boolean" end
function public.assert_type_num(value) valid = valid and type(value) == "number" end
function public.assert_type_int(value) valid = valid and util.is_int(value) end
function public.assert_type_str(value) valid = valid and type(value) == "string" end
function public.assert_type_table(value) valid = valid and type(value) == "table" end
function public.assert(check) valid = valid and (check == true) end
function public.assert_eq(check, expect) valid = valid and check == expect end
function public.assert_min(check, min) valid = valid and check >= min end
function public.assert_min_ex(check, min) valid = valid and check > min end
function public.assert_max(check, max) valid = valid and check <= max end
function public.assert_max_ex(check, max) valid = valid and check < max end
function public.assert_range(check, min, max) valid = valid and check >= min and check <= max end
function public.assert_range_ex(check, min, max) valid = valid and check > min and check < max end
function public.assert_channel(channel) valid = valid and util.is_int(channel) and channel >= 0 and channel <= 65535 end
function public.valid() return valid end
return public
end
return util
