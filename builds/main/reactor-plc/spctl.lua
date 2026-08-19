local log     = require("scada-common.log")
local util    = require("scada-common.util")
local databus = require("reactor-plc.databus")
local plc     = require("reactor-plc.plc")
local SLOW_RAMP_mB_s     = 5.0
local FAST_SWITCH_mB_s   = 40.0
local FAST_MAX_PERCENT_s = 0.02
local FUEL_LIMIT_INIT    = 0.4
local FUEL_LIMIT_START   = 0.3
local FUEL_LIMIT_RELEASE = 0.4
local FUEL_LIMIT_EMA_A   = 0.05
local spctl = {}
local STATES = {
STOPPED = 1,
INIT = 2,
SLOW_RAMP_UP = 3,
SLOW_RAMP_DOWN = 4,
STABLE_WAIT = 5,
CCOOL_MON = 6,
FAST_RAMP_UP = 7,
FAST_RAMP_DOWN = 8
}
local STATE_NAMES = {
"STOPPED",
"INIT",
"SLOW_RAMP_UP",
"SLOW_RAMP_DOWN",
"STABLE_WAIT",
"CCOOL_MON",
"FAST_RAMP_UP",
"FAST_RAMP_DOWN"
}
local _spctl = {
data = {
tps = 0.0,
tick_time = 0,
max_br = 0.0,
burn_rate = 0.0,
act_rate = 0.0,
fuel = 0.0,
fuel_fill = 0.0,
ccool_fill = 0.0
},
fast_ramp_en = false,
fast_ramping = false,   -- once we have passed through check phases once, don't repeat until reset
last_sp = 0.0,
last_ccool = 0.0,
last_change = 0,
next_state = STATES.STOPPED,
last_state = STATES.STOPPED,
fuel_limit_en = false,
fuel_monitoring = false,
fuel_limiting = false,
last_mon_check = 0,
last_fuel_filt = 0.0,
d_fuel = 0.0,
d_fuel_mBt = 0.0,
fuel_filt = util.ema_filter(FUEL_LIMIT_EMA_A),
rate_filt = util.ema_filter(FUEL_LIMIT_EMA_A),
tick_filt = util.ema_filter(FUEL_LIMIT_EMA_A)
}
local rps       = nil
local plc_state = nil
local setpoints = nil
local limits    = nil
function spctl.init(smem)
rps       = smem.plc_sys.rps
plc_state = smem.plc_state
setpoints = smem.setpoints
limits    = smem.limits
_spctl.fast_ramp_en  = plc.config.FastRamp
_spctl.fuel_limit_en = plc.config.FuelAutoLimiting
end
local function ramp_init(cur_br)
_spctl.last_sp = setpoints.burn_rate
if math.abs(setpoints.burn_rate - cur_br) > 2.5 then
local new_state = _spctl.next_state
if _spctl.next_state == STATES.STOPPED then
log.debug(util.c("SPCTL: 开始从 ", cur_br, " mB/t 到 ", setpoints.burn_rate, " mB/t 的燃烧速率斜坡"))
new_state = STATES.INIT
_spctl.fast_ramping = false
else
log.debug(util.c("SPCTL: burn rate ramp from ", cur_br, " mB/t to ", setpoints.burn_rate, " mB/t (updated setpoint)"))
if setpoints.burn_rate > cur_br then
if _spctl.fast_ramp_en and ((cur_br >= FAST_SWITCH_mB_s) or _spctl.fast_ramping) then
if _spctl.fast_ramping then
new_state = STATES.FAST_RAMP_UP
elseif _spctl.next_state ~= STATES.STABLE_WAIT and _spctl.next_state ~= STATES.CCOOL_MON then
new_state = STATES.STABLE_WAIT
end
else
new_state = STATES.SLOW_RAMP_UP
end
else
if _spctl.fast_ramp_en and ((cur_br >= FAST_SWITCH_mB_s) or _spctl.fast_ramping) then
new_state = STATES.FAST_RAMP_DOWN
else
new_state = STATES.SLOW_RAMP_DOWN
end
end
end
if new_state ~= _spctl.next_state then
log.debug("SPCTL: ramp_init() state changed to " .. (STATE_NAMES[new_state] or "UNKNOWN"))
_spctl.next_state = new_state
_spctl.last_change = os.clock()
end
elseif _spctl.fuel_limiting then
local lim_br = math.min(setpoints.burn_rate, limits.fuel_max_burn)
plc_state.limit_force_ramp = false
log.debug(util.c("SPCTL: setting burn rate directly to ", lim_br, " mB/t (limiting active, setpoint is ", setpoints.burn_rate, ")"))
_spctl.new_br = lim_br
if _spctl.next_state == STATES.STOPPED then
setpoints.burn_rate_en = false
end
else
plc_state.limit_force_ramp = false
log.debug(util.c("SPCTL: setting burn rate directly to ", setpoints.burn_rate, " mB/t"))
_spctl.new_br = setpoints.burn_rate
if _spctl.next_state == STATES.STOPPED then
setpoints.burn_rate_en = false
end
end
end
local function ramp_reset()
_spctl.last_sp    = 0
_spctl.last_ccool = 0
_spctl.next_state = STATES.STOPPED
_spctl.last_state = STATES.STOPPED
_spctl.fast_ramping = false
end
local function ramp_run(cur_br, cur_ccool, elapsed_s)
local now        = os.clock()
local state_time = now - _spctl.last_change
local state      = _spctl.next_state
local new_state  = _spctl.next_state
local new_br     = cur_br
if state == STATES.INIT then
log.debug(util.c("SPCTL: initializing for ", util.trinary(_spctl.fast_ramp_en, "fast", "slow"), " burn rate ramping mode"))
if setpoints.burn_rate > cur_br then
if _spctl.fast_ramp_en and (cur_br >= FAST_SWITCH_mB_s) then
new_state = STATES.STABLE_WAIT
else
new_state = STATES.SLOW_RAMP_UP
end
else
if _spctl.fast_ramp_en and (cur_br >= FAST_SWITCH_mB_s) then
new_state = STATES.FAST_RAMP_DOWN
else
new_state = STATES.SLOW_RAMP_DOWN
end
end
elseif state == STATES.SLOW_RAMP_UP then
new_br = cur_br + (SLOW_RAMP_mB_s * elapsed_s)
if new_br > setpoints.burn_rate then new_br = setpoints.burn_rate end
if _spctl.fast_ramp_en and (new_br >= FAST_SWITCH_mB_s) then
new_br = FAST_SWITCH_mB_s
new_state = STATES.STABLE_WAIT
end
elseif state == STATES.SLOW_RAMP_DOWN then
new_br = cur_br - (SLOW_RAMP_mB_s * elapsed_s)
if new_br < setpoints.burn_rate then new_br = setpoints.burn_rate end
elseif state == STATES.STABLE_WAIT then
if state_time >= 2 then
new_state = STATES.CCOOL_MON
end
elseif state == STATES.CCOOL_MON then
if cur_ccool >= _spctl.last_ccool then
new_state = STATES.FAST_RAMP_UP
_spctl.fast_ramping = true
end
elseif state == STATES.FAST_RAMP_UP then
local scaler = math.min(FAST_MAX_PERCENT_s, FAST_MAX_PERCENT_s * (state_time / 5.0)) * elapsed_s
local step   = scaler * _spctl.data.max_br
if cur_ccool < 0.8 then
local a = (cur_ccool - 0.4) * 2.5
step = step * a
end
step = math.max(SLOW_RAMP_mB_s * elapsed_s, step)
new_br = math.min(cur_br + step, setpoints.burn_rate)
elseif state == STATES.FAST_RAMP_DOWN then
local scaler = math.min(FAST_MAX_PERCENT_s, FAST_MAX_PERCENT_s * (state_time / 5.0)) * elapsed_s
local step   = scaler * _spctl.data.max_br
step = math.max(SLOW_RAMP_mB_s * elapsed_s, step)
new_br = math.max(cur_br - step, setpoints.burn_rate)
end
_spctl.new_br = math.min(new_br, limits.fuel_max_burn)
if plc_state.limit_force_ramp and (new_br < cur_br) then
log.info("SPCTL: released ramped fuel burn limiting recovery")
plc_state.limit_force_ramp = false
end
if _spctl.new_br ~= setpoints.burn_rate then
_spctl.last_ccool = cur_ccool
else
new_state = STATES.STOPPED
if plc_state.limit_force_ramp then
log.info("SPCTL: completed ramped fuel burn limiting recovery")
plc_state.limit_force_ramp = false
end
end
if new_state ~= state then
log.debug("SPCTL: state changed to " .. (STATE_NAMES[new_state] or "UNKNOWN"))
_spctl.next_state  = new_state
_spctl.last_change = now
end
end
local function ramp_update(reactor, elapsed_s)
if setpoints.burn_rate_en and (setpoints.burn_rate ~= _spctl.last_sp) and rps.is_active() then
parallel.waitForAll(
function () _spctl.data.burn_rate = reactor.getBurnRate() end,
function () _spctl.data.max_br    = reactor.getMaxBurnRate() end
)
local cur_br = _spctl.data.burn_rate
if (type(cur_br) == "number") and (type(_spctl.data.max_br) == "number") and (setpoints.burn_rate ~= cur_br) then
ramp_init(cur_br)
end
end
if _spctl.next_state ~= STATES.STOPPED then
if setpoints.burn_rate_en then
local cur_br, ccool = _spctl.data.burn_rate, _spctl.data.ccool_fill
if not rps.is_active() then
log.info("SPCTL: ramping aborted (reactor inactive)")
setpoints.burn_rate_en = false
ramp_reset()
else
if (type(cur_br) == "number") and (type(ccool) == "number") then
ramp_run(cur_br, ccool, elapsed_s)
else
log.error(util.c("SPCTL: skipped running loop due to bad data (cur_br = ", cur_br, ",cur_ccool = ", ccool, ")"))
end
end
else
log.info("SPCTL: ramping cancelled")
ramp_reset()
end
elseif setpoints.burn_rate_en then
log.info(util.c("SPCTL: ramping completed (setpoint of ", setpoints.burn_rate, " mB/t)"))
setpoints.burn_rate_en = false
ramp_reset()
end
end
local function update_fuel_rate_limiting(tick, reactor)
local fuel_fill = nil
local data      = _spctl.data
if _spctl.fuel_monitoring and (type(data.fuel) == "number") and (type(data.act_rate) == "number") then
fuel_fill = data.fuel_fill
local elapsed_s = (util.time_s() - _spctl.last_mon_check)
_spctl.last_mon_check = util.time_s()
local tps_avg = (data.tps + (1000 / data.tick_time)) / 2
_spctl.fuel_filt.update(data.fuel)
_spctl.rate_filt.update(data.act_rate)
_spctl.tick_filt.update(elapsed_s * tps_avg)
_spctl.d_fuel     = _spctl.fuel_filt.get() - _spctl.last_fuel_filt
_spctl.d_fuel_mBt = _spctl.d_fuel / _spctl.tick_filt.get()
local limit       = math.max(0.01, _spctl.rate_filt.get() + _spctl.d_fuel_mBt)
if _spctl.fuel_limiting then
limits.reportable_max_burn = limit
limits.fuel_max_burn = limit
else
limits.reportable_max_burn = false
limits.fuel_max_burn = math.huge
end
_spctl.last_fuel_filt = _spctl.fuel_filt.get()
elseif tick % 5 == 0 then
fuel_fill = reactor.getFuelFilledPercentage()
end
if fuel_fill then
if (fuel_fill > FUEL_LIMIT_RELEASE) and (_spctl.fuel_monitoring or _spctl.fuel_limiting) then
if _spctl.fuel_limiting and not plc_state.limit_force_ramp then
log.info("SPCTL: forcing auto commands to be ramped for burn limit recovery (limit released)")
plc_state.limit_force_ramp = true
end
_spctl.fuel_monitoring = false
_spctl.fuel_limiting = false
limits.reportable_max_burn = false
limits.fuel_max_burn = math.huge
_spctl.d_fuel = 0
_spctl.d_fuel_mBt = 0
log.info("SPCTL: monitoring fuel terminated / limit released")
elseif _spctl.fuel_monitoring and (not _spctl.fuel_limiting) and (fuel_fill < FUEL_LIMIT_START) then
_spctl.fuel_limiting = true
log.info("SPCTL: fuel limit engaged")
elseif (not _spctl.fuel_monitoring) and (fuel_fill < FUEL_LIMIT_INIT) then
_spctl.fuel_monitoring = true
_spctl.last_mon_check = util.time_s()
_spctl.fuel_filt.reset()
_spctl.rate_filt.reset()
_spctl.tick_filt.reset()
log.info("SPCTL: started monitoring fuel statistics, approaching limiting threshold")
end
end
end
function spctl.update(reactor, tick, nom_elapsed_s)
_spctl.new_br = nil
local update_5Hz = tick % 2 == 0
if _spctl.fuel_monitoring or (_spctl.next_state ~= STATES.STOPPED) or (databus.en_diag and update_5Hz) then
local t_start, t_end = util.time_ms(), 0
parallel.waitForAll(
function () _spctl.data.tps        = util.get_tps() end,
function () _spctl.data.burn_rate  = reactor.getBurnRate() end,
function () _spctl.data.ccool_fill = reactor.getCoolantFilledPercentage() end,
function () _spctl.data.fuel_fill  = reactor.getFuelFilledPercentage() end,
function () _spctl.data.act_rate   = reactor.getActualBurnRate() end,
function ()
_spctl.data.fuel = (reactor.getFuel() or { amount = nil }).amount
t_end            = util.time_ms()
end
)
_spctl.data.tick_time = t_end - t_start
end
if update_5Hz then
ramp_update(reactor, nom_elapsed_s)
end
if plc_state.auto_ctl and _spctl.fuel_limit_en then
update_fuel_rate_limiting(tick, reactor)
elseif _spctl.fuel_monitoring then
limits.reportable_max_burn = false
limits.fuel_max_burn       = math.huge
_spctl.fuel_monitoring = false
_spctl.fuel_limiting   = false
end
if _spctl.new_br then
reactor.setBurnRate(math.min(_spctl.new_br, limits.fuel_max_burn))
elseif plc_state.auto_ctl and _spctl.fuel_limiting and update_5Hz and (_spctl.next_state == STATES.STOPPED) then
local cur_br = _spctl.data.burn_rate
if cur_br > limits.fuel_max_burn then
reactor.setBurnRate(math.min(setpoints.burn_rate, limits.fuel_max_burn))
elseif cur_br < setpoints.burn_rate then
if not (plc_state.limit_force_ramp and setpoints.burn_rate_en) then
log.info("SPCTL: initiating ramped fuel burn limiting recovery")
plc_state.limit_force_ramp = true
setpoints.burn_rate_en = true
end
end
end
if update_5Hz and databus.en_diag then
local publish = databus.ps.publish
publish("spctl_ramp_active", setpoints.burn_rate_en)
publish("spctl_ramp_sp", setpoints.burn_rate)
publish("spctl_ramp_init", _spctl.next_state == STATES.INIT)
publish("spctl_ramp_sru", _spctl.next_state == STATES.SLOW_RAMP_UP)
publish("spctl_ramp_srd", _spctl.next_state == STATES.SLOW_RAMP_DOWN)
publish("spctl_ramp_sw", _spctl.next_state == STATES.STABLE_WAIT)
publish("spctl_ramp_cm", _spctl.next_state == STATES.CCOOL_MON)
publish("spctl_ramp_fru", _spctl.next_state == STATES.FAST_RAMP_UP)
publish("spctl_ramp_frd", _spctl.next_state == STATES.FAST_RAMP_DOWN)
publish("spctl_limit_mon", _spctl.fuel_monitoring)
publish("spctl_limit_lim", _spctl.fuel_limiting)
publish("spctl_limit_fr", plc_state.limit_force_ramp)
publish("spctl_limit_dfuel", _spctl.d_fuel)
publish("spctl_limit_dfuelmbt", _spctl.d_fuel_mBt)
publish("spctl_limit_limit", limits.fuel_max_burn)
publish("spctl_limit_fuel_filt", _spctl.fuel_filt.get())
publish("spctl_limit_rate_filt", _spctl.rate_filt.get())
publish("spctl_limit_tick_filt", _spctl.tick_filt.get())
publish("spctl_data_tps", _spctl.data.tps)
publish("spctl_data_tick", _spctl.data.tick_time)
end
end
return spctl
