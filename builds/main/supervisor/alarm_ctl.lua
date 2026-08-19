local log   = require("scada-common.log")
local types = require("scada-common.types")
local util  = require("scada-common.util")
local ALARM_STATE = types.ALARM_STATE
local AISTATE_NAMES = {
"INACTIVE",
"TRIPPING",
"TRIPPED",
"ACKED",
"RING_BACK",
"RING_BACK_TRIPPING"
}
local AISTATE = {
INACTIVE = 1,
TRIPPING = 2,
TRIPPED = 3,
ACKED = 4,
RING_BACK = 5,
RING_BACK_TRIPPING = 6
}
local alarm_ctl = {}
alarm_ctl.AISTATE = AISTATE
alarm_ctl.AISTATE_NAMES = AISTATE_NAMES
function alarm_ctl.update_alarm_state(caller_tag, alarm_states, tripped, alarm, no_ring_back)
local int_state = alarm.state
local ext_state = alarm_states[alarm.id]
if int_state == AISTATE.INACTIVE then
if tripped then
alarm.trip_time = util.time_ms()
if alarm.hold_time > 0 then
alarm.state = AISTATE.TRIPPING
alarm_states[alarm.id] = ALARM_STATE.INACTIVE
else
alarm.state = AISTATE.TRIPPED
alarm_states[alarm.id] = ALARM_STATE.TRIPPED
log.info(util.c(caller_tag, " 警报 ", alarm.id, " (", types.ALARM_NAMES[alarm.id], "): 已跳闸 [优先级 ",
types.ALARM_PRIORITY_NAMES[alarm.tier],"]"))
end
else
alarm.trip_time = util.time_ms()
alarm_states[alarm.id] = ALARM_STATE.INACTIVE
end
elseif (int_state == AISTATE.TRIPPING) or (int_state == AISTATE.RING_BACK_TRIPPING) then
if tripped then
local elapsed = util.time_ms() - alarm.trip_time
if elapsed > (alarm.hold_time * 1000) then
alarm.state = AISTATE.TRIPPED
alarm_states[alarm.id] = ALARM_STATE.TRIPPED
log.info(util.c(caller_tag, " 警报 ", alarm.id, " (", types.ALARM_NAMES[alarm.id], "): 已跳闸 [优先级 ",
types.ALARM_PRIORITY_NAMES[alarm.tier],"]"))
end
elseif int_state == AISTATE.RING_BACK_TRIPPING then
alarm.trip_time = 0
alarm.state = AISTATE.RING_BACK
alarm_states[alarm.id] = ALARM_STATE.RING_BACK
else
alarm.trip_time = 0
alarm.state = AISTATE.INACTIVE
alarm_states[alarm.id] = ALARM_STATE.INACTIVE
end
elseif int_state == AISTATE.TRIPPED then
if tripped then
if ext_state == ALARM_STATE.ACKED then
alarm.state = AISTATE.ACKED
end
elseif no_ring_back then
alarm.state = AISTATE.INACTIVE
alarm_states[alarm.id] = ALARM_STATE.INACTIVE
else
alarm.state = AISTATE.RING_BACK
alarm_states[alarm.id] = ALARM_STATE.RING_BACK
end
elseif int_state == AISTATE.ACKED then
if not tripped then
if no_ring_back then
alarm.state = AISTATE.INACTIVE
alarm_states[alarm.id] = ALARM_STATE.INACTIVE
else
alarm.state = AISTATE.RING_BACK
alarm_states[alarm.id] = ALARM_STATE.RING_BACK
end
end
elseif int_state == AISTATE.RING_BACK then
if tripped then
alarm.trip_time = util.time_ms()
if alarm.hold_time > 0 then
alarm.state = AISTATE.RING_BACK_TRIPPING
else
alarm.state = AISTATE.TRIPPED
alarm_states[alarm.id] = ALARM_STATE.TRIPPED
end
elseif ext_state == ALARM_STATE.INACTIVE then
alarm.state = AISTATE.INACTIVE
alarm.trip_time = 0
end
else
log.error(util.c(caller_tag, " 警报 ", alarm.id, " 的状态无效"), true)
end
if alarm.state ~= int_state then
local change_str = util.c(AISTATE_NAMES[int_state], " -> ", AISTATE_NAMES[alarm.state])
log.debug(util.c(caller_tag, " 警报 ", alarm.id, " (", types.ALARM_NAMES[alarm.id], "): ", change_str))
return alarm.state == AISTATE.TRIPPED
else return false end
end
return alarm_ctl
