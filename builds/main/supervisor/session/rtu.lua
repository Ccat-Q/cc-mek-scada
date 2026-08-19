local comms         = require("scada-common.comms")
local log           = require("scada-common.log")
local mqueue        = require("scada-common.mqueue")
local types         = require("scada-common.types")
local util          = require("scada-common.util")
local databus       = require("supervisor.databus")
local svqtypes      = require("supervisor.session.svqtypes")
local unit_session  = require("supervisor.session.rtu.unit_session")
local svrs_boilerv  = require("supervisor.session.rtu.boilerv")
local svrs_dynamicv = require("supervisor.session.rtu.dynamicv")
local svrs_ecore    = require("supervisor.session.rtu.ecore")
local svrs_envd     = require("supervisor.session.rtu.envd")
local svrs_imatrix  = require("supervisor.session.rtu.imatrix")
local svrs_redstone = require("supervisor.session.rtu.redstone")
local svrs_sna      = require("supervisor.session.rtu.sna")
local svrs_sps      = require("supervisor.session.rtu.sps")
local svrs_turbinev = require("supervisor.session.rtu.turbinev")
local rtu = {}
local PROTOCOL = comms.PROTOCOL
local MGMT_TYPE = comms.MGMT_TYPE
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local SV_Q_DATA = svqtypes.SV_Q_DATA
local PERIODICS = {
KEEP_ALIVE = 2000,
ALARM_TONES = 500
}
function rtu.new_session(id, s_addr, i_seq_num, in_queue, out_queue, timeout, advertisement, facility, fp_ok)
local function println(message) if not fp_ok then util.println_ts(message) end end
local log_tag = "rtu_gw_session(" .. id .. "): "
local self = {
modbus_q = mqueue.new(),
advert = advertisement,
fac_units = facility.get_units(),
seq_num = i_seq_num + 2,
r_seq_num = i_seq_num + 1,
connected = true,
conn_watchdog = util.new_watchdog(timeout),
last_rtt = 0,
periodics = {
last_update = 0,
keep_alive = 0,
alarm_tones = 0
},
units = {}
}
local public = {}
local function _reset_config()
self.units = {}
end
local function _handle_advertisement()
local unit_count = 0
_reset_config()
for i = 1, #self.fac_units do
local unit = self.fac_units[i]
unit.purge_rtu_devices(id)
facility.purge_rtu_devices(id)
end
for i = 1, #self.advert do
local unit = nil
local unit_advert = {
type = self.advert[i][1],
index = self.advert[i][2],
reactor = self.advert[i][3],
rs_conns = self.advert[i][4]
}
local u_type = unit_advert.type
local advert_validator = util.new_validator()
advert_validator.assert(util.is_int(unit_advert.index) or (unit_advert.index == false))
advert_validator.assert_type_int(unit_advert.reactor)
if advert_validator.valid() then
if util.is_int(unit_advert.index) then advert_validator.assert_min(unit_advert.index, 1) end
if (unit_advert.reactor == -1) or (u_type == RTU_UNIT_TYPE.REDSTONE) then
advert_validator.assert((unit_advert.reactor == -1) and (u_type == RTU_UNIT_TYPE.REDSTONE))
advert_validator.assert_type_table(unit_advert.rs_conns)
else
advert_validator.assert_min(unit_advert.reactor, 0)
advert_validator.assert_max(unit_advert.reactor, #self.fac_units)
end
if not advert_validator.valid() then u_type = false end
else
u_type = false
end
local type_string = util.strval(u_type)
if type(u_type) == "number" then type_string = types.rtu_type_to_string(u_type) end
if u_type == false then
log.debug(log_tag .. "_handle_advertisement(): 广告单元验证失败")
else
if unit_advert.reactor == -1 then
if u_type == RTU_UNIT_TYPE.REDSTONE then
unit = svrs_redstone.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then
for assignment, conns in pairs(unit_advert.rs_conns) do
if #conns > 0 then
if assignment == 0 then
facility.add_redstone(unit)
elseif assignment > 0 and assignment <= #self.fac_units then
self.fac_units[assignment].add_redstone(unit)
else
log.warning(util.c(log_tag, "_handle_advertisement(): 无效的 redstone RTU 分配 ", assignment))
end
end
end
end
else
log.warning(util.c(log_tag, "_handle_advertisement(): 遇到不支持的多分配 RTU 类型 ", type_string))
end
elseif unit_advert.reactor > 0 then
local target_unit = self.fac_units[unit_advert.reactor]
if u_type == RTU_UNIT_TYPE.BOILER_VALVE then
unit = svrs_boilerv.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then target_unit.add_boiler(unit) end
elseif u_type == RTU_UNIT_TYPE.TURBINE_VALVE then
unit = svrs_turbinev.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then target_unit.add_turbine(unit) end
elseif u_type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
unit = svrs_dynamicv.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then target_unit.add_tank(unit) end
elseif u_type == RTU_UNIT_TYPE.SNA then
unit = svrs_sna.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then target_unit.add_sna(unit) end
elseif u_type == RTU_UNIT_TYPE.ENV_DETECTOR then
unit = svrs_envd.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then target_unit.add_envd(unit) end
elseif u_type == RTU_UNIT_TYPE.VIRTUAL then
log.debug(util.c(log_tag, "跳过虚拟 RTU #", i))
else
log.warning(util.c(log_tag, "_handle_advertisement(): 遇到不支持的特定反应堆 RTU 类型 ", type_string))
end
else
if u_type == RTU_UNIT_TYPE.REDSTONE then
unit = svrs_redstone.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then facility.add_redstone(unit) end
elseif u_type == RTU_UNIT_TYPE.IMATRIX then
unit = svrs_imatrix.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then facility.add_imatrix(unit) end
elseif u_type == RTU_UNIT_TYPE.ENERGY_CORE then
unit = svrs_ecore.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then facility.add_ecore(unit) end
elseif u_type == RTU_UNIT_TYPE.SNA then
unit = svrs_sna.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then facility.add_sna(unit) end
elseif u_type == RTU_UNIT_TYPE.SPS then
unit = svrs_sps.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then facility.add_sps(unit) end
elseif u_type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
unit = svrs_dynamicv.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then facility.add_tank(unit) end
elseif u_type == RTU_UNIT_TYPE.ENV_DETECTOR then
unit = svrs_envd.new(id, i, unit_advert, self.modbus_q)
if type(unit) ~= "nil" then facility.add_envd(unit) end
elseif u_type == RTU_UNIT_TYPE.VIRTUAL then
log.debug(util.c(log_tag, "跳过虚拟 RTU #", i))
else
log.warning(util.c(log_tag, "_handle_advertisement(): 遇到不支持的设施 RTU 类型 ", type_string))
end
end
end
if unit ~= nil then
self.units[i] = unit
unit_count = unit_count + 1
elseif u_type ~= RTU_UNIT_TYPE.VIRTUAL then
log.warning(util.c(log_tag, "_handle_advertisement(): 创建单元时出现问题 (类型为 ", type_string, ")"))
end
end
databus.tx_rtu_units(id, unit_count)
end
local function _close()
self.conn_watchdog.cancel()
self.connected = false
databus.tx_rtu_disconnected(id)
for _, unit in pairs(self.units) do unit.close() end
end
local function _send_modbus(m_cnt)
local frame = comms.scada_frame()
frame.make(s_addr, self.seq_num, PROTOCOL.MODBUS_TCP, m_cnt.raw_packet())
out_queue.push_network(frame)
self.seq_num = self.seq_num + 1
end
local function _send_mgmt(msg_type, msg)
local frame, mgmt = comms.scada_frame(), comms.mgmt_container()
mgmt.make(msg_type, msg)
frame.make(s_addr, self.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
out_queue.push_network(frame)
self.seq_num = self.seq_num + 1
end
local function _handle_packet(pkt)
if self.r_seq_num ~= pkt.scada_frame.seq_num() then
log.warning(log_tag .. "序列乱序：next = " .. self.r_seq_num .. ", new = " .. pkt.scada_frame.seq_num())
return
else
self.r_seq_num = pkt.scada_frame.seq_num() + 1
end
self.conn_watchdog.feed()
if pkt.scada_frame.protocol() == PROTOCOL.MODBUS_TCP then
if self.units[pkt.unit_id] ~= nil then
self.units[pkt.unit_id].handle_adu(pkt)
end
elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
if pkt.type == MGMT_TYPE.KEEP_ALIVE then
if pkt.length == 2 then
local srv_start = pkt.data[1]
local srv_now = util.time()
self.last_rtt = srv_now - srv_start
if self.last_rtt > 750 then
log.warning(log_tag .. "RTU GW KEEP_ALIVE 往返时间 > 750ms (" .. self.last_rtt .. "ms)")
end
databus.tx_rtu_rtt(id, self.last_rtt)
else
log.debug(log_tag .. "SCADA 保活数据包长度不匹配")
end
elseif pkt.type == MGMT_TYPE.CLOSE then
_close()
elseif pkt.type == MGMT_TYPE.SWITCH_NET then
log.debug(log_tag .. "收到有效的连接切换请求")
elseif pkt.type == MGMT_TYPE.ESTABLISH then
_close()
log.warning(log_tag .. "因意外收到 ESTABLISH 数据包而终止会话")
elseif pkt.type == MGMT_TYPE.RTU_ADVERT then
log.debug(log_tag .. "收到更新的广告信息")
self.advert = pkt.data
_handle_advertisement()
elseif pkt.type == MGMT_TYPE.RTU_DEV_REMOUNT then
if pkt.length == 1 then
local unit_id = pkt.data[1]
if self.units[unit_id] ~= nil then
self.units[unit_id].invalidate_cache()
end
else
log.debug(log_tag .. "SCADA RTU GW 设备重挂载数据包长度不匹配")
end
else
log.debug(log_tag .. "处理程序收到不支持的 SCADA_MGMT 数据包类型 " .. pkt.type)
end
end
end
function public.get_id() return id end
function public.check_wd(timer)
return self.conn_watchdog.is_timer(timer) and self.connected
end
function public.close()
_close()
_send_mgmt(MGMT_TYPE.CLOSE, {})
println(log_tag .. "到 RTU GW 的连接已被服务器关闭")
log.info(log_tag .. "会话已被服务器关闭")
end
function public.iterate()
if self.connected then
local handle_start = util.time()
while in_queue.ready() and self.connected do
local msg = in_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.NETWORK then
_handle_packet(msg.message)
end
end
if util.time() - handle_start > 100 then
log.warning(log_tag .. "超过 100ms 队列处理上限")
break
end
end
if not self.connected then
println("RTU 连接 " .. id .. " 已被远端主机关闭")
log.info(log_tag .. "会话已被远端主机关闭")
return self.connected
end
local time_now = util.time()
for _, unit in pairs(self.units) do unit.update(time_now) end
local elapsed = util.time() - self.periodics.last_update
local periodics = self.periodics
periodics.keep_alive = periodics.keep_alive + elapsed
if periodics.keep_alive >= PERIODICS.KEEP_ALIVE then
_send_mgmt(MGMT_TYPE.KEEP_ALIVE, { util.time() })
periodics.keep_alive = 0
end
periodics.alarm_tones = periodics.alarm_tones + elapsed
if periodics.alarm_tones >= PERIODICS.ALARM_TONES then
_send_mgmt(MGMT_TYPE.RTU_TONE_ALARM, { facility.get_alarm_tones() })
periodics.alarm_tones = 0
end
self.periodics.last_update = util.time()
for _ = 1, self.modbus_q.length() do
local msg = self.modbus_q.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.NETWORK then
_send_modbus(msg.message)
elseif msg.qtype == mqueue.TYPE.DATA then
local cmd = msg.message
if cmd.key == unit_session.RTU_US_DATA.BUILD_CHANGED then
out_queue.push_data(SV_Q_DATA.RTU_BUILD_CHANGED, cmd.val)
end
end
end
end
end
return self.connected
end
_handle_advertisement()
return public
end
return rtu
