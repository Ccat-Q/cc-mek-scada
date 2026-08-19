
local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local util    = require("scada-common.util")
local databus = require("rtu.databus")
local rtu     = require("rtu.rtu")
local println = util.println
local backplane = {}
local _bp = {
smem = nil,
wlan_pref = true,
lan_iface = "",
act_nic = nil,
wd_nic = nil,
wl_nic = nil,
nic_map = {},
sounders = {}
}
backplane.nics = _bp.nic_map
function backplane.init(config, __shared_memory)
_bp.smem      = __shared_memory
_bp.wlan_pref = config.PreferWireless
_bp.lan_iface = config.WiredModem
if type(_bp.lan_iface) == "string" then
local modem  = ppm.get_modem(_bp.lan_iface)
local wd_nic = network.nic(modem, config.SVR_Channel)
log.info("BKPLN: WIRED PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)
_bp.wd_nic  = wd_nic
_bp.act_nic = wd_nic
_bp.nic_map[_bp.lan_iface] = wd_nic
wd_nic.closeAll()
wd_nic.open(config.RTU_Channel)
databus.tx_hw_wd_modem(modem ~= nil)
end
if config.WirelessModem then
local modem, iface = ppm.get_wireless_modem()
local wl_nic       = network.nic(modem, config.SVR_Channel)
log.info("BKPLN: WIRELESS PHY_" .. util.trinary(modem, "UP ", "DOWN") .. (iface or ""))
if (modem and _bp.wlan_pref) or not (_bp.act_nic and _bp.act_nic.is_connected()) then
_bp.act_nic = wl_nic
end
_bp.wl_nic = wl_nic
if iface then _bp.nic_map[iface] = wl_nic end
wl_nic.closeAll()
wl_nic.open(config.RTU_Channel)
databus.tx_hw_wl_modem(modem ~= nil)
end
if not ((_bp.wd_nic and _bp.wd_nic.is_connected()) or (_bp.wl_nic and _bp.wl_nic.is_connected())) then
println("startup> 未找到通讯调制解调器")
log.warning("BKPLN: 启动时未找到通讯调制解调器")
return false
end
local speakers = ppm.get_all_devices("speaker")
for _, s in pairs(speakers) do
log.info("BKPLN: SPEAKER LINK_UP " .. ppm.get_iface(s))
local sounder = rtu.init_sounder(s)
table.insert(_bp.sounders, sounder)
log.debug(util.c("BKPLN: added speaker sounder, attached as ", sounder.name))
end
databus.tx_hw_spkr_count(#_bp.sounders)
return true
end
function backplane.active_nic() return _bp.act_nic end
function backplane.standby_nic() return util.trinary(_bp.act_nic == _bp.wl_nic, _bp.wd_nic, _bp.wl_nic) end
function backplane.sounders() return _bp.sounders end
function backplane.periodic()
if _bp.wd_nic then databus.tx_wd_net(_bp.wd_nic.periodic()) end
if _bp.wl_nic then databus.tx_wl_net(_bp.wl_nic.periodic()) end
end
function backplane.attach(type, device, iface, print_no_fp)
local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic
local comms = _bp.smem.rtu_sys.rtu_comms
if type == "modem" then
local m_is_wl = device.isWireless()
log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_ATTACH ", iface))
if wd_nic and (_bp.lan_iface == iface) then
wd_nic.connect(device)
_bp.nic_map[iface] = wd_nic
log.info("BKPLN: WIRED PHY_UP " .. iface)
print_no_fp("有线通讯调制解调器已重连")
databus.tx_hw_wd_modem(true)
if (_bp.act_nic ~= wd_nic) and not _bp.wlan_pref then
_bp.act_nic = wd_nic
comms.switch_nic(_bp.act_nic, _bp.smem.rtu_state)
log.info("BKPLN: 通讯已切换到有线调制解调器（优先）")
end
elseif wl_nic and (not wl_nic.is_connected()) and m_is_wl then
wl_nic.connect(device)
_bp.nic_map[iface] = wl_nic
log.info("BKPLN: WIRELESS PHY_UP " .. iface)
print_no_fp("无线通讯调制解调器已重连")
databus.tx_hw_wl_modem(true)
if (_bp.act_nic ~= wl_nic) and _bp.wlan_pref then
_bp.act_nic = wl_nic
comms.switch_nic(_bp.act_nic, _bp.smem.rtu_state)
log.info("BKPLN: 通讯已切换到无线调制解调器（优先）")
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
elseif type == "speaker" then
log.info("BKPLN: SPEAKER LINK_UP " .. iface)
table.insert(_bp.sounders, rtu.init_sounder(device))
print_no_fp("音响已连接")
log.info("BKPLN: 已为音响 " .. iface .. " 设置音响发声器")
databus.tx_hw_spkr_count(#_bp.sounders)
end
end
function backplane.detach(type, device, iface, print_no_fp)
local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic
local comms = _bp.smem.rtu_sys.rtu_comms
if type == "modem" then
log.info(util.c("BKPLN: PHY_DETACH ", iface))
_bp.nic_map[iface] = nil
if wd_nic and wd_nic.is_modem(device) then
wd_nic.disconnect()
log.info("BKPLN: WIRED PHY_DOWN " .. iface)
databus.tx_hw_wd_modem(false)
elseif wl_nic and wl_nic.is_modem(device) then
wl_nic.disconnect()
log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)
databus.tx_hw_wl_modem(false)
end
if _bp.act_nic.is_modem(device) then
print_no_fp("活动通讯调制解调器已断开")
log.warning("BKPLN: 活动通讯调制解调器已断开")
if _bp.act_nic == wl_nic then
local modem, m_iface = ppm.get_wireless_modem()
if wl_nic and modem then
log.info("BKPLN: 找到另一个无线调制解调器，用于通讯")
wl_nic.connect(modem)
log.info("BKPLN: WIRELESS PHY_UP " .. m_iface)
databus.tx_hw_wl_modem(true)
elseif wd_nic and wd_nic.is_connected() then
_bp.act_nic = wd_nic
comms.switch_nic(_bp.act_nic, _bp.smem.rtu_state)
log.info("BKPLN: 通讯已切换到有线调制解调器")
else
comms.close(_bp.smem.rtu_state)
end
elseif wl_nic and wl_nic.is_connected() then
_bp.act_nic = wl_nic
comms.switch_nic(_bp.act_nic, _bp.smem.rtu_state)
log.info("BKPLN: 通讯已切换到无线调制解调器")
else
comms.close(_bp.smem.rtu_state)
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
elseif type == "speaker" then
log.info("BKPLN: SPEAKER LINK_DOWN " .. iface)
for i = 1, #_bp.sounders do
if _bp.sounders[i].speaker == device then
table.remove(_bp.sounders, i)
print_no_fp("音响已断开")
log.warning("BKPLN: 音响发声器 " .. iface .. " 已断开")
databus.tx_hw_spkr_count(#_bp.sounders)
break
end
end
end
end
return backplane
