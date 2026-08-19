local const      = require("scada-common.constants")
local log        = require("scada-common.log")
local rsio       = require("scada-common.rsio")
local types      = require("scada-common.types")
local util       = require("scada-common.util")
local alarm_ctl  = require("supervisor.alarm_ctl")
local unit_logic = require("supervisor.unit_logic")
local plc        = require("supervisor.session.plc")
local rsctl      = require("supervisor.session.rsctl")
local svsessions = require("supervisor.session.svsessions")
local AISTATE       = alarm_ctl.AISTATE
local ALARM         = types.ALARM
local ALARM_STATE   = types.ALARM_STATE
local PRIO          = types.ALARM_PRIORITY
local RTU_LINK_FAIL = types.RTU_LINK_FAIL
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local TRI_FAIL      = types.TRI_FAIL
local WASTE_MODE    = types.WASTE_MODE
local WASTE         = types.WASTE_PRODUCT
local PLC_S_CMDS = plc.PLC_S_CMDS
local IO = rsio.IO
local DT_KEYS = {
ReactorBurnR = "RBR",
ReactorTemp  = "RTP",
ReactorFuel  = "RFL",
ReactorWaste = "RWS",
ReactorCCool = "RCC",
ReactorHCool = "RHC",
BoilerWater  = "BWR",
BoilerSteam  = "BST",
BoilerCCool  = "BCC",
BoilerHCool  = "BHC",
TurbineSteam = "TST",
TurbinePower = "TPR"
}
local IDLE_RATE = 0.01
local SODIUM_THERM_CONV = const.mek.SODIUM_THERMAL_ENTHALPY / const.mek.SODIUM_CONDUCTIVITY
local WATER_THERM_CONV  = const.mek.WATER_THERMAL_ENTHALPY / const.mek.STEAM_ENERGY_EFF
local unit = {}
function unit.new(reactor_id, cooling_conf, po_prod_ratio, config)
local IDLE_TIME = util.trinary(config.ExtChargeIdling, 60000, 10000)
local log_tag = "UNIT " .. reactor_id .. ": "
local self = {
r_id = reactor_id,
plc_s = nil,
plc_i = nil,
num_boilers = cooling_conf.r_cool[reactor_id].BoilerCount,
num_turbines = cooling_conf.r_cool[reactor_id].TurbineCount,
aux_coolant = cooling_conf.aux_coolant[reactor_id],
tank_conn = cooling_conf.fac_tank_defs[reactor_id],
types = { DT_KEYS = DT_KEYS },
rtu_list = {},
redstone = {},
boilers = {},
turbines = {},
tanks = {},
snas = {},
envd = {},
io_ctl = nil,
valves = {},
em_cool_opened = false,
aux_cool_opened = false,
auto_engaged = false,
auto_idle = false,
auto_idling = false,
auto_idle_start = 0,
auto_was_alarmed = false,
auto_act_diff_cnt = 0,
auto_act_lim_br100 = math.huge,
deltas = {},
last_heartbeat = 0,
last_radiation = 0,
damage_decreasing = false,
damage_initial = 0,
damage_start = 0,
damage_last = 0,
damage_est_last = 0,
waste_product = WASTE.PLUTONIUM,
status_text = { "未知", "等待连接..." },
enable_aux_cool = false,
fuel_burn_rate_limited = false,
energy_mismatch = false,
energy_mismatch_start = nil,
had_reactor = false,
turbine_flow_stable = false,
turbine_stability_data = {},
last_rate_change_ms = 0,
last_rps_trips = {
high_dmg = false,
high_temp = false,
low_cool = false,
ex_waste = false,
ex_hcool = false,
fault = false,
timeout = false,
manual = false,
automatic = false,
sys_fail = false,
force_dis = false
},
plc_cache = {
active = false,
ok = false,
rps_trip = false,
rps_status = {
high_dmg = false,
high_temp = false,
low_cool = false,
ex_waste = false,
ex_hcool = false,
fault = false,
timeout = false,
manual = false,
automatic = false,
sys_fail = false,
force_dis = false
},
damage = 0,
temp = 0,
fuel = 0,
waste = 0,
high_temp_lim = 1150
},
alarms = {
ContainmentBreach    = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ContainmentBreach, tier = PRIO.CRITICAL },
ContainmentRadiation = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ContainmentRadiation, tier = PRIO.CRITICAL },
ReactorLost          = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorLost, tier = PRIO.TIMELY },
CriticalDamage       = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.CriticalDamage, tier = PRIO.CRITICAL },
ReactorDamage        = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorDamage, tier = PRIO.EMERGENCY },
ReactorOverTemp      = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorOverTemp, tier = PRIO.URGENT },
ReactorHighTemp      = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 1, id = ALARM.ReactorHighTemp, tier = PRIO.TIMELY },
ReactorWasteLeak     = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorWasteLeak, tier = PRIO.EMERGENCY },
ReactorHighWaste     = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.ReactorHighWaste, tier = PRIO.URGENT },
RPSTransient         = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.RPSTransient, tier = PRIO.TIMELY },
RCSTransient         = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 5, id = ALARM.RCSTransient, tier = PRIO.TIMELY },
TurbineTrip          = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.TurbineTrip, tier = PRIO.URGENT }
},
db = {
annunciator = {
PLCOnline = false,
PLCHeartbeat = false,
RadiationMonitor = 1,
AutoControl = false,
ReactorSCRAM = false,
ManualReactorSCRAM = false,
AutoReactorSCRAM = false,
RadiationWarning = false,
RCPTrip = false,
RCSFlowLow = false,
CoolantLevelLow = false,
ReactorTempHigh = false,
ReactorHighDeltaT = false,
FuelInputRateLow = false,
WasteLineOcclusion = false,
HighStartupRate = false,
RCSFault = false,
EmergencyCoolant = 1,
CoolantFeedMismatch = false,
BoilRateMismatch = false,
SteamFeedMismatch = false,
MaxWaterReturnFeed = false,
BoilerOnline = {},
HeatingRateLow = {},
WaterLevelLow = {},
TurbineOnline = {},
SteamDumpOpen = {},
TurbineOverSpeed = {},
GeneratorTrip = {},
TurbineTrip = {}
},
alarm_states = {
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE,
ALARM_STATE.INACTIVE
},
control = {
ready = false,
degraded = false,
generator_mismatch = false,
generator_mult = 0,
turbine_mismatch = false,
turbine_flow_perf = 0,
br100 = 0,
lim_br100 = 0,
waste_mode = WASTE_MODE.AUTO
}
}
}
self.rtu_list = { self.redstone, self.boilers, self.turbines, self.tanks, self.snas, self.envd }
self.io_ctl = rsctl.new(self.redstone, reactor_id)
for _ = 1, self.num_boilers do
table.insert(self.db.annunciator.BoilerOnline, false)
table.insert(self.db.annunciator.HeatingRateLow, false)
end
for _ = 1, self.num_turbines do
table.insert(self.db.annunciator.TurbineOnline, false)
table.insert(self.db.annunciator.SteamDumpOpen, TRI_FAIL.OK)
table.insert(self.db.annunciator.TurbineOverSpeed, false)
table.insert(self.db.annunciator.GeneratorTrip, false)
table.insert(self.db.annunciator.TurbineTrip, false)
table.insert(self.turbine_stability_data, { time_state = 0, time_tanks = 0, rotation = 1, input_rate = 0 })
end
local function _compute_dt(key, value, time)
if self.deltas[key] then
local data = self.deltas[key]
if time > data.last_t then
data.dt = (value - data.last_v) / (time - data.last_t)
data.last_v = value
data.last_t = time
end
else
self.deltas[key] = {
last_t = time,
last_v = value,
dt = 0.0
}
end
end
local function _reset_dt(key) self.deltas[key] = nil end
function self._get_dt(key) if self.deltas[key] then return self.deltas[key].dt else return 0.0 end end
local function _dt__compute_all()
if self.plc_i ~= nil then
local plc_db = self.plc_i.get_db()
local last_update_s = plc_db.last_status_update / 1000.0
_compute_dt(DT_KEYS.ReactorBurnR, plc_db.mek_status.act_burn_rate, last_update_s)
_compute_dt(DT_KEYS.ReactorTemp, plc_db.mek_status.temp, last_update_s)
_compute_dt(DT_KEYS.ReactorFuel, plc_db.mek_status.fuel, last_update_s)
_compute_dt(DT_KEYS.ReactorWaste, plc_db.mek_status.waste, last_update_s)
_compute_dt(DT_KEYS.ReactorCCool, plc_db.mek_status.ccool_amnt, last_update_s)
_compute_dt(DT_KEYS.ReactorHCool, plc_db.mek_status.hcool_amnt, last_update_s)
end
for i = 1, #self.boilers do
local boiler = self.boilers[i]
local db = boiler.get_db()
local last_update_s = db.tanks.last_update / 1000.0
_compute_dt(DT_KEYS.BoilerWater .. boiler.get_device_idx(), db.tanks.water.amount, last_update_s)
_compute_dt(DT_KEYS.BoilerSteam .. boiler.get_device_idx(), db.tanks.steam.amount, last_update_s)
_compute_dt(DT_KEYS.BoilerCCool .. boiler.get_device_idx(), db.tanks.ccool.amount, last_update_s)
_compute_dt(DT_KEYS.BoilerHCool .. boiler.get_device_idx(), db.tanks.hcool.amount, last_update_s)
end
for i = 1, #self.turbines do
local turbine = self.turbines[i]
local db = turbine.get_db()
local last_update_s = db.tanks.last_update / 1000.0
_compute_dt(DT_KEYS.TurbineSteam .. turbine.get_device_idx(), db.tanks.steam.amount, last_update_s)
_compute_dt(DT_KEYS.TurbinePower .. turbine.get_device_idx(), db.tanks.energy, last_update_s)
end
end
local waste_pu  = self.io_ctl.as_valve(IO.U_WASTE_PU)
local waste_sna = self.io_ctl.as_valve(IO.U_WASTE_PO)
local waste_po  = self.io_ctl.as_valve(IO.U_WASTE_POPL)
local waste_sps = self.io_ctl.as_valve(IO.U_WASTE_AM)
local emer_cool = self.io_ctl.as_valve(IO.U_EMER_COOL)
local aux_cool  = self.io_ctl.as_valve(IO.U_AUX_COOL)
self.valves = {
waste_pu = waste_pu,
waste_sna = waste_sna,
waste_po = waste_po,
waste_sps = waste_sps,
emer_cool = emer_cool,
aux_cool = aux_cool
}
local function _set_waste_valves(product)
self.waste_product = product
if product == WASTE.PLUTONIUM then
waste_pu.open()
waste_sna.close()
waste_po.close()
waste_sps.close()
elseif product == WASTE.POLONIUM then
waste_pu.close()
waste_sna.open()
waste_po.open()
waste_sps.close()
elseif product == WASTE.ANTI_MATTER then
waste_pu.close()
waste_sna.open()
waste_po.close()
waste_sps.open()
end
end
local public = {}
function public.link_plc_session(plc_session)
self.had_reactor = true
self.plc_s = plc_session
self.plc_i = plc_session.instance
log.debug(util.c(log_tag, "已连接 PLC [", plc_session.s_addr, ":", plc_session.r_chan, "]"))
_reset_dt(DT_KEYS.ReactorTemp)
_reset_dt(DT_KEYS.ReactorFuel)
_reset_dt(DT_KEYS.ReactorWaste)
_reset_dt(DT_KEYS.ReactorCCool)
_reset_dt(DT_KEYS.ReactorHCool)
end
function public.add_redstone(rs_unit)
table.insert(self.redstone, rs_unit)
log.debug(util.c(log_tag, "已连接红石 [", rs_unit.get_unit_id(), "@", rs_unit.get_session_id(), "]"))
_set_waste_valves(self.waste_product)
end
function public.add_turbine(turbine)
local fail_code, fail_str = svsessions.check_rtu_id(turbine, self.turbines, self.num_turbines)
local ok = fail_code == RTU_LINK_FAIL.OK
if ok then
table.insert(self.turbines, turbine)
log.debug(util.c(log_tag, "已连接涡轮机 #", turbine.get_device_idx(), " [", turbine.get_unit_id(), "@", turbine.get_session_id(), "]"))
_reset_dt(DT_KEYS.TurbineSteam .. turbine.get_device_idx())
_reset_dt(DT_KEYS.TurbinePower .. turbine.get_device_idx())
else
log.warning(util.c(log_tag, "拒绝涡轮机连接，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.add_boiler(boiler)
local fail_code, fail_str = svsessions.check_rtu_id(boiler, self.boilers, self.num_boilers)
local ok = fail_code == RTU_LINK_FAIL.OK
if ok then
table.insert(self.boilers, boiler)
log.debug(util.c(log_tag, "已连接锅炉 #", boiler.get_device_idx(), " [", boiler.get_unit_id(), "@", boiler.get_session_id(), "]"))
_reset_dt(DT_KEYS.BoilerWater .. boiler.get_device_idx())
_reset_dt(DT_KEYS.BoilerSteam .. boiler.get_device_idx())
_reset_dt(DT_KEYS.BoilerCCool .. boiler.get_device_idx())
_reset_dt(DT_KEYS.BoilerHCool .. boiler.get_device_idx())
else
log.warning(util.c(log_tag, "拒绝锅炉连接，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.add_tank(dynamic_tank)
local fail_code, fail_str = svsessions.check_rtu_id(dynamic_tank, self.tanks, 1)
local ok = fail_code == RTU_LINK_FAIL.OK
if self.tank_conn ~= 1 then
svsessions.report_rtu_mismatch(dynamic_tank)
log.warning(util.c(log_tag, "拒绝动态储罐：未配置为机组储罐"))
elseif ok then
table.insert(self.tanks, dynamic_tank)
log.debug(util.c(log_tag, "已连接动态储罐 [", dynamic_tank.get_unit_id(), "@", dynamic_tank.get_session_id(), "]"))
else
log.warning(util.c(log_tag, "拒绝动态储罐连接，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.add_sna(sna)
if config.CombinedWaste then
svsessions.report_rtu_mismatch(sna)
log.warning(util.c(log_tag, "拒绝 SNA 连接：已配置为设施综合废料"))
else
table.insert(self.snas, sna)
log.debug(util.c(log_tag, "已连接 SNA [", sna.get_unit_id(), "@", sna.get_session_id(), "]"))
end
return not config.CombinedWaste
end
function public.add_envd(envd)
local fail_code, fail_str = svsessions.check_rtu_id(envd, self.envd, 99)
local ok = fail_code == RTU_LINK_FAIL.OK
if ok then
table.insert(self.envd, envd)
log.debug(util.c(log_tag, "已连接环境探测器 #", envd.get_device_idx(), " [", envd.get_unit_id(), "@", envd.get_session_id(), "]"))
else
log.warning(util.c(log_tag, "拒绝环境探测器连接，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.purge_rtu_devices(session)
for _, v in pairs(self.rtu_list) do util.filter_table(v, function (s) return s.get_session_id() ~= session end) end
end
function public.update()
if self.plc_s ~= nil and not self.plc_s.open then
self.plc_s = nil
self.plc_i = nil
self.db.control.br100 = 0
end
for _, v in pairs(self.rtu_list) do util.filter_table(v, function (u) return u.is_connected() end) end
self.db.control.degraded = (#self.boilers ~= self.num_boilers) or (#self.turbines ~= self.num_turbines) or (self.plc_i == nil)
for i = 1, #self.boilers do
local sess = self.boilers[i]
local boiler = sess.get_db()
if sess.is_faulted() or not boiler.formed then
self.db.control.degraded = true
end
end
for i = 1, #self.turbines do
local sess = self.turbines[i]
local turbine = sess.get_db()
if sess.is_faulted() or not turbine.formed then
self.db.control.degraded = true
end
end
if self.plc_i ~= nil then
local now = util.time_ms()
local rps = self.plc_i.get_rps()
if rps.fault or rps.sys_fail then self.db.control.degraded = true end
if self.auto_engaged and not self.plc_i.is_auto_locked() then self.plc_i.auto_lock(true) end
if self.auto_idling and (((now - self.auto_idle_start) > IDLE_TIME) or not self.auto_idle) then
log.info(util.c(log_tag, "待机周期已完成"))
self.auto_idling = false
self.plc_i.auto_set_burn(0, false)
end
if self.plc_cache.active and ((now - self.last_rate_change_ms) > 2000) then
local db  = self.plc_i.get_db()
local rct = db.mek_status
if (not self.db.annunciator.CoolantLevelLow) and (rct.heating_rate > 0) then
local prod = rct.act_burn_rate * const.mek.JOULES_PER_MB
local loss = rct.env_loss * db.mek_struct.heat_cap
local heat = rct.heating_rate * util.trinary(self.num_boilers > 0, SODIUM_THERM_CONV, WATER_THERM_CONV)
local mismatch = math.abs(prod - (heat + loss)) > (const.ENERGY_MISMATCH_TOL * prod)
if mismatch and (rct.ccool_amnt > (1.1 * rct.heating_rate)) then
if self.energy_mismatch_start == nil then
self.energy_mismatch_start = now
elseif (now - self.energy_mismatch_start) > 3000 then
self.energy_mismatch = true
end
else
self.energy_mismatch_start = nil
self.energy_mismatch = false
end
end
end
end
_dt__compute_all()
unit_logic.update_annunciator(self)
unit_logic.update_alarms(self)
unit_logic.update_auto_mgmt(self, public)
unit_logic.update_status_text(self)
if #self.redstone > 0 then
unit_logic.handle_redstone(self)
elseif not self.plc_cache.rps_trip then
self.em_cool_opened = false
end
end
function public.auto_engage()
self.auto_engaged = true
if self.plc_i ~= nil then
log.debug(util.c(log_tag, "已启用自动控制"))
self.plc_i.auto_lock(true)
end
end
function public.auto_disengage()
self.auto_engaged = false
if self.plc_i ~= nil then
log.debug(util.c(log_tag, "已停用自动控制"))
self.plc_i.auto_lock(false)
self.db.control.br100 = 0
end
end
function public.auto_set_idle(idle)
if idle and not self.auto_idle then
self.auto_idling = false
self.auto_idle_start = 0
end
if idle ~= self.auto_idle then
log.debug(util.c(log_tag, "待机模式已更改为 ", idle))
end
self.auto_idle = idle
end
function public.auto_get_effective_limit()
local ctrl    = self.db.control
local eff_lim = ctrl.lim_br100
if (not ctrl.ready) or ctrl.degraded or self.plc_cache.rps_trip then
ctrl.br100 = 0
eff_lim = 0
end
return eff_lim
end
function public.auto_get_fuel_limited()
local eff_lim = public.auto_get_effective_limit()
if self.plc_i ~= nil then
local max = self.plc_i.get_db().reportable_max_burn
if max then
eff_lim = math.min(math.floor(max * 100), eff_lim)
end
eff_lim = math.min(self.auto_act_lim_br100, eff_lim)
end
return eff_lim
end
function public.auto_commit_br100(ramp)
if self.auto_engaged then
if self.plc_i ~= nil then
log.debug(util.c(log_tag, "提交燃烧速率百分值 ", self.db.control.br100, "，斜坡设置为 ", ramp))
local rate = self.db.control.br100 / 100
if self.auto_idle then
if rate <= IDLE_RATE then
ramp = false
if self.auto_idle_start == 0 then
self.auto_idling = true
self.auto_idle_start = util.time_ms()
log.info(util.c(log_tag, "开始以 ", IDLE_RATE, " mB/t 待机"))
rate = IDLE_RATE
elseif (util.time_ms() - self.auto_idle_start) > IDLE_TIME then
if self.auto_idling then
self.auto_idling = false
log.info(util.c(log_tag, "待机周期已完成"))
end
else
log.debug(util.c(log_tag, "继续以 ", IDLE_RATE, " mB/t 待机"))
rate = IDLE_RATE
end
else
self.auto_idling = false
self.auto_idle_start = 0
end
end
self.plc_i.auto_set_burn(rate, ramp)
end
end
end
function public.auto_ramp_complete()
if self.plc_i ~= nil then
return self.plc_i.is_ramp_complete() or
(self.plc_i.get_status().act_burn_rate == 0 and self.db.control.br100 == 0) or
public.auto_get_effective_limit() == 0
else return true end
end
function public.auto_scram()
if self.plc_s ~= nil then
self.db.control.br100 = 0
self.plc_s.in_queue.push_command(PLC_S_CMDS.ASCRAM)
end
end
function public.auto_cond_rps_reset()
if self.plc_s ~= nil and self.plc_i ~= nil and (not self.auto_was_alarmed) and (not self.em_cool_opened) then
local rps = self.plc_i.get_rps()
if rps.timeout or rps.automatic then
self.plc_i.auto_lock(true)
self.plc_s.in_queue.push_command(PLC_S_CMDS.RPS_AUTO_RESET)
end
end
end
function public.auto_set_waste(product)
if self.db.control.waste_mode == WASTE_MODE.AUTO then
self.waste_product = product
_set_waste_valves(product)
end
end
function public.disable()
if self.plc_s ~= nil then
self.plc_s.in_queue.push_command(PLC_S_CMDS.DISABLE)
end
end
function public.scram()
if self.plc_s ~= nil then
self.plc_s.in_queue.push_command(PLC_S_CMDS.SCRAM)
end
end
function public.cond_scram()
if self.plc_s ~= nil and not self.plc_cache.rps_status.manual then
self.plc_s.in_queue.push_command(PLC_S_CMDS.SCRAM)
end
end
function public.ack_all()
for id, state in pairs(self.db.alarm_states) do
if state == ALARM_STATE.TRIPPED then self.db.alarm_states[id] = ALARM_STATE.ACKED end
end
end
function public.ack_alarm(id)
if type(id) == "number" and self.db.alarm_states[id] == ALARM_STATE.TRIPPED then
self.db.alarm_states[id] = ALARM_STATE.ACKED
end
end
function public.reset_alarm(id)
if type(id) == "number" and self.db.alarm_states[id] == ALARM_STATE.RING_BACK then
self.db.alarm_states[id] = ALARM_STATE.INACTIVE
end
end
function public.set_waste_mode(mode)
self.db.control.waste_mode = mode
if mode == WASTE_MODE.MANUAL_PLUTONIUM then
_set_waste_valves(WASTE.PLUTONIUM)
elseif mode == WASTE_MODE.MANUAL_POLONIUM then
_set_waste_valves(WASTE.POLONIUM)
elseif mode == WASTE_MODE.MANUAL_ANTI_MATTER then
_set_waste_valves(WASTE.ANTI_MATTER)
elseif mode > WASTE_MODE.MANUAL_ANTI_MATTER then
log.debug(util.c(log_tag, "无效的废料处理模式设置 ", mode))
end
end
function public.set_burn_limit(limit)
if limit > 0 then
self.db.control.lim_br100 = math.floor(limit * 100)
if (self.plc_i ~= nil) and (type(self.plc_i.get_struct().max_burn) == "number") then
if limit > self.plc_i.get_struct().max_burn then
self.db.control.lim_br100 = math.floor(self.plc_i.get_struct().max_burn * 100)
end
end
end
end
function public.has_alarm_min_prio(min_prio)
for _, alarm in pairs(self.alarms) do
if alarm.tier <= min_prio and (alarm.state == AISTATE.TRIPPED or alarm.state == AISTATE.ACKED) then
return true
end
end
return false
end
function public.is_reactor_enabled()
if self.plc_i ~= nil then return self.plc_i.get_status().status else return false end
end
function public.is_safe_idle()
if self.plc_i == nil then return false end
if self.plc_i.get_status().status or self.plc_i.get_db().rps_tripped then return false end
for _, alarm in pairs(self.alarms) do
if not (alarm.state == AISTATE.INACTIVE or alarm.state == AISTATE.RING_BACK) then return false end
end
return true
end
function public.is_emer_cool_tripped() return self.em_cool_opened end
function public.has_energy_mismatch() return self.energy_mismatch end
function public.get_build(filter)
local all = filter == nil
local build = {}
if all or (filter == -1) then
if self.plc_i ~= nil then
build.reactor = self.plc_i.get_struct()
end
end
if all or (filter == RTU_UNIT_TYPE.BOILER_VALVE) then
build.boilers = {}
for i = 1, #self.boilers do
local boiler = self.boilers[i]
build.boilers[boiler.get_device_idx()] = { boiler.get_db().formed, boiler.get_db().build }
end
end
if all or (filter == RTU_UNIT_TYPE.TURBINE_VALVE) then
build.turbines = {}
for i = 1, #self.turbines do
local turbine = self.turbines[i]
build.turbines[turbine.get_device_idx()] = { turbine.get_db().formed, turbine.get_db().build }
end
end
if all or (filter == RTU_UNIT_TYPE.DYNAMIC_VALVE) then
build.tanks = {}
for i = 1, #self.tanks do
local tank = self.tanks[i]
build.tanks[tank.get_device_idx()] = { tank.get_db().formed, tank.get_db().build }
end
end
return build
end
function public.get_reactor_status()
local status = {}
if self.plc_i ~= nil then
status = { self.plc_i.get_status(), self.plc_i.get_rps(), self.plc_i.get_general_status() }
end
return status
end
function public.get_burn_rate()
local rate = 0
if self.plc_i ~= nil then rate = self.plc_i.get_status().act_burn_rate end
return rate or 0
end
function public.check_rtu_conns()
local conns = {}
conns.boilers = {}
for i = 1, #self.boilers do
conns.boilers[self.boilers[i].get_device_idx()] = true
end
conns.turbines = {}
for i = 1, #self.turbines do
conns.turbines[self.turbines[i].get_device_idx()] = true
end
conns.tanks = {}
for i = 1, #self.tanks do
conns.tanks[self.tanks[i].get_device_idx()] = true
end
return conns
end
function public.get_rtu_statuses()
local status = {}
status.boilers = {}
for i = 1, #self.boilers do
local boiler = self.boilers[i]
local db = boiler.get_db()
status.boilers[boiler.get_device_idx()] = { boiler.is_faulted(), db.formed, db.state, db.tanks }
end
status.turbines = {}
for i = 1, #self.turbines do
local turbine = self.turbines[i]
local db = turbine.get_db()
status.turbines[turbine.get_device_idx()] = { turbine.is_faulted(), db.formed, db.state, db.tanks }
end
status.tanks = {}
for i = 1, #self.tanks do
local tank = self.tanks[i]
local db = tank.get_db()
status.tanks[tank.get_device_idx()] = { tank.is_faulted(), db.formed, db.state, db.tanks }
end
local total_peak, total_avail, total_out = 0, 0, 0
for i = 1, #self.snas do
local db = self.snas[i].get_db()
local in_a, out_a, prod = db.tanks.input.amount, db.tanks.output.amount, db.state.production_rate
total_peak = total_peak + db.state.peak_production
total_avail = total_avail + prod
local out_from_in = util.trinary(in_a >= po_prod_ratio, in_a / po_prod_ratio, 0)
local out_rate_appx = util.trinary(out_a > 0, math.min(out_from_in, out_a), out_from_in)
total_out = total_out + math.min(out_rate_appx, prod)
end
if not config.UseSNAStatistics then
total_out = util.trinary(self.waste_product == WASTE.PLUTONIUM, 0, public.get_burn_rate() / po_prod_ratio)
end
status.sna = { #self.snas, total_peak, total_avail, total_out }
status.envds = {}
for i = 1, #self.envd do
local envd = self.envd[i]
local db = envd.get_db()
status.envds[envd.get_device_idx()] = { envd.is_faulted(), db.radiation, db.radiation_raw }
end
return status
end
function public.get_sna_status()
local total_avail_rate, near_full, low_fill = 0, true, false
for i = 1, #self.snas do
local db = self.snas[i].get_db()
total_avail_rate = total_avail_rate + db.state.production_rate
near_full = near_full and (db.tanks.input_need <= db.state.production_rate)
low_fill = low_fill or (db.tanks.input_fill < 0.15)
end
return total_avail_rate, near_full, low_fill
end
function public.get_generation_rate()
local sum = 0
for i = 1, #self.turbines do
sum = sum + self.turbines[i].get_db().state.prod_rate
end
return sum
end
function public.get_annunciator() return self.db.annunciator end
function public.get_alarms() return self.db.alarm_states end
function public.get_control_inf() return self.db.control end
function public.get_state()
return {
self.status_text[1],
self.status_text[2],
self.db.control.ready,
self.db.control.degraded,
self.db.control.waste_mode,
self.waste_product,
self.last_rate_change_ms,
self.turbine_flow_stable,
self.fuel_burn_rate_limited
}
end
function public.get_valves()
local v = self.valves
return {
v.waste_pu.check(),
v.waste_sna.check(),
v.waste_po.check(),
v.waste_sps.check(),
v.emer_cool.check(),
v.aux_cool.check()
}
end
function public.get_id() return self.r_id end
return public
end
return unit
