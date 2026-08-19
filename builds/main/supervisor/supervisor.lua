local comms      = require("scada-common.comms")
local constants  = require("scada-common.constants")
local log        = require("scada-common.log")
local types      = require("scada-common.types")
local util       = require("scada-common.util")
local themes     = require("graphics.themes")
local backplane  = require("supervisor.backplane")
local svsessions = require("supervisor.session.svsessions")
local supervisor = {}
local PROTOCOL      = comms.PROTOCOL
local DEVICE_TYPE   = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE     = comms.MGMT_TYPE
local LISTEN_MODE   = types.LISTEN_MODE
local config = {}
supervisor.config = config
supervisor.boot_state = nil
function supervisor.load_config()
if not settings.load("/supervisor.settings") then return false end
local boot_state = {
mode = settings.get("LastProcessState"),
unit_states = settings.get("LastUnitStates")
}
if type(boot_state.mode) == "number" and type(boot_state.unit_states) == "table" then
supervisor.boot_state = boot_state
end
config.UnitCount = settings.get("UnitCount")
config.CoolingConfig = settings.get("CoolingConfig")
config.FacilityTankMode = settings.get("FacilityTankMode")
config.FacilityTankDefs = settings.get("FacilityTankDefs")
config.FacilityTankList = settings.get("FacilityTankList")
config.FacilityTankConns = settings.get("FacilityTankConns")
config.TankFluidTypes = settings.get("TankFluidTypes")
config.AuxiliaryCoolant = settings.get("AuxiliaryCoolant")
config.ExtChargeIdling = settings.get("ExtChargeIdling")
config.UseSNAStatistics = settings.get("UseSNAStatistics")
config.CombinedWaste = settings.get("CombinedWaste")
config.EnergyStorageSystem = settings.get("EnergyStorageSystem")
config.MekanismConfig = settings.get("MekanismConfig")
config.MekanismWasteToPu = settings.get("MekanismWasteToPu")
config.MekanismWasteToPo = settings.get("MekanismWasteToPo")
config.WirelessModem = settings.get("WirelessModem")
config.WiredModem = settings.get("WiredModem")
config.PLC_Listen = settings.get("PLC_Listen")
config.RTU_Listen = settings.get("RTU_Listen")
config.CRD_Listen = settings.get("CRD_Listen")
config.PocketEnabled = settings.get("PocketEnabled")
config.PocketTest = settings.get("PocketTest")
config.SVR_Channel = settings.get("SVR_Channel")
config.PLC_Channel = settings.get("PLC_Channel")
config.RTU_Channel = settings.get("RTU_Channel")
config.CRD_Channel = settings.get("CRD_Channel")
config.PKT_Channel = settings.get("PKT_Channel")
config.PLC_Timeout = settings.get("PLC_Timeout")
config.RTU_Timeout = settings.get("RTU_Timeout")
config.CRD_Timeout = settings.get("CRD_Timeout")
config.PKT_Timeout = settings.get("PKT_Timeout")
config.TrustedRange = settings.get("TrustedRange")
config.AuthKey = settings.get("AuthKey")
config.LogMode = settings.get("LogMode")
config.LogPath = settings.get("LogPath")
config.LogDebug = settings.get("LogDebug")
config.FrontPanelTheme = settings.get("FrontPanelTheme")
config.ColorMode = settings.get("ColorMode")
local cfv = util.new_validator()
cfv.assert_type_int(config.UnitCount)
cfv.assert_range(config.UnitCount, 1, 4)
cfv.assert_type_table(config.CoolingConfig)
cfv.assert_type_int(config.FacilityTankMode)
cfv.assert_type_table(config.FacilityTankDefs)
cfv.assert_type_table(config.FacilityTankList)
cfv.assert_type_table(config.FacilityTankConns)
cfv.assert_type_table(config.TankFluidTypes)
cfv.assert_type_table(config.AuxiliaryCoolant)
cfv.assert_type_bool(config.ExtChargeIdling)
cfv.assert_type_bool(config.UseSNAStatistics)
cfv.assert_type_bool(config.CombinedWaste)
cfv.assert_type_int(config.EnergyStorageSystem)
if cfv.valid() then
cfv.assert_range(config.FacilityTankMode, 0, 8)
cfv.assert_range(config.EnergyStorageSystem, types.ESS.INDUCTION_MATRIX, types.ESS.ENERGY_CORE)
end
cfv.assert_type_table(config.MekanismConfig)
if cfv.valid() then
cfv.assert_type_num(config.MekanismConfig.energyPerFissionFuel)
cfv.assert_type_num(config.MekanismConfig.turbineDisperserChemicalFlow)
cfv.assert_type_num(config.MekanismConfig.turbineVentChemicalFlow)
cfv.assert_type_num(config.MekanismConfig.turbineChemicalPerTank)
end
cfv.assert_type_table(config.MekanismWasteToPu)
cfv.assert_type_table(config.MekanismWasteToPo)
if cfv.valid() then
cfv.assert_type_int(config.MekanismWasteToPu[1])
cfv.assert_type_int(config.MekanismWasteToPu[2])
cfv.assert_type_int(config.MekanismWasteToPo[1])
cfv.assert_type_int(config.MekanismWasteToPo[2])
if cfv.valid() then
cfv.assert_min(config.MekanismWasteToPu[1], 1)
cfv.assert_min(config.MekanismWasteToPu[2], 1)
cfv.assert_min(config.MekanismWasteToPo[1], 1)
cfv.assert_min(config.MekanismWasteToPo[2], 1)
end
end
cfv.assert_type_bool(config.WirelessModem)
cfv.assert((config.WiredModem == false) or (type(config.WiredModem) == "string"))
cfv.assert((config.WirelessModem == true) or (type(config.WiredModem) == "string"))
cfv.assert_type_int(config.PLC_Listen)
cfv.assert_range(config.PLC_Listen, 1, 3)
cfv.assert_type_int(config.RTU_Listen)
cfv.assert_range(config.RTU_Listen, 1, 3)
cfv.assert_type_int(config.CRD_Listen)
cfv.assert_range(config.CRD_Listen, 1, 3)
cfv.assert_type_bool(config.PocketEnabled)
cfv.assert_type_bool(config.PocketTest)
cfv.assert_channel(config.SVR_Channel)
cfv.assert_channel(config.PLC_Channel)
cfv.assert_channel(config.RTU_Channel)
cfv.assert_channel(config.CRD_Channel)
cfv.assert_channel(config.PKT_Channel)
cfv.assert_type_num(config.PLC_Timeout)
cfv.assert_min(config.PLC_Timeout, 2)
cfv.assert_type_num(config.RTU_Timeout)
cfv.assert_min(config.RTU_Timeout, 2)
cfv.assert_type_num(config.CRD_Timeout)
cfv.assert_min(config.CRD_Timeout, 2)
cfv.assert_type_num(config.PKT_Timeout)
cfv.assert_min(config.PKT_Timeout, 2)
cfv.assert_type_num(config.TrustedRange)
cfv.assert_min(config.TrustedRange, 0)
if type(config.AuthKey) == "string" then
local len = string.len(config.AuthKey)
cfv.assert(len == 0 or len >= 8)
end
cfv.assert_type_int(config.LogMode)
cfv.assert_range(config.LogMode, 0, 1)
cfv.assert_type_str(config.LogPath)
cfv.assert_type_bool(config.LogDebug)
cfv.assert_type_int(config.FrontPanelTheme)
cfv.assert_range(config.FrontPanelTheme, 1, 2)
cfv.assert_type_int(config.ColorMode)
cfv.assert_range(config.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)
if cfv.valid() then
constants.mek.JOULES_PER_MB          = config.MekanismConfig.energyPerFissionFuel
constants.mek.TURBINE_DISPERSER_FLOW = config.MekanismConfig.turbineDisperserChemicalFlow
constants.mek.TURBINE_VENT_FLOW      = config.MekanismConfig.turbineVentChemicalFlow
constants.mek.TURBINE_GAS_PER_TANK   = config.MekanismConfig.turbineChemicalPerTank
end
return cfv.valid()
end
function supervisor.comms(_version, fp_ok, facility)
local function println(message) if not fp_ok then util.println_ts(message) end end
local self = {
last_est_acks = {}
}
if config.WirelessModem then
comms.set_trusted_range(config.TrustedRange)
end
svsessions.init(fp_ok, config, facility)
local function _send_establish(nic, rx_frame, ack, data)
local tx_frame, mgmt = comms.scada_frame(), comms.mgmt_container()
mgmt.make(MGMT_TYPE.ESTABLISH, { ack, data })
tx_frame.make(rx_frame.src_addr(), rx_frame.seq_num() + 1, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
nic.transmit(rx_frame.remote_channel(), config.SVR_Channel, tx_frame)
self.last_est_acks[rx_frame.src_addr()] = ack
end
local function _establish_plc(nic, packet, src_addr, i_seq_num, last_ack)
local comms_v    = packet.data[1]
local firmware_v = packet.data[2]
local dev_type   = packet.data[3]
if (config.PLC_Listen ~= LISTEN_MODE.ALL) and (nic.isWireless() ~= (config.PLC_Listen == LISTEN_MODE.WIRELESS)) and periphemu == nil then
elseif comms_v ~= comms.version then
if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
log.info(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] 丢弃通信版本不正确的 PLC 建立数据包 v", comms_v, "（期望 v", comms.version, "）"))
end
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
elseif dev_type == DEVICE_TYPE.PLC then
if packet.length == 4 and type(packet.data[4]) == "number" then
local reactor_id = packet.data[4]
if reactor_id < 1 or reactor_id > config.UnitCount then
if last_ack ~= ESTABLISH_ACK.DENY then
log.warning(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] 拒绝分配 ", reactor_id, "（超出已配置机组数量 ", config.UnitCount, "）"))
end
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
else
local plc_id = svsessions.establish_plc_session(nic, src_addr, i_seq_num, reactor_id, firmware_v)
if plc_id == false then
if last_ack ~= ESTABLISH_ACK.COLLISION then
log.warning(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] 与反应堆 ", reactor_id, " 的分配冲突"))
end
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.COLLISION)
elseif plc_id == true then
log.info(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] 在 ", nic.phy_name(), " 上发送连接测试成功响应"))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
else
println(util.c("PLC (", firmware_v, ") [@", src_addr, "] \xbb 反应堆 ", reactor_id, " 已连接"))
log.info(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] (", firmware_v, ") 反应堆机组 ", reactor_id, " 的 PLC 已连接，会话 ID ", plc_id, "，位于 ", nic.phy_name()))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
end
end
else
log.debug("PLC_ESTABLISH: [@" .. src_addr .. "] 数据包长度不匹配/参数类型错误")
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
else
log.debug(util.c("PLC_ESTABLISH: [@", src_addr, "] PLC 通道上设备 ", dev_type, " 的建立数据包非法"))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
end
local function _establish_rtu_gw(nic, packet, src_addr, i_seq_num, last_ack)
local comms_v    = packet.data[1]
local firmware_v = packet.data[2]
local dev_type   = packet.data[3]
if (config.RTU_Listen ~= LISTEN_MODE.ALL) and (nic.isWireless() ~= (config.RTU_Listen == LISTEN_MODE.WIRELESS)) and periphemu == nil then
elseif comms_v ~= comms.version then
if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
log.info(util.c("RTU_GW_ESTABLISH: [@", src_addr, "] 丢弃通信版本不正确的 RTU_GW 建立数据包 v", comms_v, "（期望 v", comms.version, "）"))
end
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
elseif dev_type == DEVICE_TYPE.RTU then
if packet.length == 4 then
if firmware_v ~= comms.CONN_TEST_FWV then
local rtu_advert = packet.data[4]
local s_id = svsessions.establish_rtu_session(nic, src_addr, i_seq_num, rtu_advert, firmware_v)
println(util.c("RTU (", firmware_v, ") [@", src_addr, "] \xbb 已连接"))
log.info(util.c("RTU_GW_ESTABLISH: [@", src_addr, "] RTU_GW (",firmware_v, ") 已连接，会话 ID ", s_id, "，位于 ", nic.phy_name()))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
else
log.info(util.c("RTU_GW_ESTABLISH: RTU_GW [@", src_addr, "] 在 ", nic.phy_name(), " 上发送连接测试成功响应"))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
end
else
log.debug("RTU_GW_ESTABLISH: [@" .. src_addr .. "] 数据包长度不匹配")
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
else
log.debug(util.c("RTU_GW_ESTABLISH: [@", src_addr, "] RTU 通道上设备 ", dev_type, " 的建立数据包非法"))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
end
local function _establish_crd(nic, packet, src_addr, i_seq_num, last_ack)
local comms_v    = packet.data[1]
local firmware_v = packet.data[2]
local dev_type   = packet.data[3]
if (config.CRD_Listen ~= LISTEN_MODE.ALL) and (nic.isWireless() ~= (config.CRD_Listen == LISTEN_MODE.WIRELESS)) and periphemu == nil then
elseif comms_v ~= comms.version then
if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
log.info(util.c("CRD_ESTABLISH: [@", src_addr, "] 丢弃通信版本不正确的协调器建立数据包 v", comms_v, "（期望 v", comms.version, "）"))
end
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
elseif dev_type == DEVICE_TYPE.CRD then
local s_id = svsessions.establish_crd_session(nic, src_addr, i_seq_num, firmware_v)
if s_id ~= false then
println(util.c("CRD (", firmware_v, ") [@", src_addr, "] \xbb 已连接"))
log.info(util.c("CRD_ESTABLISH: [@", src_addr, "] CRD (", firmware_v, ") 已连接，会话 ID ", s_id, "，位于 ", nic.phy_name()))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW, { config.UnitCount, facility.get_cooling_conf(), { config.MekanismWasteToPu, config.MekanismWasteToPo }, config.CombinedWaste, config.EnergyStorageSystem })
else
if last_ack ~= ESTABLISH_ACK.COLLISION then
log.info("CRD_ESTABLISH: [@" .. src_addr .. "] 因已连接到另一协调器而拒绝新协调器")
end
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.COLLISION)
end
else
log.debug(util.c("CRD_ESTABLISH: [@", src_addr, "] CRD 通道上设备 ", dev_type, " 的建立数据包非法"))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
end
local function _establish_pdg(nic, packet, src_addr, i_seq_num, last_ack)
local comms_v    = packet.data[1]
local firmware_v = packet.data[2]
local dev_type   = packet.data[3]
if not config.PocketEnabled then
elseif comms_v ~= comms.version then
if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
log.info(util.c("PDG_ESTABLISH: [@", src_addr, "] 丢弃通信版本不正确的 PKT 建立数据包 v", comms_v, "（期望 v", comms.version, "）"))
end
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
elseif dev_type == DEVICE_TYPE.PKT then
local s_id = svsessions.establish_pdg_session(nic, src_addr, i_seq_num, firmware_v)
println(util.c("PKT (", firmware_v, ") [@", src_addr, "] \xbb 已连接"))
log.info(util.c("PDG_ESTABLISH: [@", src_addr, "] 口袋设备 (", firmware_v, ") 已连接，会话 ID ", s_id, "，位于 ", nic.phy_name()))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
else
log.debug(util.c("PDG_ESTABLISH: [@", src_addr, "] PKT 通道上设备 ", dev_type, " 的建立数据包非法"))
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
end
local public = {}
function public.parse_packet(side, sender, reply_to, message, distance)
local pkt, nic = nil, backplane.nics[side]
if nic then
local frame = nic.receive(side, sender, reply_to, message, distance)
if frame then
if frame.protocol() == PROTOCOL.MODBUS_TCP then
pkt = comms.modbus_container().decode(frame)
elseif frame.protocol() == PROTOCOL.RPLC then
pkt = comms.rplc_container().decode(frame)
elseif frame.protocol() == PROTOCOL.SCADA_MGMT then
pkt = comms.mgmt_container().decode(frame)
elseif frame.protocol() == PROTOCOL.SCADA_CRDN then
pkt = comms.crdn_container().decode(frame)
else
log.debug("parse_packet(" .. side .. "): 尝试解析非法数据包类型 " .. frame.protocol(), true)
end
end
else
log.error("parse_packet(" .. side .. "): 从无网卡的接口收到数据包？")
end
return pkt
end
function public.handle_packet(packet)
local nic       = backplane.nics[packet.scada_frame.interface()]
local l_chan    = packet.scada_frame.local_channel()
local r_chan    = packet.scada_frame.remote_channel()
local src_addr  = packet.scada_frame.src_addr()
local protocol  = packet.scada_frame.protocol()
local i_seq_num = packet.scada_frame.seq_num()
if l_chan ~= config.SVR_Channel then
log.debug("在未配置的信道上接收到数据包 " .. l_chan, true)
elseif r_chan == config.PLC_Channel then
local session = svsessions.find_plc_session(src_addr)
if session then
if nic ~= session.nic then
if (protocol == PROTOCOL.SCADA_MGMT) and (packet.type == MGMT_TYPE.SWITCH_NET) then
session.nic = nic
session.in_queue.push_network(packet)
log.info(util.c("将会话 ", session, " 切换到 ", nic.phy_name()))
else
log.debug(util.c("在 ", nic.phy_name(), " 上接收到来自 PLC @ ", src_addr, " 的意外数据包"))
end
else
session.in_queue.push_network(packet)
end
elseif protocol == PROTOCOL.RPLC then
log.debug("丢弃无已知会话的 RPLC 数据包")
elseif protocol == PROTOCOL.SCADA_MGMT then
if packet.type == MGMT_TYPE.ESTABLISH then
if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
_establish_plc(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
else
log.debug("无效的建立数据包（PLC 通道）")
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
else
log.debug(util.c("丢弃来自计算机 ", src_addr, " 的无已知会话的 PLC SCADA_MGMT 数据包"))
end
else
log.debug(util.c("PLC 通道上的非法数据包类型 ", protocol))
end
elseif r_chan == config.RTU_Channel then
local session = svsessions.find_rtu_session(src_addr)
if session then
if nic ~= session.nic then
if (protocol == PROTOCOL.SCADA_MGMT) and (packet.type == MGMT_TYPE.SWITCH_NET) then
session.nic = nic
session.in_queue.push_network(packet)
log.info(util.c("将会话 ", session, " 切换到 ", nic.phy_name()))
else
log.debug(util.c("在 ", nic.phy_name(), " 上接收到来自 RTU_GW @ ", src_addr, " 的意外数据包"))
end
else
session.in_queue.push_network(packet)
end
elseif protocol == PROTOCOL.MODBUS_TCP then
log.debug("丢弃无已知会话的 MODBUS_TCP 数据包")
elseif protocol == PROTOCOL.SCADA_MGMT then
if packet.type == MGMT_TYPE.ESTABLISH then
if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
_establish_rtu_gw(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
else
log.debug("无效的建立数据包（RTU 通道）")
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
else
log.debug(util.c("丢弃来自计算机 ", src_addr, " 的无已知会话的 RTU 网关 SCADA_MGMT 数据包"))
end
else
log.debug(util.c("RTU 通道上的非法数据包类型 ", protocol))
end
elseif r_chan == config.CRD_Channel then
local session = svsessions.find_crd_session(src_addr)
if session then
if nic ~= session.nic then
if (protocol == PROTOCOL.SCADA_MGMT) and (packet.type == MGMT_TYPE.SWITCH_NET) then
session.nic = nic
session.in_queue.push_network(packet)
log.info(util.c("将会话 ", session, " 切换到 ", nic.phy_name()))
else
log.debug(util.c("在 ", nic.phy_name(), " 上接收到来自 CRD @ ", src_addr, " 的意外数据包"))
end
else
session.in_queue.push_network(packet)
end
elseif protocol == PROTOCOL.SCADA_MGMT then
if packet.type == MGMT_TYPE.ESTABLISH then
if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
_establish_crd(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
else
log.debug("CRD_ESTABLISH: 建立数据包长度不匹配")
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
else
log.debug(util.c("丢弃来自计算机 ", src_addr, " 的无已知会话的协调器 SCADA_MGMT 数据包"))
end
elseif protocol == PROTOCOL.SCADA_CRDN then
log.debug(util.c("丢弃来自计算机 ", src_addr, " 的无已知会话的协调器 SCADA_CRDN 数据包"))
else
log.debug(util.c("CRD 通道上的非法数据包类型 ", protocol))
end
elseif r_chan == config.PKT_Channel then
local session = svsessions.find_pdg_session(src_addr)
if session then
session.in_queue.push_network(packet)
elseif protocol == PROTOCOL.SCADA_MGMT then
if packet.type == MGMT_TYPE.ESTABLISH then
if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
_establish_pdg(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
else
log.debug("PDG_ESTABLISH: 建立数据包长度不匹配")
_send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
end
else
log.debug(util.c("丢弃来自计算机 ", src_addr, " 的无已知会话的口袋设备 SCADA_MGMT 数据包"))
end
elseif protocol == PROTOCOL.SCADA_CRDN then
log.debug(util.c("丢弃来自计算机 ", src_addr, " 的无已知会话的口袋设备 SCADA_CRDN 数据包"))
else
log.debug(util.c("口袋通道上的非法数据包类型 ", protocol))
end
else
log.debug("在未知信道上接收到数据包 " .. r_chan, true)
end
end
return public
end
return supervisor
