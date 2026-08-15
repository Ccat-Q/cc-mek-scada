
local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local util  = require("scada-common.util")
local F_CMD = comms.FAC_COMMAND
local U_CMD = comms.UNIT_COMMAND
local process = {}
local self = {
io = nil,
comms = nil
}
function process.init(ioctl, pocket_comms)
self.io = ioctl
self.comms = pocket_comms
end
function process.fac_scram()
self.comms.send_fac_command(F_CMD.SCRAM_ALL)
log.debug("PROCESS: FAC SCRAM ALL")
end
function process.fac_ack_alarms()
self.comms.send_fac_command(F_CMD.ACK_ALL_ALARMS)
log.debug("PROCESS: FAC ACK ALL ALARMS")
end
function process.start(id)
self.io.units[id].control_state = true
self.comms.send_unit_command(U_CMD.START, id)
log.debug(util.c("PROCESS: UNIT[", id, "] START"))
end
function process.scram(id)
self.io.units[id].control_state = false
self.comms.send_unit_command(U_CMD.SCRAM, id)
log.debug(util.c("PROCESS: UNIT[", id, "] SCRAM"))
end
function process.reset_rps(id)
self.comms.send_unit_command(U_CMD.RESET_RPS, id)
log.debug(util.c("PROCESS: UNIT[", id, "] RESET RPS"))
end
function process.set_rate(id, rate)
self.comms.send_unit_command(U_CMD.SET_BURN, id, rate)
log.debug(util.c("PROCESS: UNIT[", id, "] SET BURN ", rate))
end
function process.set_group(unit_id, group_id)
self.comms.send_unit_command(U_CMD.SET_GROUP, unit_id, group_id)
log.debug(util.c("PROCESS: UNIT[", unit_id, "] SET GROUP ", group_id))
end
function process.set_unit_waste(id, mode)
self.comms.send_unit_command(U_CMD.SET_WASTE, id, mode)
log.debug(util.c("PROCESS: UNIT[", id, "] SET WASTE ", mode))
end
function process.ack_all_alarms(id)
self.comms.send_unit_command(U_CMD.ACK_ALL_ALARMS, id)
log.debug(util.c("PROCESS: UNIT[", id, "] ACK ALL ALARMS"))
end
function process.ack_alarm(id, alarm)
self.comms.send_unit_command(U_CMD.ACK_ALARM, id, alarm)
log.debug(util.c("PROCESS: UNIT[", id, "] ACK ALARM ", alarm))
end
function process.reset_alarm(id, alarm)
self.comms.send_unit_command(U_CMD.RESET_ALARM, id, alarm)
log.debug(util.c("PROCESS: UNIT[", id, "] RESET ALARM ", alarm))
end
function process.process_start(mode, burn_target, range_start, range_stop, charge_target, gen_target, limits)
self.comms.send_auto_start({ mode, burn_target, range_start, range_stop, charge_target, gen_target, limits })
log.debug("PROCESS: START AUTO CTRL")
end
function process.process_stop()
self.comms.send_fac_command(F_CMD.STOP)
log.debug("PROCESS: STOP AUTO CTRL")
end
function process.set_process_waste(product)
self.comms.send_fac_command(F_CMD.SET_WASTE_MODE, product)
log.debug(util.c("PROCESS: SET WASTE ", product))
end
function process.set_pu_fallback(enabled)
self.comms.send_fac_command(F_CMD.SET_PU_FB, enabled)
log.debug(util.c("PROCESS: SET PU FALLBACK ", enabled))
end
function process.set_sps_low_power(enabled)
self.comms.send_fac_command(F_CMD.SET_SPS_LP, enabled)
log.debug(util.c("PROCESS: SET SPS LOW POWER ", enabled))
end
return process
