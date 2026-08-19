local audio   = require("scada-common.audio")
local comms   = require("scada-common.comms")
local ppm     = require("scada-common.ppm")
local log     = require("scada-common.log")
local types   = require("scada-common.types")
local util    = require("scada-common.util")
local themes  = require("graphics.themes")
local databus = require("rtu.databus")
local modbus  = require("rtu.modbus")
local rtu = {}
local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local FAILOVER_GRACE_PERIOD_MS = 5000
local config = {}
rtu.config = config
function rtu.load_config()
if not settings.load("/rtu.settings") then return false end
config.Peripherals = settings.get("Peripherals")
config.Redstone = settings.get("Redstone")
config.SpeakerVolume = settings.get("SpeakerVolume")
config.WirelessModem = settings.get("WirelessModem")
config.WiredModem = settings.get("WiredModem")
config.PreferWireless = settings.get("PreferWireless")
config.SVR_Channel = settings.get("SVR_Channel")
config.RTU_Channel = settings.get("RTU_Channel")
config.ConnTimeout = settings.get("ConnTimeout")
config.TrustedRange = settings.get("TrustedRange")
config.AuthKey = settings.get("AuthKey")
config.LogMode = settings.get("LogMode")
config.LogPath = settings.get("LogPath")
config.LogDebug = settings.get("LogDebug")
config.FrontPanelTheme = settings.get("FrontPanelTheme")
config.ColorMode = settings.get("ColorMode")
return rtu.validate_config(config)
end
function rtu.validate_config(cfg)
local cfv = util.new_validator()
cfv.assert_type_num(cfg.SpeakerVolume)
cfv.assert_range(cfg.SpeakerVolume, 0, 3)
cfv.assert_type_bool(cfg.WirelessModem)
cfv.assert((cfg.WiredModem == false) or (type(cfg.WiredModem) == "string"))
cfv.assert(cfg.WirelessModem or (type(cfg.WiredModem) == "string"))
cfv.assert_type_bool(cfg.PreferWireless)
cfv.assert_channel(cfg.SVR_Channel)
cfv.assert_channel(cfg.RTU_Channel)
cfv.assert_type_num(cfg.ConnTimeout)
cfv.assert_min(cfg.ConnTimeout, 2)
cfv.assert_type_num(cfg.TrustedRange)
cfv.assert_min(cfg.TrustedRange, 0)
cfv.assert_type_str(cfg.AuthKey)
if type(cfg.AuthKey) == "string" then
local len = string.len(cfg.AuthKey)
cfv.assert(len == 0 or len >= 8)
end
cfv.assert_type_int(cfg.LogMode)
cfv.assert_range(cfg.LogMode, 0, 1)
cfv.assert_type_str(cfg.LogPath)
cfv.assert_type_bool(cfg.LogDebug)
cfv.assert_type_int(cfg.FrontPanelTheme)
cfv.assert_range(cfg.FrontPanelTheme, 1, 2)
cfv.assert_type_int(cfg.ColorMode)
cfv.assert_range(cfg.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)
cfv.assert_type_table(cfg.Peripherals)
cfv.assert_type_table(cfg.Redstone)
return cfv.valid()
end
function rtu.init_unit(device)
local self = {
discrete_inputs = {},
coils = {},
input_regs = {},
holding_regs = {},
io_count_cache = { 0, 0, 0, 0 }
}
local insert = table.insert
local stub = function () log.warning("tried to call an RTU function stub") end
local public = {}
local protected = {}
local function _is_faulted() return false end
if device then _is_faulted = device.__p_is_faulted end
local function _count_io()
self.io_count_cache = { #self.discrete_inputs, #self.coils, #self.input_regs, #self.holding_regs }
end
function public.io_count()
return self.io_count_cache[1], self.io_count_cache[2], self.io_count_cache[3], self.io_count_cache[4]
end
local function _as_func(f)
if type(f) == "string" then
local name = f
if device then
f = function (...) return device[name](...) end
else f = stub end
end
return f
end
function protected.connect_di(f)
insert(self.discrete_inputs, { read = _as_func(f) })
_count_io()
return #self.discrete_inputs
end
function public.read_di(di_addr)
local value = self.discrete_inputs[di_addr].read()
return value, _is_faulted()
end
function protected.connect_coil(f_read, f_write)
insert(self.coils, { read = _as_func(f_read), write = _as_func(f_write) })
_count_io()
return #self.coils
end
function public.read_coil(coil_addr)
local value = self.coils[coil_addr].read()
return value, _is_faulted()
end
function public.write_coil(coil_addr, value)
self.coils[coil_addr].write(value)
return _is_faulted()
end
function protected.connect_input_reg(f)
insert(self.input_regs, { read = _as_func(f) })
_count_io()
return #self.input_regs
end
function public.read_input_reg(reg_addr)
local value = self.input_regs[reg_addr].read()
return value, _is_faulted()
end
function protected.connect_holding_reg(f_read, f_write)
insert(self.holding_regs, { read = _as_func(f_read), write = _as_func(f_write) })
_count_io()
return #self.holding_regs
end
function public.read_holding_reg(reg_addr)
local value = self.holding_regs[reg_addr].read()
return value, _is_faulted()
end
function public.write_holding_reg(reg_addr, value)
self.holding_regs[reg_addr].write(value)
return _is_faulted()
end
function protected.interface() return public end
return protected
end
function rtu.init_sounder(speaker)
local spkr_ctl = {
speaker = speaker,
name = ppm.get_iface(speaker),
playing = false,
stream = audio.new_stream(),
play = function () end,
stop = function () end,
continue = function () end
}
function spkr_ctl.continue()
if spkr_ctl.playing then
if spkr_ctl.speaker ~= nil and spkr_ctl.stream.has_next_block() then
local success = spkr_ctl.speaker.playAudio(spkr_ctl.stream.get_next_block(), config.SpeakerVolume)
if not success then log.error(util.c("rtu_sounder(", spkr_ctl.name, "): error playing audio")) end
end
end
end
function spkr_ctl.play()
if not spkr_ctl.playing then
spkr_ctl.playing = true
return spkr_ctl.continue()
end
end
function spkr_ctl.stop()
spkr_ctl.playing = false
spkr_ctl.speaker.stop()
spkr_ctl.stream.stop()
end
return spkr_ctl
end
function rtu.comms(version, backplane, conn_watchdog)
local self = {
sv_addr = comms.BROADCAST,
seq_num = util.time_ms() * 10,
r_seq_num = nil,
txn_id = 0,
failover_init = 0,
last_est_ack = ESTABLISH_ACK.ALLOW
}
local insert = table.insert
local tx_nic = backplane.active_nic()
if config.WirelessModem then
comms.set_trusted_range(config.TrustedRange)
end
local function _send(msg_type, msg)
local frame, mgmt = comms.scada_frame(), comms.mgmt_container()
mgmt.make(msg_type, msg)
frame.make(self.sv_addr, self.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
tx_nic.transmit(config.SVR_Channel, config.RTU_Channel, frame)
self.seq_num = self.seq_num + 1
end
local function _send_keep_alive_ack(srv_time)
_send(MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
end
local function _generate_advertisement(units)
local advertisement = {}
for i = 1, #units do
local unit = units[i]
if unit.type ~= nil then
insert(advertisement, { unit.type, unit.index, unit.reactor or -1, unit.rs_conns })
end
end
return advertisement
end
local public = {}
function public.switch_nic(new_nic, rtu_state)
if tx_nic.is_connected() then
log.info(util.c("正在将链接切换到已重连接口 ", new_nic.phy_name(), " （原 ", tx_nic.phy_name(), "）"))
tx_nic = new_nic
_send(MGMT_TYPE.SWITCH_NET, {})
else
log.info(util.c("正在关闭 ", tx_nic.phy_name(), " 上的链接，切换到 ", new_nic.phy_name()))
tx_nic = new_nic
conn_watchdog.cancel()
public.unlink(rtu_state)
end
end
function public.manage_failover(act_nic)
if (act_nic ~= tx_nic) and act_nic.is_network_up() and ((util.time_ms() - self.failover_init) > FAILOVER_GRACE_PERIOD_MS) then
log.info(util.c("主接口 ", act_nic.phy_name(), " 已恢复，请求切换链接"))
tx_nic = act_nic
_send(MGMT_TYPE.SWITCH_NET, {})
self.failover_init = util.time_ms()
end
end
function public.unlink(rtu_state)
rtu_state.linked = false
self.sv_addr = comms.BROADCAST
self.r_seq_num = nil
databus.tx_link_state(types.PANEL_LINK_STATE.DISCONNECTED)
end
function public.close(rtu_state)
conn_watchdog.cancel()
_send(MGMT_TYPE.CLOSE, {})
public.unlink(rtu_state)
end
function public.send_modbus(m_cnt)
local frame = comms.scada_frame()
frame.make(self.sv_addr, self.seq_num, PROTOCOL.MODBUS_TCP, m_cnt.raw_packet())
tx_nic.transmit(config.SVR_Channel, config.RTU_Channel, frame)
self.seq_num = self.seq_num + 1
end
function public.send_establish(nic, units)
local ini_nic = tx_nic
tx_nic = nic
self.r_seq_num = nil
_send(MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.RTU, _generate_advertisement(units) })
tx_nic = ini_nic
end
function public.send_advertisement(units)
_send(MGMT_TYPE.RTU_ADVERT, _generate_advertisement(units))
end
function public.send_remounted(unit_index)
_send(MGMT_TYPE.RTU_DEV_REMOUNT, { unit_index })
end
function public.parse_packet(side, sender, reply_to, message, distance)
local pkt, nic = nil, backplane.nics[side]
if nic then
local frame = nic.receive(side, sender, reply_to, message, distance)
if frame then
if frame.protocol() == PROTOCOL.MODBUS_TCP then
pkt = comms.modbus_container().decode(frame)
elseif frame.protocol() == PROTOCOL.SCADA_MGMT then
pkt = comms.mgmt_container().decode(frame)
else
log.debug("非法数据包类型 " .. frame.protocol(), true)
end
end
else
log.error("parse_packet(" .. side .. "): received a packet from an interface without a nic?")
end
return pkt
end
function public.handle_packet(packet, units, rtu_state, sounders)
local function println_ts(message) if not rtu_state.fp_ok then util.println_ts(message) end end
local protocol = packet.scada_frame.protocol()
local l_chan   = packet.scada_frame.local_channel()
local src_addr = packet.scada_frame.src_addr()
if l_chan == config.RTU_Channel then
if self.r_seq_num == nil then
self.r_seq_num = packet.scada_frame.seq_num() + 1
elseif self.r_seq_num ~= packet.scada_frame.seq_num() then
log.warning("序列号乱序： 下一序号 = " .. self.r_seq_num .. "，新序号 = " .. packet.scada_frame.seq_num())
return
elseif rtu_state.linked and (src_addr ~= self.sv_addr) then
log.debug("received packet from unknown computer " .. src_addr .. " while linked (expected " .. self.sv_addr ..
"); channel in use by another system?")
return
else
self.r_seq_num = packet.scada_frame.seq_num() + 1
end
conn_watchdog.feed()
if protocol == PROTOCOL.MODBUS_TCP then
if rtu_state.linked then
local return_code
local reply
if packet.unit_id <= #units then
local unit = units[packet.unit_id]
local unit_dbg_tag = " (unit " .. packet.unit_id .. ")"
if unit.type == RTU_UNIT_TYPE.REDSTONE then
return_code, reply = unit.modbus_io.handle_adu(packet)
if not return_code then
log.warning("请求的 MODBUS 操作失败" .. unit_dbg_tag)
end
else
return_code, reply = unit.modbus_io.check_request(packet)
if return_code then
if unit.pkt_queue.length() > 3 then
reply = modbus.reply__srv_device_busy(packet)
log.warning("设备忙碌，丢弃新请求" .. unit_dbg_tag)
else
unit.pkt_queue.push_network(packet)
end
else
log.warning("请求的 MODBUS 操作失败" .. unit_dbg_tag)
end
end
else
reply = modbus.reply__gw_unavailable(packet)
log.debug("received MODBUS packet for non-existent unit")
end
public.send_modbus(reply)
else
log.debug("discarding MODBUS packet before linked")
end
elseif protocol == PROTOCOL.SCADA_MGMT then
if rtu_state.linked then
if packet.type == MGMT_TYPE.KEEP_ALIVE then
if packet.length == 1 and type(packet.data[1]) == "number" then
local timestamp = packet.data[1]
local trip_time = util.time() - timestamp
if trip_time > 750 then
log.warning("RTU 保活往返时间 > 750ms (" .. trip_time .. "ms)")
end
_send_keep_alive_ack(timestamp)
else
log.debug("SCADA_MGMT keep alive packet length/type mismatch")
end
elseif packet.type == MGMT_TYPE.CLOSE then
conn_watchdog.cancel()
public.unlink(rtu_state)
println_ts("服务器连接已被远程主机关闭")
log.warning("服务器连接已被远程主机关闭")
elseif packet.type == MGMT_TYPE.RTU_ADVERT then
public.send_advertisement(units)
elseif packet.type == MGMT_TYPE.RTU_TONE_ALARM then
if (packet.length == 1) and type(packet.data[1] == "table") and (#packet.data[1] == 8) then
local states = packet.data[1]
for i = 1, #sounders do
for id = 1, #states do sounders[i].stream.set_active(id, states[id] == true) end
end
end
else
log.debug("received unsupported SCADA_MGMT message type " .. packet.type)
end
elseif packet.type == MGMT_TYPE.ESTABLISH then
if packet.length == 1 then
local est_ack = packet.data[1]
if est_ack == ESTABLISH_ACK.ALLOW then
tx_nic = backplane.nics[packet.scada_frame.interface()]
rtu_state.linked = true
self.sv_addr = packet.scada_frame.src_addr()
println_ts("监控端连接已建立")
log.info(util.c("supervisor connection established, linked to SV (CID#", src_addr, ") on ", tx_nic.phy_name()))
else
if est_ack ~= self.last_est_ack then
if est_ack == ESTABLISH_ACK.BAD_VERSION then
println_ts("监控端通讯版本不匹配（请尝试更新），正在重试...")
log.warning("supervisor connection denied due to comms version mismatch, retrying")
else
println_ts("监控端连接被拒绝，正在重试...")
log.warning("supervisor connection denied, retrying")
end
end
self.sv_addr = comms.BROADCAST
rtu_state.linked = false
end
self.last_est_ack = est_ack
databus.tx_link_state(est_ack + 1)
else
log.debug("SCADA_MGMT establish packet length mismatch")
end
else
log.debug("discarding non-link SCADA_MGMT packet before linked")
end
else
log.error("非法数据包类型 " .. protocol, true)
end
else
log.debug("在未配置的通道上收到数据包 " .. l_chan, true)
end
end
return public
end
return rtu
