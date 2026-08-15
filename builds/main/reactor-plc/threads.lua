local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local ppm       = require("scada-common.ppm")
local tcd       = require("scada-common.tcd")
local util      = require("scada-common.util")
local backplane = require("reactor-plc.backplane")
local databus   = require("reactor-plc.databus")
local renderer  = require("reactor-plc.renderer")
local spctl     = require("reactor-plc.spctl")
local core      = require("graphics.core")
local threads = {}
local MAIN_CLOCK    = 0.5
local RPS_SLEEP     = 250
local COMMS_SLEEP   = 150
local SP_CTRL_SLEEP = 100
function threads.thread__main(smem)
local function println_ts(message) if not smem.plc_state.fp_ok then util.println_ts(message) end end
local public = {}
function public.exec()
databus.tx_rt_status("main", true)
log.debug("OS: main thread start")
local LINK_TICKS = 2
local ticks_to_update = 0
local loop_clock = util.new_clock(MAIN_CLOCK)
local networked     = smem.networked
local plc_state     = smem.plc_state
local rps           = smem.plc_sys.rps
local plc_comms     = smem.plc_sys.plc_comms
local conn_watchdog = smem.plc_sys.conn_watchdog
local MQ__RPS_CMD   = smem.q_types.MQ__RPS_CMD
local MQ__COMM_CMD  = smem.q_types.MQ__COMM_CMD
local function loop_tick()
databus.heartbeat()
loop_clock.start()
backplane.periodic()
if networked then
if plc_comms.is_linked() then
smem.q.mq_comms_tx.push_command(MQ__COMM_CMD.SEND_STATUS)
plc_comms.manage_failover(backplane.active_nic())
elseif ticks_to_update == 0 then
local a_nic, s_nic = backplane.active_nic(), backplane.standby_nic()
if a_nic.is_network_up() then
plc_comms.send_link_req(a_nic)
elseif s_nic and s_nic.is_network_up() then
plc_comms.send_link_req(s_nic)
end
ticks_to_update = LINK_TICKS
else
ticks_to_update = ticks_to_update - 1
end
end
if (not plc_state.reactor_formed) and rps.is_formed() then
plc_state.reactor_formed = true
println_ts("reactor is now formed")
log.info("reactor is now formed")
if (not networked) or backplane.active_nic().is_connected() then
plc_state.degraded = false
end
smem.q.mq_rps.push_command(MQ__RPS_CMD.RESET_REATTACH)
elseif plc_state.reactor_formed and (rps.is_formed() == false) then
println_ts("reactor is no longer formed")
log.info("reactor is no longer formed")
plc_state.reactor_formed = false
plc_state.degraded = true
end
databus.tx_hw_status(plc_state)
end
loop_clock.start()
while true do
local event, param1, param2, param3, param4, param5 = util.pull_event()
if event == "modem_message" and networked then
local packet = plc_comms.parse_packet(param1, param2, param3, param4, param5)
if packet ~= nil then
smem.q.mq_comms_rx.push_network(packet)
end
elseif event == "timer" then
if loop_clock.is_clock(param1) then
loop_tick()
elseif networked and conn_watchdog.is_timer(param1) then
plc_comms.close()
smem.q.mq_rps.push_command(MQ__RPS_CMD.TRIP_TIMEOUT)
else
tcd.handle(param1)
end
elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or
event == "double_click" then
renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
elseif event == "peripheral" then
local type, device = ppm.mount(param1)
if type ~= nil and device ~= nil then
backplane.attach(param1, type, device, println_ts)
end
databus.tx_hw_status(plc_state)
elseif event == "peripheral_detach" then
local type, device = ppm.handle_unmount(param1)
if type ~= nil and device ~= nil then
backplane.detach(param1, type, device, println_ts)
end
databus.tx_hw_status(plc_state)
end
if event == "terminate" or ppm.should_terminate() then
log.info("OS: terminate requested, main thread exiting")
plc_state.shutdown = true
break
end
end
end
function public.p_exec()
local plc_state = smem.plc_state
while not plc_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("main", false)
if not plc_state.shutdown then
log.info("OS: main thread restarting now...")
end
end
end
return public
end
function threads.thread__rps(smem)
local function println_ts(message) if not smem.plc_state.fp_ok then util.println_ts(message) end end
local public = {}
function public.exec()
databus.tx_rt_status("rps", true)
log.debug("OS: rps thread start")
local networked   = smem.networked
local plc_state   = smem.plc_state
local rps         = smem.plc_sys.rps
local plc_comms   = smem.plc_sys.plc_comms
local rps_queue   = smem.q.mq_rps
local MQ__RPS_CMD = smem.q_types.MQ__RPS_CMD
local was_linked  = false
local last_update = util.time()
while true do
if networked and not plc_comms.is_linked() then
if was_linked then
was_linked = false
rps.trip_timeout()
end
else was_linked = true end
if (not plc_state.no_reactor) and rps.is_formed() then
local active = rps.check_active()
databus.tx_reactor_state(active)
if rps.is_tripped() and active then rps.scram() end
end
if not (networked or smem.plc_state.fp_ok) then rps.reset(true) end
local rps_tripped, rps_status_string, rps_first = rps.check(not plc_state.no_reactor)
if rps_tripped and rps_first then
println_ts("RPS: SCRAM on safety trip (" .. rps_status_string .. ")")
if networked then plc_comms.send_rps_alarm(rps_status_string) end
end
while rps_queue.ready() and not plc_state.shutdown do
local msg = rps_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.COMMAND then
if msg.message == MQ__RPS_CMD.SCRAM then
log.info("RPS: OS requested SCRAM")
rps.scram()
elseif msg.message == MQ__RPS_CMD.DEGRADED_SCRAM then
log.info("RPS: received PLC degraded alert")
rps.trip_fault()
elseif msg.message == MQ__RPS_CMD.TRIP_TIMEOUT then
println_ts("RPS: supervisor timeout")
log.warning("RPS: received supervisor timeout alert")
rps.trip_timeout()
elseif msg.message == MQ__RPS_CMD.RESET_REATTACH then
rps.reset_reattach()
end
end
end
util.nop()
end
if plc_state.shutdown then
log.info("OS: rps thread shutdown initiated")
if rps.scram() then
println_ts("exiting, reactor disabled")
log.info("OS: rps thread reactor SCRAM OK on exit")
else
println_ts("exiting, reactor failed to disable")
log.error("OS: rps thread failed to SCRAM reactor on exit")
end
log.info("OS: rps thread exiting")
break
end
last_update = util.adaptive_delay(RPS_SLEEP, last_update)
end
end
function public.p_exec()
local plc_state = smem.plc_state
while not plc_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("rps", false)
if not plc_state.shutdown then
smem.plc_sys.rps.scram()
log.info("OS: rps thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
function threads.thread__comms_tx(smem)
local public = {}
function public.exec()
databus.tx_rt_status("comms_tx", true)
log.debug("OS: comms tx thread start")
local plc_state    = smem.plc_state
local plc_comms    = smem.plc_sys.plc_comms
local comms_queue  = smem.q.mq_comms_tx
local MQ__COMM_CMD = smem.q_types.MQ__COMM_CMD
local last_update = util.time()
while true do
while comms_queue.ready() and not plc_state.shutdown do
local msg = comms_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.COMMAND then
if msg.message == MQ__COMM_CMD.SEND_STATUS then
plc_comms.send_status(plc_state.no_reactor, plc_state.reactor_formed)
plc_comms.send_rps_status()
end
end
end
util.nop()
end
if plc_state.shutdown then
log.info("OS: comms tx thread exiting")
break
end
last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
end
end
function public.p_exec()
local plc_state = smem.plc_state
while not plc_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("comms_tx", false)
if not plc_state.shutdown then
log.info("OS: comms tx thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
function threads.thread__comms_rx(smem)
local function println_ts(message) if not smem.plc_state.fp_ok then util.println_ts(message) end end
local public = {}
function public.exec()
databus.tx_rt_status("comms_rx", true)
log.debug("OS: comms rx thread start")
local plc_state   = smem.plc_state
local plc_comms   = smem.plc_sys.plc_comms
local comms_queue = smem.q.mq_comms_rx
local last_update = util.time()
while true do
while comms_queue.ready() and not plc_state.shutdown do
local msg = comms_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.NETWORK then
plc_comms.handle_packet(msg.message, println_ts)
end
end
util.nop()
end
if plc_state.shutdown then
log.info("OS: comms rx thread exiting")
break
end
last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
end
end
function public.p_exec()
local plc_state = smem.plc_state
while not plc_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("comms_rx", false)
if not plc_state.shutdown then
log.info("OS: comms rx thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
function threads.thread__setpoint_control(smem)
local public = {}
function public.exec()
databus.tx_rt_status("spctl", true)
log.debug("OS: setpoint control thread start")
local plc_state = smem.plc_state
local plc_dev   = smem.plc_dev
local last_update = util.time()
local nom_elapsed_s = SP_CTRL_SLEEP / 1000.0
local tick = 0
spctl.init(smem)
while true do
if not plc_state.no_reactor then
tick = tick + 1
spctl.update(plc_dev.reactor, tick, nom_elapsed_s)
end
if plc_state.shutdown then
log.info("OS: setpoint control thread exiting")
break
end
last_update = util.adaptive_delay(SP_CTRL_SLEEP, last_update)
end
end
function public.p_exec()
local plc_state = smem.plc_state
while not plc_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("spctl", false)
if not plc_state.shutdown then
log.info("OS: setpoint control thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
return threads
