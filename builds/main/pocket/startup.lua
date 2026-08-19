
pocket = pocket or periphemu
local _is_pocket_env = pocket
require("/initenv").init_env()
local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local util      = require("scada-common.util")
local configure = require("pocket.configure")
local ioctl     = require("pocket.ioctl")
local pocket    = require("pocket.pocket")
local renderer  = require("pocket.renderer")
local threads   = require("pocket.threads")
local POCKET_VERSION = "1.3.2"
local println = util.println
local println_ts = util.println_ts
if not _is_pocket_env then
println("此应用程序只能在口袋电脑上使用。")
return
end
if not pocket.load_config() then
local success, error = configure.configure(true)
if success then
if not pocket.load_config() then
println("无法加载有效配置，请重新配置")
return
end
else
println("配置错误：" .. error)
return
end
end
local config = pocket.config
log.init(config.LogPath, config.LogMode, config.LogDebug)
log.info("========================================")
log.info("BOOTING pocket.startup v" .. POCKET_VERSION)
log.info("========================================")
crash.set_env("pocket", POCKET_VERSION)
crash.dbg_log_env()
local function main()
ppm.mount_all()
ioctl.get_db().version = POCKET_VERSION
local __shared_memory = {
pkt_state = {
ui_ok = false,
ui_error = nil,
shutdown = false
},
pkt_dev = {
modem = ppm.get_wireless_modem()
},
pkt_sys = {
nic = nil,
pocket_comms = nil,
sv_wd = nil,
api_wd = nil,
nav = nil
},
q = {
mq_render = mqueue.new()
}
}
local smem_dev = __shared_memory.pkt_dev
local smem_sys = __shared_memory.pkt_sys
local pkt_state = __shared_memory.pkt_state
smem_sys.nav = pocket.init_nav(__shared_memory)
if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
network.init_mac(config.AuthKey)
end
ioctl.report_link_state(ioctl.LINK_STATE.UNLINKED)
if smem_dev.modem == nil then
println("启动> 未找到无线调制解调器：请合成带无线调制解调器的口袋电脑")
log.fatal("startup> no wireless modem on startup")
return
end
smem_sys.sv_wd = util.new_watchdog(config.ConnTimeout)
smem_sys.sv_wd.cancel()
smem_sys.api_wd = util.new_watchdog(config.ConnTimeout)
smem_sys.api_wd.cancel()
log.debug("startup> conn watchdogs created")
smem_sys.nic = network.nic(smem_dev.modem)
smem_sys.pocket_comms = pocket.comms(POCKET_VERSION, smem_sys.nic, smem_sys.sv_wd, smem_sys.api_wd, smem_sys.nav)
log.debug("startup> comms init")
ioctl.init_core(smem_sys.pocket_comms, smem_sys.nav, config)
local ui_message
pkt_state.ui_ok, ui_message = renderer.try_start_ui()
if not pkt_state.ui_ok then
println(util.c("界面错误：", ui_message))
log.error(util.c("startup> GUI render failed with error ", ui_message))
end
if pkt_state.ui_ok then
local main_thread   = threads.thread__main(__shared_memory)
local render_thread = threads.thread__render(__shared_memory)
log.info("startup> completed")
parallel.waitForAll(main_thread.p_exec, render_thread.p_exec)
renderer.close_ui()
if not pkt_state.ui_ok then
println(util.c("界面崩溃，错误：", pkt_state.ui_error))
end
else
println_ts("界面创建失败")
end
println_ts("已退出")
log.info("exited")
end
if not xpcall(main, crash.handler) then
pcall(renderer.close_ui)
crash.exit()
else
log.close()
end
