
local psil = require("scada-common.psil")
local util = require("scada-common.util")
local databus = {}
local _dbus = {
wd_modem = true,
wl_modem = true,
coroutines = {}
}
local function eval_status()
local ok = _dbus.wd_modem and _dbus.wl_modem
for _, v in pairs(_dbus.coroutines) do ok = ok and v end
databus.ps.publish("status", ok)
end
databus.ps = psil.create()
local RTU_HW_STATE = {
OFFLINE = 1,
FAULTED = 2,
UNFORMED = 3,
OK = 4
}
databus.RTU_HW_STATE = RTU_HW_STATE
function databus.heartbeat() databus.ps.toggle("heartbeat") end
function databus.tx_versions(rtu_v, comms_v)
databus.ps.publish("version", rtu_v)
databus.ps.publish("comms_version", comms_v)
end
function databus.tx_hw_wd_modem(has_modem)
databus.ps.publish("has_wd_modem", has_modem)
_dbus.wd_modem = has_modem
eval_status()
end
function databus.tx_hw_wl_modem(has_modem)
databus.ps.publish("has_wl_modem", has_modem)
_dbus.wl_modem = has_modem
eval_status()
end
function databus.tx_wd_net(up)
databus.ps.publish("has_wd_net", up)
end
function databus.tx_wl_net(up)
databus.ps.publish("has_wl_net", up)
end
function databus.tx_hw_spkr_count(count)
databus.ps.publish("speaker_count", count)
end
function databus.tx_unit_hw_type(uid, type)
databus.ps.publish("unit_type_" .. uid, type)
end
function databus.tx_unit_hw_status(uid, status)
databus.ps.publish("unit_hw_" .. uid, status)
end
function databus.tx_rt_status(thread, ok)
local name = util.c("routine__", thread)
databus.ps.publish(name, ok)
_dbus.coroutines[name] = ok
eval_status()
end
function databus.tx_link_state(state)
databus.ps.publish("link_state", state)
end
return databus
