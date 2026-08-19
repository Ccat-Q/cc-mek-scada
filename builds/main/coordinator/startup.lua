
require("/initenv").init_env()
local comms       = require("scada-common.comms")
local crash       = require("scada-common.crash")
local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local network     = require("scada-common.network")
local ppm         = require("scada-common.ppm")
local util        = require("scada-common.util")
local backplane   = require("coordinator.backplane")
local configure   = require("coordinator.configure")
local coordinator = require("coordinator.coordinator")
local ioctl       = require("coordinator.ioctl")
local renderer    = require("coordinator.renderer")
local sounder     = require("coordinator.sounder")
local threads     = require("coordinator.threads")
local COORDINATOR_VERSION = "1.10.1"
local CHUNK_LOAD_DELAY_S = 30.0
local println    = util.println
local println_ts = util.println_ts
local log_render = coordinator.log_render
local log_sys    = coordinator.log_sys
local log_boot   = coordinator.log_boot
local log_comms  = coordinator.log_comms
local log_crypto = coordinator.log_crypto
if not coordinator.load_config() then
local success, error = configure.configure(1)
if success then
if not coordinator.load_config() then
println("未能加载有效配置，请重新配置")
return
end
else
println("配置错误：" .. error)
return
end
end
local config = coordinator.config
log.init(config.LogPath, config.LogMode, config.LogDebug)
log.info("========================================")
log.info("BOOTING coordinator.startup v" .. COORDINATOR_VERSION)
log.info("========================================")
println(">> SCADA Coordinator v" .. COORDINATOR_VERSION .. " <<")
crash.set_env("coordinator", COORDINATOR_VERSION)
crash.dbg_log_env()
ppm.mount_all()
local wait_on_load = true
local disp_ok, disp_err = backplane.init_displays(config)
while wait_on_load and (not disp_ok) and os.clock() < CHUNK_LOAD_DELAY_S do
term.clear()
term.setCursorPos(1, 1)
println("启动时出现显示器配置问题。\n")
println("启动将继续每2秒重试，以防区块加载延迟。\n")
println(util.sprintf("如果所有尝试都失败，配置器将在%ds后启动。\n", math.max(0, CHUNK_LOAD_DELAY_S - os.clock())))
println("(点击跳过，直接进入配置器)")
local timer_id = util.start_timer(2)
while true do
local event, param1 = util.pull_event()
if event == "timer" and param1 == timer_id then
ppm.mount_all()
disp_ok, disp_err = backplane.init_displays(config)
break
elseif event == "mouse_click" or event == "terminate" then
wait_on_load = false
break
end
end
end
if not disp_ok then
local success, error = configure.configure(2, disp_err)
if success then
if not coordinator.load_config() then
println("未能加载有效配置，请重新配置")
return
else
disp_ok, disp_err = backplane.init_displays(config)
if not disp_ok then
println(disp_err)
println("请重新配置")
return
end
end
else
println("配置错误：" .. error)
return
end
end
local function main()
ioctl.fp_versions(COORDINATOR_VERSION, comms.version)
renderer.configure(config)
renderer.init_displays(backplane.displays())
renderer.init_dmesg()
log.info("monitors ready, dmesg output incoming...")
log_render("displays connected and reset")
log_sys("system start on " .. os.date("%c"))
log_boot("starting " .. COORDINATOR_VERSION)
if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
local init_time = network.init_mac(config.AuthKey)
log_crypto("HMAC init took " .. init_time .. "ms")
end
local __shared_memory = {
date_format = util.trinary(config.Time24Hour, "%X \x04 %A, %B %d %Y", "%r \x04 %A, %B %d %Y"),
crd_state = {
fp_ok = false,
ui_ok = true,
link_fail = false,
shutdown = false
},
crd_sys = {
coord_comms = nil,
conn_watchdog = nil
},
q = {
mq_render = mqueue.new()
},
q_types = {
MQ__RENDER_CMD = {
START_MAIN_UI = 1,
CLOSE_MAIN_UI = 2
},
MQ__RENDER_DATA = {
MON_CONNECT = 1,
MON_DISCONNECT = 2,
MON_RESIZE = 3
}
}
}
local smem_sys  = __shared_memory.crd_sys
local crd_state = __shared_memory.crd_state
if not backplane.init(config, __shared_memory) then return end
log_render("starting front panel UI...")
local fp_message
crd_state.fp_ok, fp_message = renderer.try_start_fp()
if not crd_state.fp_ok then
log_render(util.c("front panel UI error: ", fp_message))
println_ts("前面板界面创建失败")
log.fatal(util.c("前面板GUI渲染失败，错误为 ", fp_message))
return
else log_render("front panel ready") end
smem_sys.conn_watchdog = util.new_watchdog(config.SVR_Timeout)
smem_sys.conn_watchdog.cancel()
log.debug("startup> conn watchdog created")
smem_sys.coord_comms = coordinator.comms(COORDINATOR_VERSION, backplane, smem_sys.conn_watchdog)
log.debug("startup> comms init")
log_comms("comms initialized")
local main_thread   = threads.thread__main(__shared_memory)
local render_thread = threads.thread__render(__shared_memory)
log.info("startup> completed")
parallel.waitForAll(main_thread.p_exec, render_thread.p_exec)
renderer.close_ui()
renderer.close_fp()
sounder.stop()
log_sys("system shutdown")
if crd_state.link_fail then println_ts("无法连接到监控端") end
if not crd_state.ui_ok then println_ts("主界面创建失败") end
if smem_sys.coord_comms.is_linked() then smem_sys.coord_comms.close() end
println_ts("已退出")
log.info("exited")
end
if not xpcall(main, crash.handler) then
pcall(renderer.close_ui)
pcall(renderer.close_fp)
pcall(sounder.stop)
crash.exit()
else
log.close()
end
