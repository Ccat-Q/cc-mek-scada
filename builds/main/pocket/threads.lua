local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local ppm      = require("scada-common.ppm")
local tcd      = require("scada-common.tcd")
local util     = require("scada-common.util")
local pocket   = require("pocket.pocket")
local renderer = require("pocket.renderer")
local core     = require("graphics.core")
local threads = {}
local MAIN_CLOCK   = 0.5
local RENDER_SLEEP = 100
local MQ__RENDER_DATA = pocket.MQ__RENDER_DATA
function threads.thread__main(smem)
local public = {}
function public.exec()
log.debug("main thread start")
local loop_clock = util.new_clock(MAIN_CLOCK)
loop_clock.start()
local pkt_state    = smem.pkt_state
local pocket_comms = smem.pkt_sys.pocket_comms
local sv_wd        = smem.pkt_sys.sv_wd
local api_wd       = smem.pkt_sys.api_wd
local nav          = smem.pkt_sys.nav
local nic          = smem.pkt_sys.nic
local function loop_tick()
pocket_comms.link_update()
if nav.get_current_page() then
local page_tasks = nav.get_current_page().tasks
for i = 1, #page_tasks do page_tasks[i]() end
end
nic.periodic()
loop_clock.start()
end
sv_wd.feed()
api_wd.feed()
log.debug("startup> conn watchdogs started")
while true do
local event, param1, param2, param3, param4, param5 = util.pull_event()
if event == "modem_message" then
local packet = pocket_comms.parse_packet(param1, param2, param3, param4, param5)
pocket_comms.handle_packet(packet)
elseif event == "timer" then
if loop_clock.is_clock(param1) then
loop_tick()
elseif sv_wd.is_timer(param1) then
log.info("supervisor server timeout")
pocket_comms.close_sv()
elseif api_wd.is_timer(param1) then
log.info("coordinator api server timeout")
pocket_comms.close_api()
else
tcd.handle(param1)
end
elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or
event == "double_click" then
renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
elseif event == "char" or event == "key" or event == "key_up" then
renderer.handle_key(core.events.new_key_event(event, param1, param2))
elseif event == "paste" then
renderer.handle_paste(param1)
end
if event == "terminate" or ppm.should_terminate() then
log.info("terminate requested, main thread exiting")
pkt_state.shutdown = true
elseif not pkt_state.ui_ok then
pkt_state.shutdown = true
log.info("terminating due to fatal UI error")
end
if pkt_state.shutdown then
log.info("closing server connections...")
pocket_comms.close()
log.info("connections closed")
break
end
end
end
function public.p_exec()
local pkt_state = smem.pkt_state
while not pkt_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
if not pkt_state.shutdown then
log.info("main thread restarting now...")
end
end
end
return public
end
function threads.thread__render(smem)
local public = {}
function public.exec()
log.debug("render thread start")
local pkt_state    = smem.pkt_state
local nav          = smem.pkt_sys.nav
local render_queue = smem.q.mq_render
local last_update = util.time()
while true do
while render_queue.ready() and not pkt_state.shutdown do
local msg = render_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.DATA then
local cmd = msg.message
if cmd.key == MQ__RENDER_DATA.LOAD_APP then
log.debug("RENDER: load app " .. cmd.val[1])
local draw_start = util.time_ms()
pkt_state.ui_ok, pkt_state.ui_error = pcall(function () nav.load_app(cmd.val[1]) end)
if not pkt_state.ui_ok then
log.fatal(util.c("RENDER: app load failed with error ", pkt_state.ui_error))
else
log.debug("RENDER: app loaded in " .. (util.time_ms() - draw_start) .. "ms")
if type(cmd.val[2]) == "function" then cmd.val[2]() end
end
end
end
end
util.nop()
end
if pkt_state.shutdown then
log.info("render thread exiting")
break
end
last_update = util.adaptive_delay(RENDER_SLEEP, last_update)
end
end
function public.p_exec()
local pkt_state = smem.pkt_state
while not pkt_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
if not pkt_state.shutdown then
log.info("render thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
return threads
