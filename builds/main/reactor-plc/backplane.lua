
local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local util    = require("scada-common.util")
local databus = require("reactor-plc.databus")
local println = util.println
local backplane = {}
local _bp = {
smem = nil,
wlan_pref = true,
lan_iface = "",
act_nic = nil,
wd_nic = nil,
wl_nic = nil,
nic_map = {}
}
local multi_reactor_warn = "BKPLN: do NOT share reactor connections between multiple PLCs! they may not all be protected and used as configured"
backplane.nics = _bp.nic_map
function backplane.init(config, __shared_memory)
_bp.smem      = __shared_memory
_bp.wlan_pref = config.PreferWireless
_bp.lan_iface = config.WiredModem
local plc_dev   = __shared_memory.plc_dev
local plc_state = __shared_memory.plc_state
plc_state.degraded = false
if _bp.smem.networked then
if type(_bp.lan_iface) == "string" then
local modem  = ppm.get_modem(_bp.lan_iface)
local wd_nic = network.nic(modem, config.SVR_Channel)
log.info("BKPLN: WIRED PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)
_bp.wd_nic  = wd_nic
_bp.act_nic = wd_nic
_bp.nic_map[_bp.lan_iface] = wd_nic
wd_nic.closeAll()
wd_nic.open(config.PLC_Channel)
plc_state.wd_modem = wd_nic.is_connected()
end
if config.WirelessModem then
local modem, iface = ppm.get_wireless_modem()
local wl_nic       = network.nic(modem, config.SVR_Channel)
log.info("BKPLN: WIRELESS PHY_" .. util.trinary(modem, "UP ", "DOWN") .. (iface or ""))
if (modem and _bp.wlan_pref) or not (_bp.act_nic and _bp.act_nic.is_connected()) then
_bp.act_nic = wl_nic
log.info("BKPLN: switched active to preferred wireless")
end
_bp.wl_nic = wl_nic
if iface then _bp.nic_map[iface] = wl_nic end
wl_nic.closeAll()
wl_nic.open(config.PLC_Channel)
plc_state.wl_modem = wl_nic.is_connected()
end
if not (plc_state.wd_modem or plc_state.wl_modem) then
println("startup> no comms modem found")
log.warning("BKPLN: no comms modem on startup")
plc_state.degraded = true
end
end
plc_dev.reactor      = ppm.get_fission_reactor()
plc_state.no_reactor = plc_dev.reactor == nil
if plc_state.no_reactor then
log.info("BKPLN: REACTOR LINK_DOWN")
println("startup> fission reactor not found")
log.warning("BKPLN: no reactor on startup")
plc_state.degraded = true
plc_state.reactor_formed = false
local _, dev = ppm.mount_virtual()
plc_dev.reactor = dev
log.info("BKPLN: mounted virtual device as reactor")
else
log.info("BKPLN: REACTOR LINK_UP " .. ppm.get_iface(plc_dev.reactor))
if not plc_dev.reactor.isFormed() then
println("startup> fission reactor is not formed")
log.warning("BKPLN: reactor logic adapter detected, but reactor is not formed")
plc_state.degraded = true
plc_state.reactor_formed = false
end
end
if #ppm.get_all_devices("fissionReactorLogicAdapter") > 1 then
println("startup> !! DANGER !! more than one reactor was detected! do not share reactor connections between multiple PLCs! they may not all be protected and used as configured")
log.warning("BKPLN: !! DANGER !! more than one reactor was detected on startup!")
log.warning(multi_reactor_warn)
databus.tx_multi_reactor(true)
end
end
function backplane.active_nic() return _bp.act_nic end
function backplane.standby_nic() return util.trinary(_bp.act_nic == _bp.wl_nic, _bp.wd_nic, _bp.wl_nic) end
function backplane.periodic()
if _bp.wd_nic then databus.tx_wd_net(_bp.wd_nic.periodic()) end
if _bp.wl_nic then databus.tx_wl_net(_bp.wl_nic.periodic()) end
end
function backplane.attach(iface, type, device, print_no_fp)
local MQ__RPS_CMD = _bp.smem.q_types.MQ__RPS_CMD
local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic
local networked = _bp.smem.networked
local state     = _bp.smem.plc_state
local dev       = _bp.smem.plc_dev
local sys       = _bp.smem.plc_sys
if type ~= nil and device ~= nil then
if type == "fissionReactorLogicAdapter" then
if not state.no_reactor then
log.warning("BKPLN: !! DANGER !! an additional reactor (" .. iface .. ") was connected and will not be used!")
log.warning(multi_reactor_warn)
databus.tx_multi_reactor(true)
return
end
log.info("BKPLN: REACTOR LINK_UP " .. iface)
dev.reactor = device
state.no_reactor = false
print_no_fp("reactor connected")
log.info("BKPLN: reactor connected")
state.reactor_formed = true
if ((not networked) or (state.wd_modem or state.wl_modem)) and state.reactor_formed then
state.degraded = false
end
sys.rps.reconnect_reactor(dev.reactor)
if networked then
sys.plc_comms.reconnect_reactor(dev.reactor)
end
_bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.RESET_REATTACH)
elseif networked and type == "modem" then
local m_is_wl = device.isWireless()
log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_ATTACH ", iface))
if wd_nic and (_bp.lan_iface == iface) then
wd_nic.connect(device)
_bp.nic_map[iface] = wd_nic
log.info("BKPLN: WIRED PHY_UP " .. iface)
print_no_fp("wired comms modem connected")
state.wd_modem = true
if (_bp.act_nic ~= wd_nic) and not _bp.wlan_pref then
_bp.act_nic = wd_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: switched comms to wired modem (preferred)")
end
elseif wl_nic and (not wl_nic.is_connected()) and m_is_wl then
wl_nic.connect(device)
_bp.nic_map[iface] = wl_nic
log.info("BKPLN: WIRELESS PHY_UP " .. iface)
print_no_fp("wireless comms modem connected")
state.wl_modem = true
if (_bp.act_nic ~= wl_nic) and _bp.wlan_pref then
_bp.act_nic = wl_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: switched comms to wireless modem (preferred)")
end
elseif wl_nic and m_is_wl then
device.closeAll()
print_no_fp("standby wireless modem connected")
log.info("BKPLN: standby wireless modem connected")
else
device.closeAll()
print_no_fp("unassigned modem connected")
log.warning("BKPLN: unassigned modem connected")
end
if (state.wd_modem or state.wl_modem) and state.reactor_formed and not state.no_reactor then
state.degraded = false
end
end
end
end
function backplane.detach(iface, type, device, print_no_fp)
local MQ__RPS_CMD = _bp.smem.q_types.MQ__RPS_CMD
local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic
local state = _bp.smem.plc_state
local dev   = _bp.smem.plc_dev
local sys   = _bp.smem.plc_sys
if type == "fissionReactorLogicAdapter" then
log.info("BKPLN: REACTOR LINK_DOWN " .. iface)
if #ppm.get_all_devices("fissionReactorLogicAdapter") > 1 then
log.warning("BKPLN: !! DANGER !! more than one reactor is still present!")
log.warning(multi_reactor_warn)
databus.tx_multi_reactor(true)
else databus.tx_multi_reactor(false) end
if device == dev.reactor then
print_no_fp("reactor disconnected")
log.warning("BKPLN: reactor disconnected")
state.no_reactor = true
state.degraded = true
local reactor, r_iface = ppm.get_fission_reactor()
if reactor and r_iface then
log.info("BKPLN: found another fission reactor logic adapter")
backplane.attach(r_iface, type, reactor, print_no_fp)
end
end
elseif _bp.smem.networked and type == "modem" then
log.info(util.c("BKPLN: PHY_DETACH ", iface))
_bp.nic_map[iface] = nil
if wd_nic and wd_nic.is_modem(device) then
wd_nic.disconnect()
log.info("BKPLN: WIRED PHY_DOWN " .. iface)
state.wd_modem = false
elseif wl_nic and wl_nic.is_modem(device) then
wl_nic.disconnect()
log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)
state.wl_modem = false
end
if _bp.act_nic.is_modem(device) then
print_no_fp("active comms modem disconnected")
log.warning("BKPLN: active comms modem disconnected")
if _bp.act_nic == wl_nic then
local modem, m_iface = ppm.get_wireless_modem()
if wl_nic and modem then
log.info("BKPLN: found another wireless modem, using it for comms")
wl_nic.connect(modem)
log.info("BKPLN: WIRELESS PHY_UP " .. m_iface)
state.wl_modem = true
elseif wd_nic and wd_nic.is_connected() then
_bp.act_nic = wd_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: switched comms to wired modem")
else
state.degraded = true
_bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.DEGRADED_SCRAM)
end
elseif wl_nic and wl_nic.is_connected() then
_bp.act_nic = wl_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: switched comms to wireless modem")
else
state.degraded = true
_bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.DEGRADED_SCRAM)
end
elseif wd_nic and wd_nic.is_modem(device) then
print_no_fp("standby wired modem disconnected")
log.info("BKPLN: standby wired modem disconnected")
elseif wl_nic and wl_nic.is_modem(device) then
print_no_fp("standby wireless modem disconnected")
log.info("BKPLN: standby wireless modem disconnected")
else
print_no_fp("unassigned modem disconnected")
log.warning("BKPLN: unassigned modem disconnected")
end
end
end
return backplane
