
local psil    = require("scada-common.psil")
local types   = require("scada-common.types")
local util    = require("scada-common.util")
local iorx    = require("pocket.iorx")
local process = require("pocket.process")
local ALARM = types.ALARM
local ALARM_STATE = types.ALARM_STATE
local ENERGY_SCALE = types.ENERGY_SCALE
local ENERGY_UNITS = types.ENERGY_SCALE_UNITS
local TEMP_SCALE = types.TEMP_SCALE
local TEMP_UNITS = types.TEMP_SCALE_UNITS
local WARN_TT = 40
local HIGH_TT = 80
local ioctl = {}
local LINK_STATE = {
UNLINKED = 0,
SV_LINK_ONLY = 1,
API_LINK_ONLY = 2,
LINKED = 3
}
ioctl.LINK_STATE = LINK_STATE
local io = {
version = "unknown",
ps = psil.create(),
loader_require = { sv = false, api = false }
}
local config = nil
local comms  = nil
function ioctl.init_core(pkt_comms, nav, cfg)
comms = pkt_comms
config = cfg
ioctl.rx = iorx(io)
io.nav = nav
io.diag = {}
io.diag.tone_test = {
test_1 = function (state) comms.diag__set_alarm_tone(1, state) end,
test_2 = function (state) comms.diag__set_alarm_tone(2, state) end,
test_3 = function (state) comms.diag__set_alarm_tone(3, state) end,
test_4 = function (state) comms.diag__set_alarm_tone(4, state) end,
test_5 = function (state) comms.diag__set_alarm_tone(5, state) end,
test_6 = function (state) comms.diag__set_alarm_tone(6, state) end,
test_7 = function (state) comms.diag__set_alarm_tone(7, state) end,
test_8 = function (state) comms.diag__set_alarm_tone(8, state) end,
stop_tones = function () comms.diag__set_alarm_tone(0, false) end,
test_breach = function (state) comms.diag__set_alarm(ALARM.ContainmentBreach, state) end,
test_rad = function (state) comms.diag__set_alarm(ALARM.ContainmentRadiation, state) end,
test_lost = function (state) comms.diag__set_alarm(ALARM.ReactorLost, state) end,
test_crit = function (state) comms.diag__set_alarm(ALARM.CriticalDamage, state) end,
test_dmg = function (state) comms.diag__set_alarm(ALARM.ReactorDamage, state) end,
test_overtemp = function (state) comms.diag__set_alarm(ALARM.ReactorOverTemp, state) end,
test_hightemp = function (state) comms.diag__set_alarm(ALARM.ReactorHighTemp, state) end,
test_wasteleak = function (state) comms.diag__set_alarm(ALARM.ReactorWasteLeak, state) end,
test_highwaste = function (state) comms.diag__set_alarm(ALARM.ReactorHighWaste, state) end,
test_rps = function (state) comms.diag__set_alarm(ALARM.RPSTransient, state) end,
test_rcs = function (state) comms.diag__set_alarm(ALARM.RCSTransient, state) end,
test_turbinet = function (state) comms.diag__set_alarm(ALARM.TurbineTrip, state) end,
stop_alarms = function () comms.diag__set_alarm(0, false) end,
get_tone_states = function () comms.diag__get_alarm_tones() end,
tone_buttons = {},
alarm_buttons = {}
}
io.diag.get_comps = function () comms.diag__get_computers() end
io.api = {
get_fac = function () comms.api__get_facility() end,
get_unit = function (unit) comms.api__get_unit(unit) end,
get_ctrl = function () comms.api__get_control() end,
get_proc = function () comms.api__get_process() end,
get_waste = function () comms.api__get_waste() end,
get_rad = function () comms.api__get_rad() end
}
end
function ioctl.init_fac(conf)
local temp_scale, energy_scale = config.TempScale, config.EnergyScale
io.temp_label = TEMP_UNITS[temp_scale]
io.energy_label = ENERGY_UNITS[energy_scale]
if temp_scale == TEMP_SCALE.CELSIUS then
io.temp_convert = function (t) return t - 273.15 end
elseif temp_scale == TEMP_SCALE.FAHRENHEIT then
io.temp_convert = function (t) return (1.8 * (t - 273.15)) + 32 end
elseif temp_scale == TEMP_SCALE.RANKINE then
io.temp_convert = function (t) return 1.8 * t end
else
io.temp_label = "K"
io.temp_convert = function (t) return t end
end
if energy_scale == ENERGY_SCALE.FE or energy_scale == ENERGY_SCALE.RF then
io.energy_convert = util.joules_to_fe_rf
io.energy_convert_from_fe = function (t) return t end
io.energy_convert_to_fe = function (t) return t end
else
io.energy_label = "J"
io.energy_convert = function (t) return t end
io.energy_convert_from_fe = util.fe_rf_to_joules
io.energy_convert_to_fe = util.joules_to_fe_rf
end
io.facility = {
num_units = conf.num_units,
tank_mode = conf.cooling.fac_tank_mode,
tank_defs = conf.cooling.fac_tank_defs,
tank_list = conf.cooling.fac_tank_list,
tank_conns = conf.cooling.fac_tank_conns,
tank_fluid_types = conf.cooling.tank_fluid_types,
combined_waste = conf.com_waste,
ess_type = conf.ess,
all_sys_ok = false,
rtu_count = 0,
status_lines = { "", "" },
auto_ready = false,
auto_active = false,
auto_ramping = false,
auto_saturated = false,
auto_scram = false,
ascram_status = {
ess_fault = false,
ess_fill = false,
crit_alarm = false,
radiation = false,
gen_fault = false
},
auto_current_waste_product = types.WASTE_PRODUCT.PLUTONIUM,
auto_pu_fallback_active = false,
auto_sps_disabled = false,
waste_stats = { 0, 0, 0, 0, 0, 0 },
num_snas = 0,
sna_peak_rate_in = 0.0,
sna_peak_rate_out = 0.0,
sna_max_rate_in = 0.0,
sna_max_rate_out = 0.0,
sna_in_rate = 0.0,
sna_out_rate = 0.0,
radiation = types.new_zero_radiation_reading(),
start_ack = nil,
stop_ack = nil,
scram_ack = nil,
ack_alarms_ack = nil,
ps = psil.create(),
induction_ps_tbl = {},
induction_data_tbl = {},
ecore_ps_tbl = {},
ecore_data_tbl = {},
sps_ps_tbl = {},
sps_data_tbl = {},
tank_ps_tbl = {},
tank_data_tbl = {},
rad_monitors = {}
}
table.insert(io.facility.induction_ps_tbl, psil.create())
table.insert(io.facility.induction_data_tbl, {})
table.insert(io.facility.ecore_ps_tbl, psil.create())
table.insert(io.facility.ecore_data_tbl, {})
table.insert(io.facility.sps_ps_tbl, psil.create())
table.insert(io.facility.sps_data_tbl, {})
for i = 1, #io.facility.tank_list do
if io.facility.tank_list[i] == 2 then
table.insert(io.facility.tank_ps_tbl, psil.create())
table.insert(io.facility.tank_data_tbl, {})
end
end
io.units = {}
for i = 1, conf.num_units do
local entry = {
unit_id = i,
connected = false,
num_boilers = 0,
num_turbines = 0,
num_snas = 0,
has_tank = conf.cooling.r_cool[i].TankConnection,
status_lines = { "", "" },
auto_ready = false,
auto_degraded = false,
control_state = false,
burn_rate_cmd = 0.0,
radiation = types.new_zero_radiation_reading(),
sna_peak_rate_in = 0.0,
sna_peak_rate_out = 0.0,
sna_max_rate_in = 0.0,
sna_max_rate_out = 0.0,
sna_in_rate = 0.0,
sna_out_rate = 0.0,
waste_mode = types.WASTE_MODE.MANUAL_PLUTONIUM,
waste_product = types.WASTE_PRODUCT.PLUTONIUM,
last_rate_change_ms = 0,
turbine_flow_stable = false,
fuel_burn_rate_limited = false,
waste_stats = { 0, 0, 0 },
a_group = types.AUTO_GROUP.MANUAL,
start = function () process.start(i) end,
scram = function () process.scram(i) end,
reset_rps = function () process.reset_rps(i) end,
ack_alarms = function () process.ack_all_alarms(i) end,
set_burn = function (rate) process.set_rate(i, rate) end,
start_ack = nil,
scram_ack = nil,
reset_rps_ack = nil,
ack_alarms_ack = nil,
alarms = { ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE },
annunciator = {},
unit_ps = psil.create(),
reactor_data = types.new_reactor_db(),
boiler_ps_tbl = {},
boiler_data_tbl = {},
turbine_ps_tbl = {},
turbine_data_tbl = {},
tank_ps_tbl = {},
tank_data_tbl = {},
rad_monitors = {}
}
if io.facility.tank_mode ~= 0 then
entry.has_tank = conf.cooling.fac_tank_defs[i] > 0
end
for _ = 1, conf.cooling.r_cool[i].BoilerCount do
table.insert(entry.boiler_ps_tbl, psil.create())
table.insert(entry.boiler_data_tbl, {})
end
for _ = 1, conf.cooling.r_cool[i].TurbineCount do
table.insert(entry.turbine_ps_tbl, psil.create())
table.insert(entry.turbine_data_tbl, {})
end
if io.facility.tank_defs[i] == 1 then
table.insert(entry.tank_ps_tbl, psil.create())
table.insert(entry.tank_data_tbl, {})
end
entry.num_boilers = #entry.boiler_data_tbl
entry.num_turbines = #entry.turbine_data_tbl
table.insert(io.units, entry)
end
process.init(io, comms)
end
function ioctl.report_link_state(state, sv_addr, api_addr)
io.ps.publish("link_state", state)
if state == LINK_STATE.API_LINK_ONLY or state == LINK_STATE.UNLINKED then
io.ps.publish("svr_conn_quality", 0)
end
if state == LINK_STATE.SV_LINK_ONLY or state == LINK_STATE.UNLINKED then
io.ps.publish("crd_conn_quality", 0)
end
if sv_addr then
io.ps.publish("sv_addr", util.c(sv_addr, ":", config.SVR_Channel))
elseif sv_addr == false then
io.ps.publish("sv_addr", "unknown (not linked)")
end
if api_addr then
io.ps.publish("api_addr", util.c(api_addr, ":", config.CRD_Channel))
elseif api_addr == false then
io.ps.publish("api_addr", "unknown (not linked)")
end
end
function ioctl.report_svr_link_error(msg) io.ps.publish("svr_link_msg", msg) end
function ioctl.report_crd_link_error(msg) io.ps.publish("api_link_msg", msg) end
function ioctl.report_svr_tt(trip_time)
local state = 3
if trip_time > HIGH_TT then
state = 1
elseif trip_time > WARN_TT then
state = 2
end
io.ps.publish("svr_conn_quality", state)
end
function ioctl.report_crd_tt(trip_time)
local state = 3
if trip_time > HIGH_TT then
state = 1
elseif trip_time > WARN_TT then
state = 2
end
io.ps.publish("crd_conn_quality", state)
end
function ioctl.get_db() return io end
return ioctl
