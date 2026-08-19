
local comms       = require("scada-common.comms")
local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local types       = require("scada-common.types")
local util        = require("scada-common.util")
local databus     = require("supervisor.databus")
local pgi         = require("supervisor.panel.pgi")
local coordinator = require("supervisor.session.coordinator")
local plc         = require("supervisor.session.plc")
local pocket      = require("supervisor.session.pocket")
local rtu         = require("supervisor.session.rtu")
local svqtypes    = require("supervisor.session.svqtypes")
local RTU_LINK_FAIL = types.RTU_LINK_FAIL
local RTU_TYPES     = types.RTU_UNIT_TYPE
local SV_Q_DATA     = svqtypes.SV_Q_DATA
local PLC_S_CMDS    = plc.PLC_S_CMDS
local PLC_S_DATA    = plc.PLC_S_DATA
local CRD_S_DATA    = coordinator.CRD_S_DATA
local svsessions = {}
local SESSION_TYPE = {
RTU_SESSION = 0,
PLC_SESSION = 1,
CRD_SESSION = 2,
PDG_SESSION = 3
}
svsessions.SESSION_TYPE = SESSION_TYPE
local self = {
fp_ok = false,
config = nil,
facility = nil,
plc_ini_reset = {},
sessions = {
rtu = {},
plc = {},
crd = {},
pdg = {}
},
next_ids = { rtu = 0, plc = 0, crd = 0, pdg = 0 },
dev_dbg = {
duplicate = {},
out_of_range = {},
mismatch = {},
connected = {}
}
}
local function _sv_handle_outq(session)
local handle_start = util.time()
while session.out_queue.ready() do
local msg = session.out_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.NETWORK then
session.nic.transmit(session.r_chan, self.config.SVR_Channel, msg.message)
elseif msg.qtype == mqueue.TYPE.DATA then
local cmd = msg.message
if cmd.key < SV_Q_DATA.__END_PLC_CMDS__ then
local plc_s = svsessions.get_reactor_session(cmd.val[1])
if plc_s ~= nil then
if cmd.key == SV_Q_DATA.START then
plc_s.in_queue.push_command(PLC_S_CMDS.ENABLE)
elseif cmd.key == SV_Q_DATA.SCRAM then
plc_s.in_queue.push_command(PLC_S_CMDS.SCRAM)
elseif cmd.key == SV_Q_DATA.RESET_RPS then
plc_s.in_queue.push_command(PLC_S_CMDS.RPS_RESET)
elseif cmd.key == SV_Q_DATA.SET_BURN and type(cmd.val) == "table" and #cmd.val == 2 then
plc_s.in_queue.push_data(PLC_S_DATA.BURN_RATE, cmd.val[2])
else
log.debug(util.c("SVS: 未知的 PLC SV 队列命令 ", cmd.key))
end
end
else
local crd_s = svsessions.get_crd_session()
if crd_s ~= nil then
if cmd.key == SV_Q_DATA.CRDN_ACK then
crd_s.in_queue.push_data(CRD_S_DATA.CMD_ACK, cmd.val)
elseif cmd.key == SV_Q_DATA.PLC_BUILD_CHANGED then
crd_s.in_queue.push_data(CRD_S_DATA.RESEND_PLC_BUILD, cmd.val)
elseif cmd.key == SV_Q_DATA.RTU_BUILD_CHANGED then
crd_s.in_queue.push_data(CRD_S_DATA.RESEND_RTU_BUILD, cmd.val)
end
end
end
end
end
if util.time() - handle_start > 100 then
log.debug("SVS: 监控端出队处理器超过 100ms 队列处理上限")
log.debug(util.c("SVS: 问题会话: ", session))
break
end
end
end
local function _iterate(sessions)
for i = 1, #sessions do
local session = sessions[i]
if session.open and session.instance.iterate() then
_sv_handle_outq(session)
else session.open = false end
end
end
local function _shutdown(session)
session.open = false
session.instance.close()
while session.out_queue.ready() do
local msg = session.out_queue.pop()
if msg ~= nil and msg.qtype == mqueue.TYPE.NETWORK then
session.nic.transmit(session.r_chan, self.config.SVR_Channel, msg.message)
end
end
log.debug(util.c("SVS: 已关闭会话 ", session))
end
local function _close(sessions)
for i = 1, #sessions do
local session = sessions[i]
if session.open then _shutdown(session) end
end
end
local function _check_watchdogs(sessions, timer_event)
for i = 1, #sessions do
local session = sessions[i]
if session.open then
local triggered = session.instance.check_wd(timer_event)
if triggered then
log.debug(util.c("SVS: 看门狗正在关闭会话 ", session, "..."))
_shutdown(session)
return true
end
end
end
return false
end
local function _free_closed(sessions)
local f = function (session) return session.open end
local on_delete = function (session)
log.debug(util.c("SVS: 释放已关闭的会话 ", session))
end
util.filter_table(sessions, f, on_delete)
end
local function _find_session(list, s_addr)
for i = 1, #list do
if list[i].s_addr == s_addr then return list[i] end
end
return nil
end
local function _update_dev_dbg()
local f = function (unit) return unit.is_connected() end
util.filter_table(self.dev_dbg.duplicate, f, pgi.delete_chk_entry)
util.filter_table(self.dev_dbg.out_of_range, f, pgi.delete_chk_entry)
util.filter_table(self.dev_dbg.mismatch, f, pgi.delete_chk_entry)
local conns     = self.dev_dbg.connected
local units     = self.facility.get_units()
local rtu_conns = self.facility.check_rtu_conns()
local function report(disconnected, msg)
if disconnected then pgi.create_missing_entry(msg) else pgi.delete_missing_entry(msg) end
end
if rtu_conns.ess ~= conns.ess then
report(conns.ess, util.c("设施的储能系统"))
conns.ess = rtu_conns.ess
end
if rtu_conns.sps ~= conns.sps then
report(conns.sps, util.c("设施的 SPS"))
conns.sps = rtu_conns.sps
end
for i = 1, #conns.tanks do
if (rtu_conns.tanks[i] or false) ~= conns.tanks[i] then
report(conns.tanks[i], util.c("设施的 #", i, " 号动态罐"))
conns.tanks[i] = rtu_conns.tanks[i] or false
end
end
for u = 1, #units do
local u_conns = conns.units[u]
rtu_conns = units[u].check_rtu_conns()
for i = 1, #u_conns.boilers do
if (rtu_conns.boilers[i] or false) ~= u_conns.boilers[i] then
report(u_conns.boilers[i], util.c("机组 ", u, " 的 #", i, " 号锅炉"))
u_conns.boilers[i] = rtu_conns.boilers[i] or false
end
end
for i = 1, #u_conns.turbines do
if (rtu_conns.turbines[i] or false) ~= u_conns.turbines[i] then
report(u_conns.turbines[i], util.c("机组 ", u, " 的 #", i, " 号涡轮机"))
u_conns.turbines[i] = rtu_conns.turbines[i] or false
end
end
for i = 1, #u_conns.tanks do
if (rtu_conns.tanks[i] or false) ~= u_conns.tanks[i] then
report(u_conns.tanks[i], util.c("机组 ", u, " 的动态罐"))
u_conns.tanks[i] = rtu_conns.tanks[i] or false
end
end
end
end
function svsessions.check_rtu_id(unit, list, max)
local fail_code, fail_str = RTU_LINK_FAIL.OK, "OK"
if (unit.get_device_idx() < 1 and max ~= 1) or unit.get_device_idx() > max then
fail_code, fail_str = RTU_LINK_FAIL.OUT_OF_RANGE, "索引超出范围"
table.insert(self.dev_dbg.out_of_range, unit)
else
for _, u in ipairs(list) do
if u.get_device_idx() == unit.get_device_idx() then
fail_code, fail_str = RTU_LINK_FAIL.DUPLICATE, "索引重复"
table.insert(self.dev_dbg.duplicate, unit)
break
end
end
end
if fail_code == RTU_LINK_FAIL.OK and #list >= max then
fail_code, fail_str = RTU_LINK_FAIL.MAX_DEVICES, "此类型数量过多"
end
if fail_code ~= RTU_LINK_FAIL.OK and fail_code ~= RTU_LINK_FAIL.MAX_DEVICES then
local r_id, idx, type = unit.get_reactor(), unit.get_device_idx(), unit.get_unit_type()
local msg
if r_id == 0 then
msg = "设施的 "
if type == RTU_TYPES.IMATRIX then
msg = msg .. "感应矩阵"
elseif type == RTU_TYPES.SPS then
msg = msg .. "SPS"
elseif type == RTU_TYPES.DYNAMIC_VALVE then
msg = util.c(msg, "#", idx, " 号动态罐")
elseif type == RTU_TYPES.ENV_DETECTOR then
msg = util.c(msg, "#", idx, " 号环境探测器")
else
msg = msg .. " ? (错误)"
end
else
msg = util.c("机组 ", r_id, " 的 ")
if type == RTU_TYPES.BOILER_VALVE then
msg = util.c(msg, "#", idx, " 号锅炉")
elseif type == RTU_TYPES.TURBINE_VALVE then
msg = util.c(msg, "#", idx, " 号涡轮机")
elseif type == RTU_TYPES.DYNAMIC_VALVE then
msg = msg .. "动态罐"
elseif type == RTU_TYPES.ENV_DETECTOR then
msg = util.c(msg, "#", idx, " 号环境探测器")
else
msg = msg .. " ? (错误)"
end
end
pgi.create_chk_entry(unit, fail_code, msg)
end
return fail_code, fail_str
end
function svsessions.report_rtu_mismatch(unit)
local r_id, type = unit.get_reactor(), unit.get_unit_type()
local msg
local details = ""
table.insert(self.dev_dbg.mismatch, unit)
if r_id == 0 then
msg = "一个设施 "
if type == RTU_TYPES.IMATRIX then
msg = msg .. "感应矩阵"
details = "配置用于能量核心"
elseif type == RTU_TYPES.ENERGY_CORE then
msg = msg .. "能量核心"
details = "配置用于感应矩阵"
elseif type == RTU_TYPES.DYNAMIC_VALVE then
msg = msg .. "动态罐"
details = "未配置用于设施罐"
elseif type == RTU_TYPES.SNA then
msg = msg .. "SNA（必须用于机组）"
else
msg = msg .. " ? (错误)"
end
else
msg = util.c("机组 ", r_id, " 的 ")
if type == RTU_TYPES.DYNAMIC_VALVE then
msg = msg .. "动态罐"
details = "机组未配置用于机组罐"
elseif type == RTU_TYPES.SNA then
msg = msg .. "SNA（必须用于设施）"
else
msg = msg .. " ? (错误)"
end
end
pgi.create_chk_entry(unit, RTU_LINK_FAIL.MISMATCH, msg, details)
end
function svsessions.init(fp_ok, config, facility)
self.fp_ok = fp_ok
self.config = config
self.facility = facility
self.dev_dbg.connected = { ess = true, sps = true, tanks = {}, units = {} }
local cool_conf = facility.get_cooling_conf()
for i = 1, #cool_conf.fac_tank_list do
if cool_conf.fac_tank_list[i] == 2 then
table.insert(self.dev_dbg.connected.tanks, true)
end
end
for i = 1, config.UnitCount do
local r_cool = cool_conf.r_cool[i]
local conns = { boilers = {}, turbines = {}, tanks = {} }
for b = 1, r_cool.BoilerCount do conns.boilers[b] = true end
for t = 1, r_cool.TurbineCount do conns.turbines[t] = true end
if r_cool.TankConnection and cool_conf.fac_tank_defs[i] == 1 then
conns.tanks[1] = true
end
self.plc_ini_reset[i] = true
self.dev_dbg.connected.units[i] = conns
end
end
function svsessions.find_rtu_session(source_addr)
local session = _find_session(self.sessions.rtu, source_addr)
return session
end
function svsessions.find_plc_session(source_addr)
local session = _find_session(self.sessions.plc, source_addr)
return session
end
function svsessions.find_crd_session(source_addr)
local session = _find_session(self.sessions.crd, source_addr)
return session
end
function svsessions.find_pdg_session(source_addr)
local session = _find_session(self.sessions.pdg, source_addr)
return session
end
function svsessions.get_crd_session()
return self.sessions.crd[1]
end
function svsessions.get_reactor_session(reactor)
local session = nil
for i = 1, #self.sessions.plc do
if self.sessions.plc[i].reactor == reactor then
session = self.sessions.plc[i]
end
end
return session
end
function svsessions.establish_plc_session(nic, source_addr, i_seq_num, for_reactor, version)
if svsessions.get_reactor_session(for_reactor) == nil and for_reactor >= 1 and for_reactor <= self.config.UnitCount then
if version == comms.CONN_TEST_FWV then return true end
local plc_s = {
s_type = "plc",
open = true,
reactor = for_reactor,
version = version,
nic = nic,
r_chan = self.config.PLC_Channel,
s_addr = source_addr,
in_queue = mqueue.new(),
out_queue = mqueue.new(),
instance = nil
}
local id = self.next_ids.plc
plc_s.instance = plc.new_session(id, source_addr, i_seq_num, for_reactor, plc_s.in_queue, plc_s.out_queue, self.config.PLC_Timeout, self.plc_ini_reset, self.fp_ok)
table.insert(self.sessions.plc, plc_s)
local units = self.facility.get_units()
units[for_reactor].link_plc_session(plc_s)
local mt = {
__tostring = function (s)  return util.c("PLC [", s.instance.get_id(), "] for reactor #", s.reactor, " (@", s.s_addr, ")") end
}
setmetatable(plc_s, mt)
databus.tx_plc_connected(for_reactor, version, source_addr)
log.debug(util.c("SVS: 已建立新会话: ", plc_s))
self.next_ids.plc = id + 1
return plc_s.instance.get_id()
else
return false
end
end
function svsessions.establish_rtu_session(nic, source_addr, i_seq_num, advertisement, version)
local rtu_s = {
s_type = "rtu",
open = true,
version = version,
nic = nic,
r_chan = self.config.RTU_Channel,
s_addr = source_addr,
in_queue = mqueue.new(),
out_queue = mqueue.new(),
instance = nil
}
local id = self.next_ids.rtu
rtu_s.instance = rtu.new_session(id, source_addr, i_seq_num, rtu_s.in_queue, rtu_s.out_queue, self.config.RTU_Timeout, advertisement, self.facility, self.fp_ok)
table.insert(self.sessions.rtu, rtu_s)
local mt = {
__tostring = function (s)  return util.c("RTU [", s.instance.get_id(), "] (@", s.s_addr, ")") end
}
setmetatable(rtu_s, mt)
databus.tx_rtu_connected(id, version, source_addr)
log.debug(util.c("SVS: 已建立新会话: ", rtu_s))
self.next_ids.rtu = id + 1
return id
end
function svsessions.establish_crd_session(nic, source_addr, i_seq_num, version)
if svsessions.get_crd_session() == nil then
local crd_s = {
s_type = "crd",
open = true,
version = version,
nic = nic,
r_chan = self.config.CRD_Channel,
s_addr = source_addr,
in_queue = mqueue.new(),
out_queue = mqueue.new(),
instance = nil
}
local id = self.next_ids.crd
crd_s.instance = coordinator.new_session(id, source_addr, i_seq_num, crd_s.in_queue, crd_s.out_queue, self.config.CRD_Timeout, self.facility, self.fp_ok)
table.insert(self.sessions.crd, crd_s)
local mt = {
__tostring = function (s)  return util.c("CRD [", s.instance.get_id(), "] (@", s.s_addr, ")") end
}
setmetatable(crd_s, mt)
databus.tx_crd_connected(version, source_addr)
log.debug(util.c("SVS: 已建立新会话: ", crd_s))
self.next_ids.crd = id + 1
return id
else
return false
end
end
function svsessions.establish_pdg_session(nic, source_addr, i_seq_num, version)
local pdg_s = {
s_type = "pkt",
open = true,
version = version,
nic = nic,
r_chan = self.config.PKT_Channel,
s_addr = source_addr,
in_queue = mqueue.new(),
out_queue = mqueue.new(),
instance = nil
}
local id = self.next_ids.pdg
pdg_s.instance = pocket.new_session(id, source_addr, i_seq_num, pdg_s.in_queue, pdg_s.out_queue, self.config.PKT_Timeout, self.sessions, self.facility, self.fp_ok, self.config.PocketTest)
table.insert(self.sessions.pdg, pdg_s)
local mt = {
__tostring = function (s)  return util.c("PDG [", s.instance.get_id(), "] (@", s.s_addr, ")") end
}
setmetatable(pdg_s, mt)
databus.tx_pdg_connected(id, version, source_addr)
log.debug(util.c("SVS: 已建立新会话: ", pdg_s))
self.next_ids.pdg = id + 1
return id
end
function svsessions.check_all_watchdogs(timer_event)
for _, list in pairs(self.sessions) do
if _check_watchdogs(list, timer_event) then return true end
end
return false
end
function svsessions.iterate_all()
for _, list in pairs(self.sessions) do _iterate(list) end
self.facility.report_rtu_gateways(self.sessions.rtu)
self.facility.update()
self.facility.update_units()
_update_dev_dbg()
end
function svsessions.free_all_closed()
for _, list in pairs(self.sessions) do _free_closed(list) end
end
function svsessions.close_all()
for _, list in pairs(self.sessions) do _close(list) end
svsessions.free_all_closed()
end
return svsessions
