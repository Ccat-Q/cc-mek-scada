
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
println("SCADA 模拟器配置")
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
SimulateSPS = settings.get("SimulateSPS"),
ShowUI = settings.get("ShowUI"),
UnitCount = settings.get("UnitCount"),
BoilersPerUnit = settings.get("BoilersPerUnit"),
TurbinesPerUnit = settings.get("TurbinesPerUnit"),
ModemSide = settings.get("ModemSide")
}
end
println("== 网络 ==")
local svr = prompt("SVR 频道（监控端在此监听）", cur.SVR_Channel or 16240, true)
local plc = prompt("PLC 频道（监控端在此发送 PLC 帧）", cur.PLC_Channel or 16241, true)
local rtu = prompt("RTU 频道（监控端在此发送 RTU 帧）", cur.RTU_Channel or 16242, true)
local auth = prompt("AuthKey（HMAC 密钥，须与监控端一致；留空 = 关闭）", cur.AuthKey or "", false)
local range = prompt("TrustedRange（最大距离，0 = 不限）", cur.TrustedRange or 0, true)
println("")
println("== 模拟拓扑 ==")
local plc_en = prompt("模拟反应堆 PLC？(y/n)", (cur.SimulatePLC ~= false) and "y" or "n", false)
local rtu_en = prompt("模拟 RTU 网关？(y/n)", (cur.SimulateRTU ~= false) and "y" or "n", false)
local units = prompt("反应堆机组数量（1-4）", cur.UnitCount or 1, true)
units = math.max(1, math.min(4, units or 1))
local boilers = 0
local turbines = 0
if string.lower(tostring(rtu_en)) ~= "n" then
print("注意：锅炉/涡轮机数量必须与监控端的设施配置一致")
print("      否则设备将显示 'bad index'。")
boilers = prompt("每机组锅炉数量（1-2）", cur.BoilersPerUnit or 1, true)
boilers = math.max(1, math.min(2, boilers or 1))
turbines = prompt("每机组涡轮机数量（1-3）", cur.TurbinesPerUnit or 1, true)
turbines = math.max(1, math.min(3, turbines or 1))
end
local sps_en = prompt("模拟设施 SPS？(y/n)", (cur.SimulateSPS ~= false) and "y" or "n", false)
local ui_en = prompt("显示前面板界面？(y/n)", (cur.ShowUI ~= false) and "y" or "n", false)
local modem_side = prompt("调制解调器侧（可选，留空自动检测）", cur.ModemSide or "", false)
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
settings.set("SimulateSPS", string.lower(tostring(sps_en)) ~= "n")
settings.set("ShowUI", string.lower(tostring(ui_en)) ~= "n")
if modem_side then settings.set("ModemSide", modem_side) end
local saved = settings.save("/sim.settings")
println("")
if saved then
println("配置已保存到 /sim.settings")
return true
else
println("错误：保存配置失败")
return false, "无法保存 /sim.settings"
end
end
return configure
