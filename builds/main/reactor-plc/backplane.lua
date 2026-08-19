
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
local multi_reactor_warn = "BKPLN: 请勿在多个 PLC 之间共享反应堆连接！它们可能无法全部按配置受到保护和正常使用"
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
log.info("BKPLN: 有线 PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)
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
log.info("BKPLN: 无线 PHY_" .. util.trinary(modem, "UP ", "DOWN") .. (iface or ""))
if (modem and _bp.wlan_pref) or not (_bp.act_nic and _bp.act_nic.is_connected()) then
_bp.act_nic = wl_nic
log.info("BKPLN: 已切换到优先无线")
end
_bp.wl_nic = wl_nic
if iface then _bp.nic_map[iface] = wl_nic end
wl_nic.closeAll()
wl_nic.open(config.PLC_Channel)
plc_state.wl_modem = wl_nic.is_connected()
end
if not (plc_state.wd_modem or plc_state.wl_modem) then
println("startup> 未找到通信调制解调器")
log.warning("BKPLN: 启动时没有通信调制解调器")
plc_state.degraded = true
end
end
plc_dev.reactor      = ppm.get_fission_reactor()
plc_state.no_reactor = plc_dev.reactor == nil
if plc_state.no_reactor then
log.info("BKPLN: REACTOR LINK_DOWN")
println("startup> 未找到裂变反应堆")
log.warning("BKPLN: 启动时没有反应堆")
plc_state.degraded = true
plc_state.reactor_formed = false
local _, dev = ppm.mount_virtual()
plc_dev.reactor = dev
log.info("BKPLN: 已将虚拟设备挂载为反应堆")
else
log.info("BKPLN: REACTOR LINK_UP " .. ppm.get_iface(plc_dev.reactor))
if not plc_dev.reactor.isFormed() then
println("startup> 裂变反应堆未成型")
log.warning("BKPLN: 检测到反应堆逻辑适配器，但反应堆未成型")
plc_state.degraded = true
plc_state.reactor_formed = false
end
end
if #ppm.get_all_devices("fissionReactorLogicAdapter") > 1 then
println("startup> !! 危险 !! 检测到多个反应堆！请勿在多个 PLC 之间共享反应堆连接！它们可能无法全部按配置受到保护和正常使用")
log.warning("BKPLN: !! 危险 !! 启动时检测到多个反应堆！")
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
log.warning("BKPLN: !! 危险 !! 检测到额外的反应堆（" .. iface .. "）已连接，将不会使用它！")
log.warning(multi_reactor_warn)
databus.tx_multi_reactor(true)
return
end
log.info("BKPLN: REACTOR LINK_UP " .. iface)
dev.reactor = device
state.no_reactor = false
print_no_fp("反应堆已连接")
log.info("BKPLN: 反应堆已连接")
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
log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "无线", "有线"), " PHY_ATTACH ", iface))
if wd_nic and (_bp.lan_iface == iface) then
wd_nic.connect(device)
_bp.nic_map[iface] = wd_nic
log.info("BKPLN: 有线 PHY_UP " .. iface)
print_no_fp("有线通信调制解调器已连接")
state.wd_modem = true
if (_bp.act_nic ~= wd_nic) and not _bp.wlan_pref then
_bp.act_nic = wd_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: 已将通信切换到有线调制解调器（优先）")
end
elseif wl_nic and (not wl_nic.is_connected()) and m_is_wl then
wl_nic.connect(device)
_bp.nic_map[iface] = wl_nic
log.info("BKPLN: 无线 PHY_UP " .. iface)
print_no_fp("无线通信调制解调器已连接")
state.wl_modem = true
if (_bp.act_nic ~= wl_nic) and _bp.wlan_pref then
_bp.act_nic = wl_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: 已将通信切换到无线调制解调器（优先）")
end
elseif wl_nic and m_is_wl then
device.closeAll()
print_no_fp("备用无线调制解调器已连接")
log.info("BKPLN: 备用无线调制解调器已连接")
else
device.closeAll()
print_no_fp("未分配调制解调器已连接")
log.warning("BKPLN: 未分配调制解调器已连接")
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
log.warning("BKPLN: !! 危险 !! 仍有多个反应堆！")
log.warning(multi_reactor_warn)
databus.tx_multi_reactor(true)
else databus.tx_multi_reactor(false) end
if device == dev.reactor then
print_no_fp("反应堆已断开")
log.warning("BKPLN: 反应堆已断开")
state.no_reactor = true
state.degraded = true
local reactor, r_iface = ppm.get_fission_reactor()
if reactor and r_iface then
log.info("BKPLN: 找到另一个裂变反应堆逻辑适配器")
backplane.attach(r_iface, type, reactor, print_no_fp)
end
end
elseif _bp.smem.networked and type == "modem" then
log.info(util.c("BKPLN: PHY_DETACH ", iface))
_bp.nic_map[iface] = nil
if wd_nic and wd_nic.is_modem(device) then
wd_nic.disconnect()
log.info("BKPLN: 有线 PHY_DOWN " .. iface)
state.wd_modem = false
elseif wl_nic and wl_nic.is_modem(device) then
wl_nic.disconnect()
log.info("BKPLN: 无线 PHY_DOWN " .. iface)
state.wl_modem = false
end
if _bp.act_nic.is_modem(device) then
print_no_fp("活动通信调制解调器已断开")
log.warning("BKPLN: 活动通信调制解调器已断开")
if _bp.act_nic == wl_nic then
local modem, m_iface = ppm.get_wireless_modem()
if wl_nic and modem then
log.info("BKPLN: 找到另一个无线调制解调器，正在将其用于通信")
wl_nic.connect(modem)
log.info("BKPLN: 无线 PHY_UP " .. m_iface)
state.wl_modem = true
elseif wd_nic and wd_nic.is_connected() then
_bp.act_nic = wd_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: 已将通信切换到有线调制解调器")
else
state.degraded = true
_bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.DEGRADED_SCRAM)
end
elseif wl_nic and wl_nic.is_connected() then
_bp.act_nic = wl_nic
sys.plc_comms.switch_nic(_bp.act_nic)
log.info("BKPLN: 已将通信切换到无线调制解调器")
else
state.degraded = true
_bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.DEGRADED_SCRAM)
end
elseif wd_nic and wd_nic.is_modem(device) then
print_no_fp("备用有线调制解调器已断开")
log.info("BKPLN: 备用有线调制解调器已断开")
elseif wl_nic and wl_nic.is_modem(device) then
print_no_fp("备用无线调制解调器已断开")
log.info("BKPLN: 备用无线调制解调器已断开")
else
print_no_fp("未分配调制解调器已断开")
log.warning("BKPLN: 未分配调制解调器已断开")
end
end
end
return backplane
