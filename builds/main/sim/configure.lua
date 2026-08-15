
local util = require("scada-common.util")
local println = util.println
local print = print
local read = read
local configure = {}
local function prompt(question, default, is_number)
local dstr = tostring(default)
print(question .. " [" .. dstr .. "]: ")
local input = read()
if input == "" then
return default
elseif is_number then
local n = tonumber(input)
if n then return n else return default end
else
return input
end
end
function configure.configure()
println("SCADA Simulator Configuration")
println("=============================")
println("")
local loaded = settings.load("/sim.settings")
local cur = {}
if loaded then
cur = {
SVR_Channel = settings.get("SVR_Channel"),
PLC_Channel = settings.get("PLC_Channel"),
RTU_Channel = settings.get("RTU_Channel"),
AuthKey = settings.get("AuthKey"),
TrustedRange = settings.get("TrustedRange"),
SimulatePLC = settings.get("SimulatePLC"),
SimulateRTU = settings.get("SimulateRTU"),
UnitCount = settings.get("UnitCount"),
BoilersPerUnit = settings.get("BoilersPerUnit"),
TurbinesPerUnit = settings.get("TurbinesPerUnit"),
ModemSide = settings.get("ModemSide")
}
end
println("== Network ==")
local svr = prompt("SVR channel (supervisor listens here)", cur.SVR_Channel or 16240, true)
local plc = prompt("PLC channel (supervisor sends PLC frames here)", cur.PLC_Channel or 16241, true)
local rtu = prompt("RTU channel (supervisor sends RTU frames here)", cur.RTU_Channel or 16242, true)
local auth = prompt("AuthKey (HMAC key, must match supervisor; empty = off)", cur.AuthKey or "", false)
local range = prompt("TrustedRange (max distance, 0 = unlimited)", cur.TrustedRange or 0, true)
println("")
println("== Simulation Topology ==")
local plc_en = prompt("Simulate a reactor PLC? (y/n)", (cur.SimulatePLC ~= false) and "y" or "n", false)
local rtu_en = prompt("Simulate an RTU gateway? (y/n)", (cur.SimulateRTU ~= false) and "y" or "n", false)
local units = prompt("Number of reactor units (1-4)", cur.UnitCount or 1, true)
units = math.max(1, math.min(4, units or 1))
local boilers = 0
local turbines = 0
if string.lower(tostring(rtu_en)) ~= "n" then
boilers = prompt("Boilers per unit (1-2)", cur.BoilersPerUnit or 1, true)
boilers = math.max(1, math.min(2, boilers or 1))
turbines = prompt("Turbines per unit (1-3)", cur.TurbinesPerUnit or 1, true)
turbines = math.max(1, math.min(3, turbines or 1))
end
local modem_side = prompt("Modem side (optional, auto-detect if empty)", cur.ModemSide or "", false)
if modem_side == "" then modem_side = nil end
settings.set("SVR_Channel", svr)
settings.set("PLC_Channel", plc)
settings.set("RTU_Channel", rtu)
settings.set("AuthKey", auth)
settings.set("TrustedRange", range)
settings.set("SimulatePLC", string.lower(tostring(plc_en)) ~= "n")
settings.set("SimulateRTU", string.lower(tostring(rtu_en)) ~= "n")
settings.set("UnitCount", units)
settings.set("BoilersPerUnit", boilers)
settings.set("TurbinesPerUnit", turbines)
if modem_side then settings.set("ModemSide", modem_side) end
local saved = settings.save("/sim.settings")
println("")
if saved then
println("Configuration saved to /sim.settings")
return true
else
println("ERROR: failed to save configuration")
return false, "failed to save /sim.settings"
end
end
return configure
