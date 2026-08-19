local const      = require("scada-common.constants")
local log        = require("scada-common.log")
local rsio       = require("scada-common.rsio")
local types      = require("scada-common.types")
local util       = require("scada-common.util")
local alarm_ctl  = require("supervisor.alarm_ctl")
local unit       = require("supervisor.unit")
local fac_update = require("supervisor.facility_update")
local rsctl      = require("supervisor.session.rsctl")
local svsessions = require("supervisor.session.svsessions")
local AISTATE = alarm_ctl.AISTATE
local ALARM         = types.ALARM
local ALARM_STATE   = types.ALARM_STATE
local AUTO_GROUP    = types.AUTO_GROUP
local PRIO          = types.ALARM_PRIORITY
local PROCESS       = types.PROCESS
local RTU_LINK_FAIL = types.RTU_LINK_FAIL
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local WASTE         = types.WASTE_PRODUCT
local IO = rsio.IO
local AUTO_SCRAM = {
NONE = 0,
ESS_FAULT = 1,
ESS_FILL = 2,
CRIT_ALARM = 3,
RADIATION = 4,
GEN_FAULT = 5
}
local START_STATUS = {
OK = 0,
NO_UNITS = 1,
BLADE_MISMATCH = 2
}
local RCV_STATE = {
INACTIVE = 0,
PRIMED = 1,
RUNNING = 2,
STOPPED = 3
}
local CHARGE_SCALER = 1000000
local GEN_SCALER    = 1000
local facility = {}
function facility.new(config)
local self = {
units = {},
types = { AUTO_SCRAM = AUTO_SCRAM, START_STATUS = START_STATUS, RCV_STATE = RCV_STATE },
status_text = { "启动", "初始化..." },
all_sys_ok = false,
allow_testing = false,
cooling_conf = {
r_cool = config.CoolingConfig,
fac_tank_mode = config.FacilityTankMode,
fac_tank_defs = config.FacilityTankDefs,
fac_tank_list = config.FacilityTankList,
fac_tank_conns = config.FacilityTankConns,
tank_fluid_types = config.TankFluidTypes,
aux_coolant = config.AuxiliaryCoolant
},
rtu_gw_conn_count = 0,
rtu_list = {},
redstone = {},
induction = {},
ecore = {},
snas = {},
sps = {},
tanks = {},
envd = {},
io_ctl = nil,
recovery = RCV_STATE.INACTIVE,
recovery_boot_state = nil,
last_unit_states = {},
units_ready = false,
mode = PROCESS.INACTIVE,
last_mode = PROCESS.INACTIVE,
return_mode = PROCESS.INACTIVE,
mode_set = PROCESS.MAX_BURN,
start_fail = START_STATUS.OK,
max_burn_combined = 0.0,
sp = {
burn_target = 0.1,
range_start = 10,
range_stop = 90,
charge_setpoint = 0,
gen_rate_setpoint = 0
},
group_map = {},
prio_defs = { {}, {}, {}, {} },
at_max_burn = false,
ascram = false,
ascram_reason = AUTO_SCRAM.NONE,
ascram_status = {
ess_fault = false,
ess_fill = false,
crit_alarm = false,
radiation = false,
gen_fault = false
},
energy_mismatch = false,
turbine_gen_rate = 0.0,
charge_conversion = const.mek.STANDARD_FE_PER_MB,
ref_P_scaler = 1.0,
ref_D_scaler = 1.0,
time_start = 0.0,
initial_ramp = true,
waiting_on_ramp = false,
waiting_on_stable = false,
range_control_en = false,
charge_control_open = nil,
feedforward = 0.0,
accumulator = 0.0,
saturated = false,
last_update = 0,
last_error = 0.0,
last_time = 0.0,
waste_product = WASTE.PLUTONIUM,
current_waste_product = WASTE.PLUTONIUM,
po_prod_ratio = config.MekanismWasteToPo[1] / config.MekanismWasteToPo[2],
pu_fallback = false,
pu_fallback_active = false,
pu_fallback_times = { [0] = 0 },
sps_low_power = false,
disabled_sps = false,
tone_states = {},
test_tone_set = false,
test_tone_reset = false,
test_tone_states = {},
test_alarm_states = {},
ess_stat_init = false,
ess_percent = 0.0,
avg_charge = util.ema_filter(0.2857),
avg_inflow = util.ema_filter(0.2857),
avg_outflow = util.ema_filter(0.2857),
avg_net = util.ema_filter(0.075),
ess_last_capacity = 0,
ess_last_charge = 0,
ess_last_charge_t = 0,
ess_faulted_times = { 0, 0, 0 },
alarms = {
FacilityRadiation = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.FacilityRadiation, tier = PRIO.CRITICAL },
},
alarm_states = {
[ALARM.FacilityRadiation] = ALARM_STATE.INACTIVE
}
}
local f_update = fac_update(self)
for i = 1, config.UnitCount do
table.insert(self.units, unit.new(i, self.cooling_conf, self.po_prod_ratio, config))
table.insert(self.group_map, AUTO_GROUP.MANUAL)
table.insert(self.last_unit_states, false)
table.insert(self.pu_fallback_times, 0)
end
self.rtu_list = { self.redstone, self.induction, self.ecore, self.snas, self.sps, self.tanks, self.envd }
self.io_ctl = rsctl.new(self.redstone, 0)
for _ = 1, 12 do table.insert(self.test_alarm_states, false) end
for _ = 1, 8 do
table.insert(self.tone_states, false)
table.insert(self.test_tone_states, false)
end
settings.set("LastProcessState", PROCESS.INACTIVE)
settings.set("LastUnitStates", self.last_unit_states)
if not settings.save("/supervisor.settings") then
log.warning("FAC: 无法将初始控制状态保存到监控端设置文件")
end
local waste_pu  = self.io_ctl.as_valve(IO.F_WASTE_PU)
local waste_sna = self.io_ctl.as_valve(IO.F_WASTE_PO)
local waste_po  = self.io_ctl.as_valve(IO.F_WASTE_POPL)
local waste_sps = self.io_ctl.as_valve(IO.F_WASTE_AM)
self.valves = {
waste_pu = waste_pu,
waste_sna = waste_sna,
waste_po = waste_po,
waste_sps = waste_sps
}
local function _auto_check_and_save(auto_cfg)
local ready = false
local limits = {}
for i = 1, config.UnitCount do
limits[i] = self.units[i].get_control_inf().lim_br100 * 100
end
if self.mode == PROCESS.INACTIVE then
if (type(auto_cfg.mode) == "number") and (auto_cfg.mode > PROCESS.INACTIVE) and (auto_cfg.mode <= PROCESS.RANGE_CONTROL) then
self.mode_set = auto_cfg.mode
end
ready = self.mode_set > 0
if (type(auto_cfg.burn_target) == "number") and auto_cfg.burn_target >= 0.1 then
self.sp.burn_target = auto_cfg.burn_target
elseif self.mode_set == PROCESS.BURN_RATE then ready = false end
if (type(auto_cfg.range_start) == "number") and (auto_cfg.range_start >= 0) and (auto_cfg.range_start < 100) then
self.sp.range_start = auto_cfg.range_start
elseif self.mode_set == PROCESS.RANGE_CONTROL then ready = false end
if (type(auto_cfg.range_stop) == "number") and (auto_cfg.range_stop <= 100) and (auto_cfg.range_stop > auto_cfg.range_start) then
self.sp.range_stop = auto_cfg.range_stop
elseif self.mode_set == PROCESS.RANGE_CONTROL then ready = false end
if (type(auto_cfg.charge_target) == "number") and auto_cfg.charge_target >= 0 then
self.sp.charge_setpoint = auto_cfg.charge_target * CHARGE_SCALER
elseif self.mode_set == PROCESS.CHARGE then ready = false end
if (type(auto_cfg.gen_target) == "number") and auto_cfg.gen_target >= 0 then
self.sp.gen_rate_setpoint = auto_cfg.gen_target * GEN_SCALER
elseif self.mode_set == PROCESS.GEN_RATE then ready = false end
if (type(auto_cfg.limits) == "table") and (#auto_cfg.limits == config.UnitCount) then
for i = 1, config.UnitCount do
local limit = auto_cfg.limits[i]
if (type(limit) == "number") and (limit >= 0.1) then
limits[i] = limit
self.units[i].set_burn_limit(limit)
end
end
end
end
return ready, limits
end
local public = {}
function public.add_redstone(rs_unit) table.insert(self.redstone, rs_unit) end
function public.add_imatrix(imatrix)
local fail_code, fail_str = svsessions.check_rtu_id(imatrix, self.induction, 1)
local ok = fail_code == RTU_LINK_FAIL.OK
if config.EnergyStorageSystem ~= types.ESS.INDUCTION_MATRIX or #self.ecore > 0 then
svsessions.report_rtu_mismatch(imatrix)
log.warning(util.c("FAC: 拒绝链接感应矩阵，因其配置为能量核心或已含能量核心"))
elseif ok then
table.insert(self.induction, imatrix)
log.debug(util.c("FAC: 已链接感应矩阵 [", imatrix.get_unit_id(), "@", imatrix.get_session_id(), "]"))
else
log.warning(util.c("FAC: 拒绝链接感应矩阵，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.add_ecore(ecore)
local fail_code, fail_str = svsessions.check_rtu_id(ecore, self.ecore, 1)
local ok = fail_code == RTU_LINK_FAIL.OK
if config.EnergyStorageSystem ~= types.ESS.ENERGY_CORE or #self.induction > 0 then
svsessions.report_rtu_mismatch(ecore)
log.warning(util.c("FAC: 拒绝链接能量核心，因其配置为感应矩阵或已含感应矩阵"))
elseif ok then
table.insert(self.ecore, ecore)
log.debug(util.c("FAC: 已链接能量核心 [", ecore.get_unit_id(), "@", ecore.get_session_id(), "]"))
else
log.warning(util.c("FAC: 拒绝链接能量核心，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.add_sna(sna)
if config.CombinedWaste then
table.insert(self.snas, sna)
log.debug(util.c("FAC: 已链接 SNA [", sna.get_unit_id(), "@", sna.get_session_id(), "]"))
else
svsessions.report_rtu_mismatch(sna)
log.warning(util.c("FAC: 拒绝链接 SNA，因其未配置为设施综合废料"))
end
return config.CombinedWaste
end
function public.add_sps(sps)
local fail_code, fail_str = svsessions.check_rtu_id(sps, self.sps, 1)
local ok = fail_code == RTU_LINK_FAIL.OK
if ok then
table.insert(self.sps, sps)
log.debug(util.c("FAC: 已链接 SPS [", sps.get_unit_id(), "@", sps.get_session_id(), "]"))
else
log.warning(util.c("FAC: 拒绝链接 SPS，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.add_tank(dynamic_tank)
local fail_code, fail_str = svsessions.check_rtu_id(dynamic_tank, self.tanks, #self.cooling_conf.fac_tank_list)
local ok = fail_code == RTU_LINK_FAIL.OK
if self.cooling_conf.fac_tank_mode == 0 then
svsessions.report_rtu_mismatch(dynamic_tank)
log.warning("FAC: 拒绝链接动态储罐，因其未配置为设施储罐")
elseif ok then
table.insert(self.tanks, dynamic_tank)
log.debug(util.c("FAC: 已链接动态储罐 #", dynamic_tank.get_device_idx(), " [", dynamic_tank.get_unit_id(), "@", dynamic_tank.get_session_id(), "]"))
else
log.warning(util.c("FAC: 拒绝链接动态储罐，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.add_envd(envd)
local fail_code, fail_str = svsessions.check_rtu_id(envd, self.envd, 99)
local ok = fail_code == RTU_LINK_FAIL.OK
if ok then
table.insert(self.envd, envd)
log.debug(util.c("FAC: 已链接环境探测器 #", envd.get_device_idx(), " [", envd.get_unit_id(), "@", envd.get_session_id(), "]"))
else
log.warning(util.c("FAC: 拒绝链接环境探测器，失败代码 ", fail_code, " (", fail_str, ")"))
end
return ok
end
function public.purge_rtu_devices(session)
for _, v in pairs(self.rtu_list) do util.filter_table(v, function (s) return s.get_session_id() ~= session end) end
end
function public.update()
f_update.boot_recovery()
f_update.pre_auto()
f_update.auto_control(config.ExtChargeIdling)
f_update.auto_safety()
f_update.post_auto()
f_update.redstone(public.ack_all)
f_update.waste_mgmt(config.CombinedWaste, public)
f_update.unit_mgmt(config.CombinedWaste)
f_update.update_alarms()
f_update.alarm_audio()
end
function public.update_units()
self.energy_mismatch = false
for i = 1, #self.units do
local u = self.units[i]
u.update()
if u.has_energy_mismatch() then
self.energy_mismatch = true
end
end
end
function public.clear_boot_state()
settings.unset("LastProcessState")
settings.unset("LastUnitStates")
if not settings.save("/supervisor.settings") then
log.warning("facility.clear_boot_state(): 无法保存监控端设置文件")
else
log.debug("FAC: 退出时已清除启动状态")
end
end
function public.boot_recovery_init(state)
if self.recovery == RCV_STATE.INACTIVE and state then
self.recovery_boot_state = state
self.recovery = RCV_STATE.PRIMED
log.info("FAC: 启动恢复就绪")
end
end
function public.boot_recovery_start(auto_cfg)
if self.recovery == RCV_STATE.PRIMED then
self.recovery = util.trinary(_auto_check_and_save(auto_cfg), RCV_STATE.RUNNING, RCV_STATE.STOPPED)
log.info(util.c("FAC: 启动恢复 ", util.trinary(self.recovery == RCV_STATE.RUNNING, "已启动", "失败")))
else self.recovery = RCV_STATE.STOPPED end
end
function public.cancel_recovery()
if self.recovery == RCV_STATE.RUNNING then
self.recovery = RCV_STATE.STOPPED
self.recovery_boot_state = nil
log.info("FAC: 启动恢复已被用户操作取消")
end
end
function public.scram_all()
for i = 1, #self.units do
self.units[i].scram()
end
end
function public.ack_all()
for i = 1, #self.units do self.units[i].ack_all() end
for id, state in pairs(self.alarm_states) do
if state == ALARM_STATE.TRIPPED then self.alarm_states[id] = ALARM_STATE.ACKED end
end
end
function public.auto_is_active() return self.mode ~= PROCESS.INACTIVE end
function public.auto_stop() self.mode = PROCESS.INACTIVE end
function public.auto_start(auto_cfg)
local ready, limits = _auto_check_and_save(auto_cfg)
if ready and self.units_ready then
self.mode = self.mode_set
end
log.debug(util.c("FAC: 进程启动 ", util.trinary(ready, "已接受", "已拒绝")))
return {
ready,
self.mode_set,
self.sp.burn_target,
self.sp.range_start,
self.sp.range_stop,
self.sp.charge_setpoint / CHARGE_SCALER,
self.sp.gen_rate_setpoint / GEN_SCALER,
limits
}
end
function public.set_group(unit_id, group)
if (group >= AUTO_GROUP.MANUAL and group <= AUTO_GROUP.BACKUP) and (unit_id > 0 and unit_id <= config.UnitCount) and self.mode == PROCESS.INACTIVE then
local old_group = self.group_map[unit_id]
if old_group ~= AUTO_GROUP.MANUAL then
util.filter_table(self.prio_defs[old_group], function (u) return u.get_id() ~= unit_id end)
end
self.group_map[unit_id] = group
if group > AUTO_GROUP.MANUAL then
table.insert(self.prio_defs[group], self.units[unit_id])
end
end
end
function public.get_group(unit_id) return self.group_map[unit_id] end
function public.set_waste_product(product)
if product == WASTE.PLUTONIUM or product == WASTE.POLONIUM or product == WASTE.ANTI_MATTER then
self.waste_product = product
end
return self.waste_product
end
function public.set_pu_fallback(enabled)
self.pu_fallback = enabled == true
return self.pu_fallback
end
function public.set_sps_low_power(enabled)
self.sps_low_power = enabled == true
return self.sps_low_power
end
function public.diag_set_test_tone(id, state)
if self.allow_testing then
self.test_tone_set = true
self.test_tone_reset = false
if id == 0 then
for i = 1, #self.test_tone_states do self.test_tone_states[i] = false end
else
self.test_tone_states[id] = state
end
end
return self.allow_testing, self.test_tone_states
end
function public.diag_set_test_alarm(id, state)
if self.allow_testing then
self.test_tone_set = true
self.test_tone_reset = false
if id == 0 then
for i = 1, #self.test_alarm_states do self.test_alarm_states[i] = false end
else
self.test_alarm_states[id] = state
end
end
return self.allow_testing, self.test_alarm_states
end
function public.has_energy_mismatch() return self.energy_mismatch end
function public.get_alarm_tones() return self.tone_states end
function public.get_build(type)
local all = type == nil
local build = {}
if all or type == RTU_UNIT_TYPE.IMATRIX then
build.induction = {}
for i = 1, #self.induction do
local db = self.induction[i].get_db()
build.induction[i] = { db.formed, db.build }
end
end
if all or type == RTU_UNIT_TYPE.ENERGY_CORE then
build.ecore = {}
for i = 1, #self.ecore do
local db = self.ecore[i].get_db()
build.ecore[i] = { db.formed, db.build }
end
end
if all or type == RTU_UNIT_TYPE.SPS then
build.sps = {}
for i = 1, #self.sps do
local db = self.sps[i].get_db()
build.sps[i] = { db.formed, db.build }
end
end
if all or type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
build.tanks = {}
for i = 1, #self.tanks do
local tank = self.tanks[i]
build.tanks[tank.get_device_idx()] = { tank.get_db().formed, tank.get_db().build }
end
end
return build
end
function public.get_control_status()
local astat = self.ascram_status
return {
self.all_sys_ok,
self.units_ready,
self.mode,
self.waiting_on_ramp or self.waiting_on_stable,
self.at_max_burn or self.saturated,
self.turbine_gen_rate,
self.ascram,
astat.ess_fault,
astat.ess_fill,
astat.crit_alarm,
astat.radiation,
astat.gen_fault or self.mode == PROCESS.GEN_RATE_FAULT_IDLE,
self.energy_mismatch,
self.status_text[1],
self.status_text[2],
self.group_map,
self.current_waste_product,
self.pu_fallback_active,
self.disabled_sps
}
end
function public.check_rtu_conns()
local conns = {}
conns.ess = (#self.induction > 0) or (#self.ecore > 0)
conns.sps = #self.sps > 0
conns.tanks = {}
for i = 1, #self.tanks do
conns.tanks[self.tanks[i].get_device_idx()] = true
end
return conns
end
function public.get_rtu_statuses()
local status = {}
status.count = self.rtu_gw_conn_count
status.power = {
self.avg_charge.get(),
self.avg_inflow.get(),
self.avg_outflow.get(),
0
}
status.induction = {}
for i = 1, #self.induction do
local matrix = self.induction[i]
local db = matrix.get_db()
status.induction[i] = { matrix.is_faulted(), db.formed, db.state, db.tanks }
local fe_per_ms = self.avg_net.get()
if fe_per_ms ~= 0 then
local remaining = util.joules_to_fe_rf(util.trinary(fe_per_ms > 0, db.tanks.energy_need, db.tanks.energy))
status.power[4] = remaining / fe_per_ms
end
end
status.ecore = {}
for i = 1, #self.ecore do
local ecore = self.ecore[i]
local db = ecore.get_db()
status.ecore[i] = { ecore.is_faulted(), db.formed, db.state, db.virtual }
local fe_per_ms = self.avg_net.get()
if fe_per_ms ~= 0 then
local remaining = util.trinary(fe_per_ms > 0, db.virtual.energy_need, db.state.energy)
status.power[4] = remaining / fe_per_ms
end
end
if config.CombinedWaste then
local total_peak, total_avail, total_out = 0, 0, 0
for i = 1, #self.snas do
local db = self.snas[i].get_db()
local in_a, out_a, prod = db.tanks.input.amount, db.tanks.output.amount, db.state.production_rate
total_peak = total_peak + db.state.peak_production
total_avail = total_avail + prod
local out_from_in = util.trinary(in_a >= self.po_prod_ratio, in_a / self.po_prod_ratio, 0)
local out_rate_appx = util.trinary(out_a > 0, math.min(out_from_in, out_a), out_from_in)
total_out = total_out + math.min(out_rate_appx, prod)
end
if not config.UseSNAStatistics then
local burn_sum = 0
for i = 1, #self.units do
burn_sum = burn_sum + self.units[i].get_burn_rate()
end
total_out = util.trinary(self.waste_product == WASTE.PLUTONIUM, 0, burn_sum / self.po_prod_ratio)
end
status.sna = { #self.snas, total_peak, total_avail, total_out }
end
status.sps = {}
for i = 1, #self.sps do
local sps = self.sps[i]
local db = sps.get_db()
status.sps[i] = { sps.is_faulted(), db.formed, db.state, db.tanks }
end
status.tanks = {}
for i = 1, #self.tanks do
local tank = self.tanks[i]
local db = tank.get_db()
status.tanks[tank.get_device_idx()] = { tank.is_faulted(), db.formed, db.state, db.tanks }
end
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
function public.get_valves()
if not config.CombinedWaste then return nil end
local v = self.valves
return {
v.waste_pu.check(),
v.waste_sna.check(),
v.waste_po.check(),
v.waste_sps.check()
}
end
function public.report_rtu_gateways(sessions) self.rtu_gw_conn_count = #sessions end
function public.get_cooling_conf() return self.cooling_conf end
function public.get_units() return self.units end
return public
end
return facility
