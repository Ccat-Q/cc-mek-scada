
local const   = require("scada-common.constants")
local log     = require("scada-common.log")
local psil    = require("scada-common.psil")
local types   = require("scada-common.types")
local util    = require("scada-common.util")
local process = require("coordinator.process")
local sounder = require("coordinator.sounder")
local pgi     = require("coordinator.ui.pgi")
local ALARM_STATE = types.ALARM_STATE
local PROCESS = types.PROCESS
local ENERGY_SCALE = types.ENERGY_SCALE
local ENERGY_UNITS = types.ENERGY_SCALE_UNITS
local TEMP_SCALE = types.TEMP_SCALE
local TEMP_UNITS = types.TEMP_SCALE_UNITS
local RCT_STATE = types.REACTOR_STATE
local BLR_STATE = types.BOILER_STATE
local TRB_STATE = types.TURBINE_STATE
local TNK_STATE = types.TANK_STATE
local ESS_STATE = types.ESS_STATE
local SPS_STATE = types.SPS_STATE
local WASTE_PRODUCT = types.WASTE_PRODUCT
local WARN_RTT = 1000
local HIGH_RTT = 1500
local ioctl = {}
local _ioctl = {
wd_modem = true,
wl_modem = true,
speaker = true,
monitor_states = {},
coroutines = {}
}
local io = {
mek = { pu_ratio = { 10, 1 }, po_ratio = { 10, 1 } },
fp = { ps = psil.create() }
}
function ioctl.init(conf, comms, temp_scale, energy_scale)
io.temp_label   = TEMP_UNITS[temp_scale]
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
conf = conf,
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
auto_gen_rate = false,
auto_scram = false,
ascram_status = {
ess_fault = false,
ess_fill = false,
crit_alarm = false,
radiation = false,
gen_fault = false
},
auto_current_waste_product = WASTE_PRODUCT.PLUTONIUM,
auto_pu_fallback_active = false,
auto_sps_disabled = false,
waste_stats = { 0, 0, 0, 0, 0, 0 },
num_snas = 0,
sna_peak_rate = 0.0,
sna_max_rate = 0.0,
sna_out_rate = 0.0,
radiation = types.new_zero_radiation_reading(),
save_cfg_ack = nil,
alarm_tones = { false, false, false, false, false, false, false, false },
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
local function ack(alarm) process.ack_alarm(i, alarm) end
local function reset(alarm) process.reset_alarm(i, alarm) end
local entry = {
unit_id = i,
connected = false,
num_boilers = 0,
num_turbines = 0,
num_snas = 0,
has_tank = conf.cooling.r_cool[i].TankConnection,
aux_coolant = conf.cooling.aux_coolant[i],
status_lines = { "", "" },
auto_ready = false,
auto_degraded = false,
control_state = false,
burn_rate_cmd = 0.0,
radiation = types.new_zero_radiation_reading(),
sna_peak_rate = 0.0,
sna_max_rate = 0.0,
sna_out_rate = 0.0,
waste_mode = types.WASTE_MODE.MANUAL_PLUTONIUM,
waste_product = WASTE_PRODUCT.PLUTONIUM,
waste_stats = { 0, 0, 0 },
last_rate_change_ms = 0,
turbine_flow_stable = false,
fuel_burn_rate_limited = false,
a_group = types.AUTO_GROUP.MANUAL,
start = function () io.process.start(i) end,
scram = function () io.process.scram(i) end,
reset_rps = function () io.process.reset_rps(i) end,
ack_alarms = function () io.process.ack_all_alarms(i) end,
set_burn = function (rate) process.set_rate(i, rate) end,
set_waste = function (mode) process.set_unit_waste(i, mode) end,
set_group = function (grp) process.set_group(i, grp) end,
alarm_callbacks = {
c_breach   = { ack = function () ack(1)  end, reset = function () reset(1)  end },
radiation  = { ack = function () ack(2)  end, reset = function () reset(2)  end },
r_lost     = { ack = function () ack(3)  end, reset = function () reset(3)  end },
dmg_crit   = { ack = function () ack(4)  end, reset = function () reset(4)  end },
damage     = { ack = function () ack(5)  end, reset = function () reset(5)  end },
over_temp  = { ack = function () ack(6)  end, reset = function () reset(6)  end },
high_temp  = { ack = function () ack(7)  end, reset = function () reset(7)  end },
waste_leak = { ack = function () ack(8)  end, reset = function () reset(8)  end },
waste_high = { ack = function () ack(9)  end, reset = function () reset(9)  end },
rps_trans  = { ack = function () ack(10) end, reset = function () reset(10) end },
rcs_trans  = { ack = function () ack(11) end, reset = function () reset(11) end },
t_trip     = { ack = function () ack(12) end, reset = function () reset(12) end }
},
alarms = {
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
io.process = process.create_handle()
end
function ioctl.set_mek_config(conf)
local valid = type(conf) == "table" and type(conf[1]) == "table" and type(conf[2]) == "table"
if valid then
io.mek.pu_ratio[1] = conf[1][1]
io.mek.pu_ratio[2] = conf[1][2]
io.mek.po_ratio[1] = conf[2][1]
io.mek.po_ratio[2] = conf[2][2]
end
return valid
end
local function fp_eval_status()
local ok = _ioctl.wd_modem and _ioctl.wl_modem and _ioctl.speaker
for _, v in pairs(_ioctl.monitor_states) do ok = ok and v end
for _, v in pairs(_ioctl.coroutines) do ok = ok and v end
io.fp.ps.publish("status", ok)
end
function ioctl.heartbeat() io.fp.ps.toggle("heartbeat") end
function ioctl.fp_versions(firmware_v, comms_v)
io.fp.ps.publish("version", firmware_v)
io.fp.ps.publish("comms_version", comms_v)
end
function ioctl.fp_has_wd_modem(has_modem)
io.fp.ps.publish("has_wd_modem", has_modem)
_ioctl.wd_modem = has_modem
fp_eval_status()
end
function ioctl.fp_has_wl_modem(has_modem)
io.fp.ps.publish("has_wl_modem", has_modem)
_ioctl.wl_modem = has_modem
fp_eval_status()
end
function ioctl.fp_has_wd_net(up)
io.fp.ps.publish("has_wd_net", up)
end
function ioctl.fp_has_wl_net(up)
io.fp.ps.publish("has_wl_net", up)
end
function ioctl.fp_has_speaker(has_speaker)
io.fp.ps.publish("has_speaker", has_speaker)
_ioctl.speaker = has_speaker
fp_eval_status()
end
function ioctl.fp_link_state(state) io.fp.ps.publish("link_state", state) end
function ioctl.fp_monitor_state(id, connected)
local name = nil
if id == "main" then
name = "main_monitor"
elseif id == "flow" then
name = "flow_monitor"
elseif type(id) == "number" then
name = "unit_monitor_" .. id
end
if name ~= nil then
io.fp.ps.publish(name, connected)
_ioctl.monitor_states[name] = connected ~= 1
fp_eval_status()
end
end
function ioctl.fp_rt_status(thread, ok)
local name = util.c("routine__", thread)
io.fp.ps.publish(name, ok)
_ioctl.coroutines[name] = ok
fp_eval_status()
end
function ioctl.fp_pkt_connected(session_id, fw, s_addr)
io.fp.ps.publish("pkt_" .. session_id .. "_fw", fw)
io.fp.ps.publish("pkt_" .. session_id .. "_addr", util.sprintf("@ C% 3d", s_addr))
pgi.create_pkt_entry(session_id)
end
function ioctl.fp_pkt_disconnected(session_id)
pgi.delete_pkt_entry(session_id)
end
function ioctl.fp_pkt_rtt(session_id, rtt)
io.fp.ps.publish("pkt_" .. session_id .. "_rtt", rtt)
if rtt > HIGH_RTT then
io.fp.ps.publish("pkt_" .. session_id .. "_rtt_color", colors.red)
elseif rtt > WARN_RTT then
io.fp.ps.publish("pkt_" .. session_id .. "_rtt_color", colors.yellow_hc)
else
io.fp.ps.publish("pkt_" .. session_id .. "_rtt_color", colors.green_hc)
end
end
local function _record_multiblock_build(id, entry, data_tbl, ps_tbl, create)
local exists = type(data_tbl[id]) == "table"
if exists or create then
if not exists then
ps_tbl[id] = psil.create()
data_tbl[id] = {}
end
data_tbl[id].formed = entry[1]
data_tbl[id].build  = entry[2]
ps_tbl[id].publish("formed", entry[1])
for key, val in pairs(data_tbl[id].build) do ps_tbl[id].publish(key, val) end
end
return exists or (create == true)
end
function ioctl.record_facility_builds(build)
local valid = true
if type(build) == "table" then
local fac = io.facility
if type(build.induction) == "table" then
for id, matrix in pairs(build.induction) do
if not _record_multiblock_build(id, matrix, fac.induction_data_tbl, fac.induction_ps_tbl) then
log.debug(util.c("ioctl.record_facility_builds: invalid induction matrix id ", id))
valid = false
end
end
end
if type(build.ecore) == "table" then
for id, ecore in pairs(build.ecore) do
if not _record_multiblock_build(id, ecore, fac.ecore_data_tbl, fac.ecore_ps_tbl) then
log.debug(util.c("ioctl.record_facility_builds: invalid energy core id ", id))
valid = false
end
end
end
if type(build.sps) == "table" then
for id, sps in pairs(build.sps) do
if not _record_multiblock_build(id, sps, fac.sps_data_tbl, fac.sps_ps_tbl) then
log.debug(util.c("ioctl.record_facility_builds: invalid SPS id ", id))
valid = false
end
end
end
if type(build.tanks) == "table" then
for id, tank in pairs(build.tanks) do
_record_multiblock_build(id, tank, fac.tank_data_tbl, fac.tank_ps_tbl, true)
end
end
else
log.debug("facility builds not a table")
valid = false
end
return valid
end
function ioctl.record_unit_builds(builds)
local valid = true
for id, build in pairs(builds) do
local unit = io.units[id]
local log_header = util.c("ioctl.record_unit_builds[UNIT ", id, "]: ")
if type(build) ~= "table" then
log.debug(log_header .. "build not a table")
valid = false
elseif type(unit) ~= "table" then
log.debug(log_header .. "invalid unit id")
valid = false
else
if type(build.reactor) == "table" then
unit.reactor_data.mek_struct = build.reactor
for key, val in pairs(unit.reactor_data.mek_struct) do
unit.unit_ps.publish(key, val)
end
if (type(unit.reactor_data.mek_struct.length) == "number") and (unit.reactor_data.mek_struct.length ~= 0) and
(type(unit.reactor_data.mek_struct.width) == "number") and (unit.reactor_data.mek_struct.width ~= 0) then
unit.unit_ps.publish("size", { unit.reactor_data.mek_struct.length, unit.reactor_data.mek_struct.width })
end
end
if type(build.boilers) == "table" then
for b_id, boiler in pairs(build.boilers) do
if not _record_multiblock_build(b_id, boiler, unit.boiler_data_tbl, unit.boiler_ps_tbl) then
log.debug(util.c(log_header, "invalid boiler id ", b_id))
valid = false
end
end
end
if type(build.turbines) == "table" then
for t_id, turbine in pairs(build.turbines) do
if not _record_multiblock_build(t_id, turbine, unit.turbine_data_tbl, unit.turbine_ps_tbl) then
log.debug(util.c(log_header, "invalid turbine id ", t_id))
valid = false
end
end
end
if type(build.tanks) == "table" then
for d_id, d_tank in pairs(build.tanks) do
_record_multiblock_build(d_id, d_tank, unit.tank_data_tbl, unit.tank_ps_tbl, true)
end
end
end
end
return valid
end
local function gen_eta_text(eta_ms)
local str, pre = "", util.trinary(eta_ms >= 0, "Full in ", "Empty in ")
local seconds = math.abs(eta_ms) / 1000
local minutes = seconds / 60
local hours   = minutes / 60
local days    = hours / 24
if math.abs(eta_ms) < 1000 or (eta_ms ~= eta_ms) then
str = "No ETA"
elseif days < 1000 then
days    = math.floor(days)
hours   = math.floor(hours % 24)
minutes = math.floor(minutes % 60)
seconds = math.floor(seconds % 60)
if days > 0 then
str = days .. "d"
elseif hours > 0 then
str = hours .. "h " .. minutes .. "m"
elseif minutes > 0 then
str = minutes .. "m " .. seconds .. "s"
elseif seconds > 0 then
str = seconds .. "s"
end
str = pre .. str
else
local years = math.floor(days / 365.25)
if years <= 99999999 then
str = pre .. years .. "y"
else
str = pre .. "eras"
end
end
return str
end
local function _record_multiblock_status(entry, data, ps)
local is_faulted = entry[1]
data.formed      = entry[2]
data.state       = entry[3]
data.tanks       = entry[4]
ps.publish("formed", data.formed)
ps.publish("faulted", is_faulted)
for key, val in pairs(data.state) do ps.publish(key, val) end
for key, val in pairs(data.tanks) do ps.publish(key, val) end
return is_faulted
end
function ioctl.update_facility_status(status)
local valid = true
local log_header = util.c("ioctl.update_facility_status: ")
if type(status) ~= "table" then
log.debug(util.c(log_header, "status not a table"))
valid = false
else
local fac = io.facility
local f_ps = fac.ps
local ctl_status = status[1]
if type(ctl_status) == "table" and #ctl_status == 19 then
fac.all_sys_ok = ctl_status[1]
fac.auto_ready = ctl_status[2]
if type(ctl_status[3]) == "number" then
fac.auto_active = ctl_status[3] > PROCESS.INACTIVE
else
fac.auto_active = false
valid = false
end
fac.auto_ramping = ctl_status[4]
fac.auto_saturated = ctl_status[5]
fac.auto_gen_rate = ctl_status[6]
fac.auto_scram = ctl_status[7]
fac.ascram_status.ess_fault = ctl_status[8]
fac.ascram_status.ess_fill = ctl_status[9]
fac.ascram_status.crit_alarm = ctl_status[10]
fac.ascram_status.radiation = ctl_status[11]
fac.ascram_status.gen_fault = ctl_status[12]
fac.status_lines[1] = ctl_status[14]
fac.status_lines[2] = ctl_status[15]
f_ps.publish("all_sys_ok", fac.all_sys_ok)
f_ps.publish("auto_ready", fac.auto_ready)
f_ps.publish("auto_active", fac.auto_active)
f_ps.publish("auto_ramping", fac.auto_ramping)
f_ps.publish("auto_saturated", fac.auto_saturated)
f_ps.publish("auto_gen_rate", fac.auto_gen_rate)
f_ps.publish("auto_scram", fac.auto_scram)
f_ps.publish("as_ess_fault", fac.ascram_status.ess_fault)
f_ps.publish("as_ess_fill", fac.ascram_status.ess_fill)
f_ps.publish("as_crit_alarm", fac.ascram_status.crit_alarm)
f_ps.publish("as_radiation", fac.ascram_status.radiation)
f_ps.publish("as_gen_fault", fac.ascram_status.gen_fault)
f_ps.publish("config_warning", ctl_status[13])
f_ps.publish("status_line_1", fac.status_lines[1])
f_ps.publish("status_line_2", fac.status_lines[2])
local group_map = ctl_status[16]
if (type(group_map) == "table") and (#group_map == fac.num_units) then
for i = 1, #group_map do
io.units[i].a_group = group_map[i]
io.units[i].unit_ps.publish("auto_group_id", group_map[i])
io.units[i].unit_ps.publish("auto_group", types.AUTO_GROUP_NAMES[group_map[i] + 1])
end
end
fac.auto_current_waste_product = ctl_status[17]
fac.auto_pu_fallback_active = ctl_status[18]
fac.auto_sps_disabled = ctl_status[19]
f_ps.publish("current_waste_product", fac.auto_current_waste_product)
f_ps.publish("pu_fallback_active", fac.auto_pu_fallback_active)
f_ps.publish("sps_disabled_low_power", fac.auto_sps_disabled)
else
log.debug(log_header .. "control status not a table or length mismatch")
valid = false
end
local rtu_statuses = status[2]
fac.rtu_count = 0
if type(rtu_statuses) == "table" then
fac.rtu_count = rtu_statuses.count
if type(rtu_statuses.power) == "table" and #rtu_statuses.power == 4 then
local ps = util.trinary(fac.ess_type == types.ESS.ENERGY_CORE, fac.ecore_ps_tbl[1], fac.induction_ps_tbl[1])
local chg   = tonumber(rtu_statuses.power[1])
local in_f  = tonumber(rtu_statuses.power[2])
local out_f = tonumber(rtu_statuses.power[3])
local eta   = tonumber(rtu_statuses.power[4])
ps.publish("avg_charge", chg)
ps.publish("avg_inflow", in_f)
ps.publish("avg_outflow", out_f)
ps.publish("eta_ms", eta)
ps.publish("eta_string", gen_eta_text(eta or 0))
local charging, discharging = false, false
if fac.ess_type == types.ESS.ENERGY_CORE then
local data = fac.ecore_data_tbl[1]
if data and data.state then
charging = data.state.transfer > 0
discharging = data.state.transfer < 0
end
else
local data = fac.induction_data_tbl[1]
charging = in_f > out_f
discharging = out_f > in_f
if data and data.build then
local cap = util.joules_to_fe_rf(data.build.transfer_cap)
ps.publish("at_max_io", in_f >= cap or out_f >= cap)
end
end
ps.publish("is_charging", charging)
ps.publish("is_discharging", discharging)
else
log.debug(log_header .. "power statistics list not a table")
valid = false
end
if type(rtu_statuses.induction) == "table" then
local matrix_status = ESS_STATE.OFFLINE
for id = 1, #fac.induction_ps_tbl do
if rtu_statuses.induction[id] == nil then
fac.induction_ps_tbl[id].publish("computed_status", matrix_status)
end
end
for id, matrix in pairs(rtu_statuses.induction) do
if type(fac.induction_data_tbl[id]) == "table" then
local data = fac.induction_data_tbl[id]
local ps   = fac.induction_ps_tbl[id]
local rtu_faulted = _record_multiblock_status(matrix, data, ps)
if rtu_faulted then
matrix_status = ESS_STATE.FAULT
elseif data.formed then
if data.tanks.energy_fill > const.RS_THRESHOLDS.ENERGY_CHARGE_HIGH then
matrix_status = ESS_STATE.HIGH_CHARGE
elseif data.tanks.energy_fill < const.RS_THRESHOLDS.ENERGY_CHARGE_LOW then
matrix_status = ESS_STATE.LOW_CHARGE
else
matrix_status = ESS_STATE.ONLINE
end
else
matrix_status = ESS_STATE.UNFORMED
end
ps.publish("computed_status", matrix_status)
else
log.debug(util.c(log_header, "invalid induction matrix id ", id))
end
end
else
log.debug(log_header .. "induction matrix list not a table")
valid = false
end
if type(rtu_statuses.ecore) == "table" then
local ecore_status = ESS_STATE.OFFLINE
for id = 1, #fac.ecore_ps_tbl do
if rtu_statuses.ecore[id] == nil then
fac.ecore_ps_tbl[id].publish("computed_status", ecore_status)
end
end
for id, ecore in pairs(rtu_statuses.ecore) do
if type(fac.induction_data_tbl[id]) == "table" then
local data = fac.ecore_data_tbl[id]
local ps   = fac.ecore_ps_tbl[id]
local rtu_faulted = ecore[1]
data.formed  = ecore[2]
data.state   = ecore[3]
data.virtual = ecore[4]
ps.publish("formed", data.formed)
ps.publish("faulted", rtu_faulted)
for key, val in pairs(data.state) do ps.publish(key, val) end
for key, val in pairs(data.virtual) do ps.publish(key, val) end
if rtu_faulted then
ecore_status = ESS_STATE.FAULT
elseif data.formed then
if data.virtual.energy_fill > const.RS_THRESHOLDS.ENERGY_CHARGE_HIGH then
ecore_status = ESS_STATE.HIGH_CHARGE
elseif data.virtual.energy_fill < const.RS_THRESHOLDS.ENERGY_CHARGE_LOW then
ecore_status = ESS_STATE.LOW_CHARGE
else
ecore_status = ESS_STATE.ONLINE
end
else
ecore_status = ESS_STATE.UNFORMED
end
ps.publish("computed_status", ecore_status)
else
log.debug(util.c(log_header, "invalid energy core id ", id))
end
end
else
log.debug(log_header .. "energy core list not a table")
valid = false
end
if type(rtu_statuses.sna) == "table" then
fac.num_snas      = rtu_statuses.sna[1]
fac.sna_peak_rate = rtu_statuses.sna[2]
fac.sna_max_rate  = rtu_statuses.sna[3]
fac.sna_out_rate  = rtu_statuses.sna[4]
f_ps.publish("sna_count", fac.num_snas)
f_ps.publish("sna_peak_rate", fac.sna_peak_rate)
f_ps.publish("sna_max_rate_out", fac.sna_max_rate)
f_ps.publish("sna_max_rate_in", (fac.sna_max_rate * io.mek.po_ratio[1]) / io.mek.po_ratio[2])
f_ps.publish("sna_out_rate", fac.sna_out_rate)
elseif fac.combined_waste then
log.debug(log_header .. "sna statistic list not a table")
valid = false
end
if type(rtu_statuses.sps) == "table" then
local sps_status = SPS_STATE.OFFLINE
for id = 1, #fac.sps_ps_tbl do
if rtu_statuses.sps[id] == nil then
fac.sps_ps_tbl[id].publish("computed_status", sps_status)
end
end
for id, sps in pairs(rtu_statuses.sps) do
if type(fac.sps_data_tbl[id]) == "table" then
local data = fac.sps_data_tbl[id]
local ps   = fac.sps_ps_tbl[id]
local rtu_faulted = _record_multiblock_status(sps, data, ps)
if rtu_faulted then
sps_status = SPS_STATE.FAULT
elseif data.formed then
sps_status = util.trinary(data.state.process_rate > 0, SPS_STATE.ACTIVE, SPS_STATE.IDLE)
else sps_status = SPS_STATE.UNFORMED end
ps.publish("computed_status", sps_status)
io.facility.ps.publish("am_rate", data.state.process_rate * 1000)
else
log.debug(util.c(log_header, "invalid sps id ", id))
end
end
else
log.debug(log_header .. "sps list not a table")
valid = false
end
if type(rtu_statuses.tanks) == "table" then
local tank_status = TNK_STATE.OFFLINE
for id = 1, #fac.tank_ps_tbl do
if rtu_statuses.tanks[id] == nil then
fac.tank_ps_tbl[id].publish("computed_status", tank_status)
end
end
for id, tank in pairs(rtu_statuses.tanks) do
if type(fac.tank_data_tbl[id]) == "table" then
local data = fac.tank_data_tbl[id]
local ps   = fac.tank_ps_tbl[id]
local rtu_faulted = _record_multiblock_status(tank, data, ps)
if rtu_faulted then
tank_status = TNK_STATE.FAULT
elseif data.formed then
if data.tanks.fill >= 0.99 then
tank_status = TNK_STATE.HIGH_FILL
elseif data.tanks.fill < 0.20 then
tank_status = TNK_STATE.LOW_FILL
else
tank_status = TNK_STATE.ONLINE
end
else tank_status = TNK_STATE.UNFORMED end
ps.publish("computed_status", tank_status)
else
log.debug(util.c(log_header, "invalid dynamic tank id ", id))
end
end
else
log.debug(log_header .. "dyanmic tank list not a table")
valid = false
end
if type(rtu_statuses.envds) == "table" then
local max_rad, max_reading, any_conn, any_faulted = 0, types.new_zero_radiation_reading(), false, false
fac.rad_monitors = {}
for id, envd in pairs(rtu_statuses.envds) do
local rtu_faulted = envd[1]
local radiation   = envd[2]
local rad_raw     = envd[3]
any_conn = true
any_faulted = any_faulted or rtu_faulted
if rad_raw > max_rad then
max_rad = rad_raw
max_reading = radiation
end
if not rtu_faulted then
fac.rad_monitors[id] = { radiation = radiation, raw = rad_raw }
end
end
if any_conn then
fac.radiation = max_reading
f_ps.publish("rad_computed_status", util.trinary(any_faulted, 2, 3))
else
fac.radiation = types.new_zero_radiation_reading()
f_ps.publish("rad_computed_status", 1)
end
f_ps.publish("radiation", fac.radiation)
else
log.debug(log_header .. "environment detector list not a table")
valid = false
end
else
log.debug(log_header .. "rtu statuses not a table")
valid = false
end
f_ps.publish("rtu_count", fac.rtu_count)
if (type(status[3]) == "table") and (#status[3] == 8) then
fac.alarm_tones = status[3]
sounder.set(fac.alarm_tones)
else
log.debug(log_header .. "alarm tones not a table or length mismatch")
valid = false
end
if fac.combined_waste then
if (type(status[4]) == "table") and (#status[4] == 4) then
local ps, valve_states = f_ps, status[4]
ps.publish("V_pu_conn", valve_states[1] > 0)
ps.publish("V_pu_state", valve_states[1] == 2)
ps.publish("V_po_conn", valve_states[2] > 0)
ps.publish("V_po_state", valve_states[2] == 2)
ps.publish("V_pl_conn", valve_states[3] > 0)
ps.publish("V_pl_state", valve_states[3] == 2)
ps.publish("V_am_conn", valve_states[4] > 0)
ps.publish("V_am_state", valve_states[4] == 2)
else
log.debug(log_header .. "valve states not a table or length mismatch")
valid = false
end
end
end
return valid
end
function ioctl.update_unit_statuses(statuses)
local valid = true
if type(statuses) ~= "table" then
log.debug("ioctl.update_unit_statuses: unit statuses not a table")
valid = false
elseif #statuses ~= #io.units then
log.debug("ioctl.update_unit_statuses: number of provided unit statuses does not match expected number of units")
valid = false
else
local burn_rate_sum = 0.0
local sna_count_sum = 0
local pu_rate, po_rate, po_pl_rate, po_am_rate, spent_rate = 0.0, 0.0, 0.0, 0.0, 0.0
local fac = io.facility
for i = 1, #statuses do
local log_header = util.c("ioctl.update_unit_statuses[unit ", i, "]: ")
local unit = io.units[i]
local status = statuses[i]
local burn_rate = 0.0
if type(status) ~= "table" or #status ~= 6 then
log.debug(log_header .. "invalid status entry in unit statuses (not a table or invalid length)")
valid = false
else
local reactor_status = status[1]
if type(reactor_status) ~= "table" then
reactor_status = {}
log.debug(log_header .. "reactor status not a table")
end
local computed_status = RCT_STATE.OFFLINE
if #reactor_status == 0 then
unit.connected = false
unit.unit_ps.publish("computed_status", computed_status)
elseif #reactor_status == 3 then
local mek_status = reactor_status[1]
local rps_status = reactor_status[2]
local gen_status = reactor_status[3]
if #gen_status == 6 then
unit.reactor_data.last_status_update = gen_status[1]
unit.reactor_data.control_state      = gen_status[2]
unit.reactor_data.rps_tripped        = gen_status[3]
unit.reactor_data.rps_trip_cause     = gen_status[4]
unit.reactor_data.no_reactor         = gen_status[5]
unit.reactor_data.formed             = gen_status[6]
else
log.debug(log_header .. "reactor general status length mismatch")
end
for key, val in pairs(unit.reactor_data) do
if key ~= "rps_status" and key ~= "mek_struct" and key ~= "mek_status" then
unit.unit_ps.publish(key, val)
end
end
unit.reactor_data.rps_status = rps_status
for key, val in pairs(rps_status) do
unit.unit_ps.publish(key, val)
end
if next(mek_status) then
unit.reactor_data.mek_status = mek_status
for key, val in pairs(mek_status) do
unit.unit_ps.publish(key, val)
end
end
burn_rate = unit.reactor_data.mek_status.act_burn_rate
burn_rate_sum = burn_rate_sum + burn_rate
if unit.reactor_data.mek_status.status then
computed_status = RCT_STATE.ACTIVE
else
if unit.reactor_data.no_reactor then
computed_status = RCT_STATE.FAULT
elseif not unit.reactor_data.formed then
computed_status = RCT_STATE.UNFORMED
elseif unit.reactor_data.rps_status.force_dis then
computed_status = RCT_STATE.FORCE_DISABLED
elseif unit.reactor_data.rps_tripped and unit.reactor_data.rps_trip_cause ~= "manual" then
computed_status = RCT_STATE.SCRAMMED
else
computed_status = RCT_STATE.DISABLED
end
end
unit.connected = true
unit.unit_ps.publish("computed_status", computed_status)
else
log.debug(log_header .. "reactor status length mismatch")
valid = false
end
local rtu_statuses = status[2]
if type(rtu_statuses) == "table" then
if type(rtu_statuses.boilers) == "table" then
local boil_sum = 0
computed_status = BLR_STATE.OFFLINE
for id = 1, #unit.boiler_ps_tbl do
if rtu_statuses.boilers[id] == nil then
unit.boiler_ps_tbl[id].publish("computed_status", computed_status)
end
end
for id, boiler in pairs(rtu_statuses.boilers) do
if type(unit.boiler_data_tbl[id]) == "table" then
local data = unit.boiler_data_tbl[id]
local ps   = unit.boiler_ps_tbl[id]
local rtu_faulted = _record_multiblock_status(boiler, data, ps)
if rtu_faulted then
computed_status = BLR_STATE.FAULT
elseif data.formed then
boil_sum = boil_sum + data.state.boil_rate
computed_status = util.trinary(data.state.boil_rate > 0, BLR_STATE.ACTIVE, BLR_STATE.IDLE)
else computed_status = BLR_STATE.UNFORMED end
unit.boiler_ps_tbl[id].publish("computed_status", computed_status)
else
log.debug(util.c(log_header, "invalid boiler id ", id))
valid = false
end
end
unit.unit_ps.publish("boiler_boil_sum", boil_sum)
else
log.debug(log_header .. "boiler list not a table")
valid = false
end
if type(rtu_statuses.turbines) == "table" then
local flow_sum = 0
computed_status = TRB_STATE.OFFLINE
for id = 1, #unit.turbine_ps_tbl do
if rtu_statuses.turbines[id] == nil then
unit.turbine_ps_tbl[id].publish("computed_status", computed_status)
end
end
for id, turbine in pairs(rtu_statuses.turbines) do
if type(unit.turbine_data_tbl[id]) == "table" then
local data = unit.turbine_data_tbl[id]
local ps   = unit.turbine_ps_tbl[id]
local rtu_faulted = _record_multiblock_status(turbine, data, ps)
if rtu_faulted then
computed_status = TRB_STATE.FAULT
elseif data.formed then
flow_sum = flow_sum + data.state.flow_rate
if data.tanks.energy_fill >= 0.99 then
computed_status = TRB_STATE.TRIPPED
elseif data.state.flow_rate < 100 then
computed_status = TRB_STATE.IDLE
else
computed_status = TRB_STATE.ACTIVE
end
else computed_status = TRB_STATE.UNFORMED end
unit.turbine_ps_tbl[id].publish("computed_status", computed_status)
else
log.debug(util.c(log_header, "invalid turbine id ", id))
valid = false
end
end
unit.unit_ps.publish("turbine_flow_sum", flow_sum)
else
log.debug(log_header .. "turbine list not a table")
valid = false
end
if type(rtu_statuses.tanks) == "table" then
computed_status = TNK_STATE.OFFLINE
for id = 1, #unit.tank_ps_tbl do
if rtu_statuses.tanks[id] == nil then
unit.tank_ps_tbl[id].publish("computed_status", computed_status)
end
end
for id, tank in pairs(rtu_statuses.tanks) do
if type(unit.tank_data_tbl[id]) == "table" then
local data = unit.tank_data_tbl[id]
local ps   = unit.tank_ps_tbl[id]
local rtu_faulted = _record_multiblock_status(tank, data, ps)
if rtu_faulted then
computed_status = TNK_STATE.FAULT
elseif data.formed then
if data.tanks.fill >= 0.99 then
computed_status = TNK_STATE.HIGH_FILL
elseif data.tanks.fill < 0.20 then
computed_status = TNK_STATE.LOW_FILL
else
computed_status = TNK_STATE.ONLINE
end
else computed_status = TNK_STATE.UNFORMED end
unit.tank_ps_tbl[id].publish("computed_status", computed_status)
else
log.debug(util.c(log_header, "invalid dynamic tank id ", id))
valid = false
end
end
else
log.debug(log_header .. "dynamic tank list not a table")
valid = false
end
if type(rtu_statuses.sna) == "table" then
unit.num_snas      = rtu_statuses.sna[1]
unit.sna_peak_rate = rtu_statuses.sna[2]
unit.sna_max_rate  = rtu_statuses.sna[3]
unit.sna_out_rate  = rtu_statuses.sna[4]
unit.unit_ps.publish("sna_count", unit.num_snas)
unit.unit_ps.publish("sna_peak_rate", unit.sna_peak_rate)
unit.unit_ps.publish("sna_max_rate_out", unit.sna_max_rate)
unit.unit_ps.publish("sna_max_rate_in", (unit.sna_max_rate * io.mek.po_ratio[1]) / io.mek.po_ratio[2])
unit.unit_ps.publish("sna_out_rate", unit.sna_out_rate)
sna_count_sum = sna_count_sum + unit.num_snas
else
log.debug(log_header .. "sna statistic list not a table")
valid = false
end
if type(rtu_statuses.envds) == "table" then
local max_rad, max_reading, any_conn = 0, types.new_zero_radiation_reading(), false
unit.rad_monitors = {}
for id, envd in pairs(rtu_statuses.envds) do
local rtu_faulted = envd[1]
local radiation   = envd[2]
local rad_raw     = envd[3]
any_conn = true
if rad_raw > max_rad then
max_rad = rad_raw
max_reading = radiation
end
if not rtu_faulted then
unit.rad_monitors[id] = { radiation = radiation, raw = rad_raw }
end
end
if any_conn then
unit.radiation = max_reading
else
unit.radiation = types.new_zero_radiation_reading()
end
unit.unit_ps.publish("radiation", unit.radiation)
else
log.debug(log_header .. "radiation monitor list not a table")
valid = false
end
else
log.debug(log_header .. "rtu list not a table")
valid = false
end
unit.annunciator = status[3]
if type(unit.annunciator) ~= "table" then
unit.annunciator = {}
log.debug(log_header .. "annunciator state not a table")
valid = false
end
for key, val in pairs(unit.annunciator) do
if key == "BoilerOnline" or key == "HeatingRateLow" or key == "WaterLevelLow" then
for id = 1, #val do
unit.boiler_ps_tbl[id].publish(key, val[id])
end
elseif key == "TurbineOnline" or key == "SteamDumpOpen" or key == "TurbineOverSpeed" or
key == "GeneratorTrip" or key == "TurbineTrip" then
for id = 1, #val do
unit.turbine_ps_tbl[id].publish(key, val[id])
end
elseif type(val) == "table" then
log.debug(log_header .. "unrecognized table found in annunciator list, this is a bug")
valid = false
else
unit.unit_ps.publish(key, val)
end
end
local alarm_states = status[4]
if type(alarm_states) == "table" then
for id = 1, #alarm_states do
local state = alarm_states[id]
unit.alarms[id] = state
if state == types.ALARM_STATE.TRIPPED or state == types.ALARM_STATE.ACKED then
unit.unit_ps.publish("Alarm_" .. id, 2)
elseif state == types.ALARM_STATE.RING_BACK then
unit.unit_ps.publish("Alarm_" .. id, 3)
else
unit.unit_ps.publish("Alarm_" .. id, 1)
end
end
else
log.debug(log_header .. "alarm states not a table")
valid = false
end
local unit_state = status[5]
if type(unit_state) == "table" then
if #unit_state == 9 then
unit.status_lines[1] = unit_state[1]
unit.status_lines[2] = unit_state[2]
unit.auto_ready = unit_state[3]
unit.auto_degraded = unit_state[4]
unit.waste_mode = unit_state[5]
unit.waste_product = unit_state[6]
unit.last_rate_change_ms = unit_state[7]
unit.turbine_flow_stable = unit_state[8]
unit.fuel_burn_rate_limited = unit_state[9]
unit.unit_ps.publish("U_StatusLine1", unit.status_lines[1])
unit.unit_ps.publish("U_StatusLine2", unit.status_lines[2])
unit.unit_ps.publish("U_AutoReady", unit.auto_ready)
unit.unit_ps.publish("U_AutoDegraded", unit.auto_degraded)
unit.unit_ps.publish("U_AutoWaste", unit.waste_mode == types.WASTE_MODE.AUTO)
unit.unit_ps.publish("U_WasteMode", unit.waste_mode)
unit.unit_ps.publish("U_WasteProduct", unit.waste_product)
else
log.debug(log_header .. "unit state length mismatch")
valid = false
end
else
log.debug(log_header .. "unit state not a table")
valid = false
end
local valve_states = status[6]
if type(valve_states) == "table" then
if #valve_states == 6 then
unit.unit_ps.publish("V_pu_conn", valve_states[1] > 0)
unit.unit_ps.publish("V_pu_state", valve_states[1] == 2)
unit.unit_ps.publish("V_po_conn", valve_states[2] > 0)
unit.unit_ps.publish("V_po_state", valve_states[2] == 2)
unit.unit_ps.publish("V_pl_conn", valve_states[3] > 0)
unit.unit_ps.publish("V_pl_state", valve_states[3] == 2)
unit.unit_ps.publish("V_am_conn", valve_states[4] > 0)
unit.unit_ps.publish("V_am_state", valve_states[4] == 2)
unit.unit_ps.publish("V_emc_conn", valve_states[5] > 0)
unit.unit_ps.publish("V_emc_state", valve_states[5] == 2)
unit.unit_ps.publish("V_aux_conn", valve_states[6] > 0)
unit.unit_ps.publish("V_aux_state", valve_states[6] == 2)
else
log.debug(log_header .. "valve states length mismatch")
valid = false
end
else
log.debug(log_header .. "valve states not a table")
valid = false
end
local u_spent_rate
local u_pu_rate, u_po_rate, u_po_pl_rate, u_po_am_rate = 0, unit.sna_out_rate, 0, 0
local product = util.trinary(fac.combined_waste, fac.auto_current_waste_product, unit.waste_product)
unit.unit_ps.publish("sna_in", util.trinary(product == WASTE_PRODUCT.PLUTONIUM, 0, burn_rate))
if product == WASTE_PRODUCT.ANTI_MATTER then
u_po_am_rate = u_po_rate
po_am_rate   = po_am_rate + u_po_am_rate
u_spent_rate = 0
elseif product == WASTE_PRODUCT.POLONIUM then
u_po_pl_rate = u_po_rate
po_pl_rate   = po_pl_rate + u_po_rate
u_spent_rate = u_po_rate
else
u_pu_rate    = (burn_rate * io.mek.pu_ratio[2]) / io.mek.pu_ratio[1]
pu_rate      = pu_rate + u_pu_rate
u_spent_rate = u_pu_rate
end
unit.unit_ps.publish("pu_rate", u_pu_rate)
unit.unit_ps.publish("po_rate", u_po_rate)
unit.unit_ps.publish("po_pl_rate", u_po_pl_rate)
unit.unit_ps.publish("po_am_rate", u_po_am_rate)
unit.waste_stats = { u_pu_rate, u_po_rate, u_po_pl_rate }
unit.unit_ps.publish("ws_rate", u_spent_rate)
po_rate = po_rate + u_po_rate
spent_rate = spent_rate + u_spent_rate
end
end
local f_ps = fac.ps
if fac.combined_waste then
po_rate = fac.sna_out_rate
if fac.auto_current_waste_product == WASTE_PRODUCT.POLONIUM then
po_pl_rate = po_rate
spent_rate = po_rate
elseif fac.auto_current_waste_product == WASTE_PRODUCT.ANTI_MATTER then
po_am_rate = po_rate
end
else
f_ps.publish("sna_count", sna_count_sum)
end
fac.waste_stats = { burn_rate_sum, pu_rate, po_rate, po_pl_rate, po_am_rate, spent_rate }
f_ps.publish("burn_sum", burn_rate_sum)
f_ps.publish("sna_in", util.trinary(fac.auto_current_waste_product == WASTE_PRODUCT.PLUTONIUM, 0, burn_rate_sum))
f_ps.publish("pu_rate", pu_rate)
f_ps.publish("po_rate", po_rate)
f_ps.publish("po_pl_rate", po_pl_rate)
f_ps.publish("po_am_rate", po_am_rate)
f_ps.publish("spent_waste_rate", spent_rate)
end
return valid
end
function ioctl.get_db() return io end
return ioctl
