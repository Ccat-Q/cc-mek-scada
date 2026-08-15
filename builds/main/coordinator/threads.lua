local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local ppm         = require("scada-common.ppm")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")
local backplane   = require("coordinator.backplane")
local coordinator = require("coordinator.coordinator")
local ioctl       = require("coordinator.ioctl")
local process     = require("coordinator.process")
local renderer    = require("coordinator.renderer")
local sounder     = require("coordinator.sounder")
local apisessions = require("coordinator.session.apisessions")
local core        = require("graphics.core")
local log_render = coordinator.log_render
local log_sys    = coordinator.log_sys
local log_comms  = coordinator.log_comms
local threads = {}
local MAIN_CLOCK   = 0.5
local RENDER_SLEEP = 100
function threads.thread__main(smem)
local public = {}
function public.exec()
ioctl.fp_rt_status("main", true)
log.debug("OS: main thread start")
local loop_clock = util.new_clock(MAIN_CLOCK)
loop_clock.start()
log_sys("system started successfully")
local crd_state       = smem.crd_state
local coord_comms     = smem.crd_sys.coord_comms
local conn_watchdog   = smem.crd_sys.conn_watchdog
local MQ__RENDER_CMD  = smem.q_types.MQ__RENDER_CMD
local MQ__RENDER_DATA = smem.q_types.MQ__RENDER_DATA
local function loop_tick()
ioctl.heartbeat()
backplane.periodic()
local ok, start_ui = coord_comms.manage_link()
if not ok then
crd_state.link_fail = true
crd_state.shutdown = true
log_sys("supervisor connection failed, shutting down...")
log.fatal("failed to connect to supervisor")
return true
elseif start_ui then
log_sys("supervisor connected, dispatching main UI start")
smem.q.mq_render.push_command(MQ__RENDER_CMD.START_MAIN_UI)
end
apisessions.iterate_all()
apisessions.free_all_closed()
process.clear_timed_out()
if renderer.ui_ready() then
ioctl.get_db().facility.ps.publish("date_time", os.date(smem.date_format))
end
loop_clock.start()
return false
end
while true do
local event, param1, param2, param3, param4, param5 = util.pull_event()
if event == "modem_message" then
local packet = coord_comms.parse_packet(param1, param2, param3, param4, param5)
if coord_comms.handle_packet(packet) then
log_comms("supervisor closed connection")
smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
coord_comms.close()
sounder.stop()
end
elseif event == "timer" then
if loop_clock.is_clock(param1) then
if loop_tick() then break end
elseif conn_watchdog.is_timer(param1) then
log_comms("supervisor server timeout")
smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
coord_comms.close()
sounder.stop()
elseif not apisessions.check_all_watchdogs(param1) then
tcd.handle(param1)
end
elseif event == "speaker_audio_empty" then
sounder.continue()
elseif event == "monitor_touch" or event == "mouse_click" or event == "mouse_up" or
event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
elseif event == "monitor_resize" then
smem.q.mq_render.push_data(MQ__RENDER_DATA.MON_RESIZE, param1)
elseif event == "peripheral" then
local type, device = ppm.mount(param1)
if type ~= nil and device ~= nil then
backplane.attach(type, device, param1)
end
elseif event == "peripheral_detach" then
local type, device = ppm.handle_unmount(param1)
if type ~= nil and device ~= nil then
backplane.detach(type, device, param1)
end
end
if event == "terminate" or ppm.should_terminate() then
crd_state.shutdown = true
log.info("OS: terminate requested, main thread exiting")
elseif not crd_state.ui_ok then
crd_state.shutdown = true
log.info("OS: terminating due to fatal UI error")
end
if crd_state.shutdown then
coord_comms.manage_link(true)
if coord_comms.is_linked() then
log_comms("closing supervisor connection...")
else crd_state.link_fail = true end
coord_comms.close()
log_comms("supervisor connection closed")
log_comms("closing api sessions...")
apisessions.close_all()
log_comms("api sessions closed")
break
end
end
end
function public.p_exec()
local crd_state = smem.crd_state
while not crd_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
ioctl.fp_rt_status("main", false)
if not crd_state.shutdown then
log.info("OS: main thread restarting now...")
end
end
end
return public
end
function threads.thread__render(smem)
local public = {}
function public.exec()
ioctl.fp_rt_status("render", true)
log.debug("OS: render thread start")
local crd_state       = smem.crd_state
local render_queue    = smem.q.mq_render
local MQ__RENDER_CMD  = smem.q_types.MQ__RENDER_CMD
local MQ__RENDER_DATA = smem.q_types.MQ__RENDER_DATA
local last_update = util.time()
while true do
while render_queue.ready() and not crd_state.shutdown do
local msg = render_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.COMMAND then
if msg.message == MQ__RENDER_CMD.START_MAIN_UI then
if renderer.ui_ready() then
log_render("closing main UI before executing new request to start")
renderer.close_ui()
end
log_render("starting main UI...")
local draw_start = util.time_ms()
local ui_message
crd_state.ui_ok, ui_message = renderer.try_start_ui()
if not crd_state.ui_ok then
log_render(util.c("main UI error: ", ui_message))
log.fatal(util.c("main GUI render failed with error ", ui_message))
else
log_render("main UI draw took " .. (util.time_ms() - draw_start) .. "ms")
end
elseif msg.message == MQ__RENDER_CMD.CLOSE_MAIN_UI then
if renderer.ui_ready() then
log_render("closing main UI...")
renderer.close_ui()
log_render("main UI closed")
end
end
elseif msg.qtype == mqueue.TYPE.DATA then
local cmd = msg.message
if cmd.key == MQ__RENDER_DATA.MON_CONNECT then
renderer.handle_reconnect(cmd.val)
elseif cmd.key == MQ__RENDER_DATA.MON_DISCONNECT then
renderer.handle_disconnect(cmd.val)
elseif cmd.key == MQ__RENDER_DATA.MON_RESIZE then
local is_used, is_ok = renderer.handle_resize(cmd.val)
if is_used then
log_sys(util.c("configured monitor ", cmd.val, " resized, ", util.trinary(is_ok, "display fits", "display does not fit")))
end
end
end
end
util.nop()
end
if crd_state.shutdown then
log.info("OS: render thread exiting")
break
end
last_update = util.adaptive_delay(RENDER_SLEEP, last_update)
end
end
function public.p_exec()
local crd_state = smem.crd_state
while not crd_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
ioctl.fp_rt_status("render", false)
if not crd_state.shutdown then
log.info("OS: render thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
return threads
