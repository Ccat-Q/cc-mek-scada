
local databus = require("sim.databus")
local tui = {}
local facility
local plc
local rtu
local control
local SIM_VERSION = ""
local tab = 1
function tui.set_version(version) SIM_VERSION = version end
function tui.init(cfg, fac, plc_state, rtu_state, ctl)
facility, plc, rtu, control = fac, plc_state, rtu_state, ctl
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
end
local function bar(fill, width)
if fill == nil then fill = 0 end
local filled = math.floor(fill * width)
if filled < 0 then filled = 0 end
if filled > width then filled = width end
return "[" .. string.rep("=", filled) .. string.rep(" ", width - filled) .. "]"
end
local function commas(n)
local s = string.format("%.0f", n or 0)
local k = ""
while #s > 3 do
k = "," .. s:sub(-3) .. k
s = s:sub(1, -4)
end
return s .. k
end
local function link_txt(linked)
if linked then return "已连接" else return "断开" end
end
local function draw_status()
local w, h = term.getSize()
local lines = {}
local ln = 1
lines[ln] = "=== SCADA 模拟器 v" .. SIM_VERSION .. " ==="; ln = ln + 1
lines[ln] = "PLC [" .. link_txt(plc.linked) .. "]   RTU [" .. link_txt(rtu.linked) .. "]"
ln = ln + 2
local unit = facility.units[plc.reactor_id]
if unit then
local r = unit.reactor
local st = r.status
local act = st.active and "运行中" or "已停止"
local trip = r.tripped and ("  跳闸:" .. r.trip_cause) or ""
lines[ln] = "反应堆  " .. act .. "  温度 " .. string.format("%.1f", st.temp) .. "K" ..
"  热量 " .. commas(st.heating_rate) .. trip
ln = ln + 1
lines[ln] = "燃烧 " .. string.format("%.1f", st.burn_rate) .. "/" ..
string.format("%.1f", st.act_burn_rate) .. " mB/t   损伤 " ..
string.format("%.1f", st.damage) .. "%"
ln = ln + 1
local bw = math.max(10, w - 22)
lines[ln] = "燃料  " .. bar(st.fuel_fill, bw) .. string.format(" %3.0f%%", st.fuel_fill * 100); ln = ln + 1
lines[ln] = "废料 " .. bar(st.waste_fill, bw) .. string.format(" %3.0f%%", st.waste_fill * 100); ln = ln + 1
lines[ln] = "冷却 " .. bar(st.coolant_fill, bw) .. string.format(" %3.0f%%", st.coolant_fill * 100); ln = ln + 1
lines[ln] = "热冷却 " .. bar(st.hcoolant_fill, bw) .. string.format(" %3.0f%%", st.hcoolant_fill * 100); ln = ln + 2
if #unit.boilers > 0 then
local b = unit.boilers[1]
lines[ln] = "锅炉  温度 " .. string.format("%.1f", b.state.temperature) .. "K" ..
"  沸腾 " .. string.format("%.0f", b.state.boil_rate)
ln = ln + 1
lines[ln] = "蒸汽 " .. bar(b.tanks.steam_fill, bw) .. string.format(" %3.0f%%", b.tanks.steam_fill * 100) ..
"  水 " .. bar(b.tanks.water_fill, bw) .. string.format(" %3.0f%%", b.tanks.water_fill * 100)
ln = ln + 2
end
if #unit.turbines > 0 then
local t = unit.turbines[1]
lines[ln] = "涡轮机  流量 " .. string.format("%.0f", t.state.flow_rate) ..
"  发电 " .. commas(t.state.prod_rate) .. " RF/t"
ln = ln + 1
lines[ln] = "蒸汽 " .. bar(t.tanks.steam_fill, bw) .. string.format(" %3.0f%%", t.tanks.steam_fill * 100) ..
"  能量 " .. bar(t.tanks.energy_fill, bw) .. string.format(" %3.0f%%", t.tanks.energy_fill * 100)
ln = ln + 2
end
local ess = facility.ess
lines[ln] = "ESS  " .. bar(ess.tanks.energy_fill, bw) .. string.format(" %3.0f%%", ess.tanks.energy_fill * 100) ..
"  入 " .. commas(ess.state.last_input) .. "  出 " .. commas(ess.state.last_output)
ln = ln + 1
local sps = facility.sps
lines[ln] = "SPS  处理 " .. string.format("%.1f", sps.state.process_rate) ..
"  入 " .. bar(sps.tanks.input_fill, bw) .. string.format(" %3.0f%%", sps.tanks.input_fill * 100)
ln = ln + 2
end
lines[ln] = "[1]状态 [2]日志  [b]燃烧 [s]急停 [a]启动 [+]-燃烧 [-]-燃烧 [h]热量 [f]燃料 [q]退出"
ln = ln + 1
term.clear()
for i = 1, math.min(ln - 1, h) do
term.setCursorPos(1, i)
local line = lines[i] or ""
term.write(line:sub(1, w))
end
end
local function draw_log()
local w, h = term.getSize()
local lines = {}
lines[1] = "=== SCADA 模拟器日志 ==="
lines[2] = ""
local logs = databus.get_log(nil, h - 4)
local i = 3
for _, entry in ipairs(logs) do
if i <= h then
lines[i] = entry.text
i = i + 1
end
end
lines[math.min(i, h)] = "[1]状态 [2]日志  [q]退出"
term.clear()
for row = 1, math.min(#lines, h) do
term.setCursorPos(1, row)
term.write((lines[row] or ""):sub(1, w))
end
end
function tui.draw()
if tab == 2 then
draw_log()
else
draw_status()
end
end
function tui.handle_key(key)
if key == keys.num1 then
tab = 1
tui.draw()
return true
elseif key == keys.num2 then
tab = 2
tui.draw()
return true
elseif key == keys.q then
return false
elseif key == keys.b then
local _, h = term.getSize()
term.setCursorPos(1, h)
term.clearLine()
write("燃烧速率 (mB/t): ")
local value = tonumber(read())
term.clearLine()
if value then control.set_burn(value) end
tui.draw()
return true
end
if key == keys.s then control.scram() return true end
if key == keys.a then control.activate() return true end
if key == keys.plus then control.nudge_burn(100) return true end
if key == keys.minus then control.nudge_burn(-100) return true end
if key == keys.h then control.nudge_heat(0.05) return true end
if key == keys.f then control.nudge_fuel(0.1) return true end
return false
end
return tui
