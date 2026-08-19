local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local ppm          = require("scada-common.ppm")
local tcd          = require("scada-common.tcd")
local types        = require("scada-common.types")
local util         = require("scada-common.util")
local backplane    = require("rtu.backplane")
local databus      = require("rtu.databus")
local modbus       = require("rtu.modbus")
local renderer     = require("rtu.renderer")
local boilerv_rtu  = require("rtu.dev.boilerv_rtu")
local dynamicv_rtu = require("rtu.dev.dynamicv_rtu")
local ecore_rtu    = require("rtu.dev.ecore_rtu")
local envd_rtu     = require("rtu.dev.envd_rtu")
local imatrix_rtu  = require("rtu.dev.imatrix_rtu")
local sna_rtu      = require("rtu.dev.sna_rtu")
local sps_rtu      = require("rtu.dev.sps_rtu")
local turbinev_rtu = require("rtu.dev.turbinev_rtu")
local core         = require("graphics.core")
local threads = {}
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local RTU_HW_STATE = databus.RTU_HW_STATE
local MAIN_CLOCK  = 0.5
local COMMS_SLEEP = 100
local function handle_unit_mount(smem, println_ts, iface, type, device, unit)
local sys = smem.rtu_sys
if unit.name == iface then
local resend_advert, faulted, unknown, invalid = false, false, false, false
local function fail(msg)
invalid = true
log.error(msg .. " 位于配置中")
end
unit.device = device
if unit.type == RTU_UNIT_TYPE.VIRTUAL then
resend_advert = true
if type == "boilerValve" then
if unit.reactor < 1 or unit.reactor > 4 then fail(util.c("锅炉 '", unit.name, "' 无法初始化，未分配到有效机组")) end
if (unit.index == false) or unit.index < 1 or unit.index > 2 then fail(util.c("锅炉 '", unit.name, "' 无法初始化，提供的索引无效")) end
unit.type = RTU_UNIT_TYPE.BOILER_VALVE
elseif type == "turbineValve" then
if unit.reactor < 1 or unit.reactor > 4 then fail(util.c("涡轮机 '", unit.name, "' 无法初始化，未分配到有效机组")) end
if (unit.index == false) or unit.index < 1 or unit.index > 3 then fail(util.c("涡轮机 '", unit.name, "' 无法初始化，提供的索引无效")) end
unit.type = RTU_UNIT_TYPE.TURBINE_VALVE
elseif type == "dynamicValve" then
if unit.reactor < 0 or unit.reactor > 4 then fail(util.c("动态储罐 '", unit.name, "' 无法初始化，未提供有效分配")) end
if (unit.reactor == 0 and ((unit.index == false) or unit.index < 1 or unit.index > 4)) or
(unit.reactor > 0 and unit.index ~= 1) then
fail(util.c("动态储罐 '", unit.name, "' 无法初始化，提供的索引无效"))
end
unit.type = RTU_UNIT_TYPE.DYNAMIC_VALVE
elseif type == "inductionPort" or type == "reinforcedInductionPort" then
if unit.reactor ~= 0 then fail(util.c("感应矩阵 '", unit.name, "' 无法初始化，未分配到设施")) end
unit.type = RTU_UNIT_TYPE.IMATRIX
elseif type == "spsPort" then
if unit.reactor ~= 0 then fail(util.c("SPS '", unit.name, "' 无法初始化，未分配到设施")) end
unit.type = RTU_UNIT_TYPE.SPS
elseif type == "solarNeutronActivator" or type == "largeSolarNeutronActivator" then
if unit.reactor < 1 or unit.reactor > 4 then fail(util.c("SNA '", unit.name, "' 无法初始化，未分配到有效机组")) end
unit.type = RTU_UNIT_TYPE.SNA
elseif type == "environmentDetector" or type == "environment_detector"  then
if unit.reactor < 0 or unit.reactor > 4 then fail(util.c("环境探测器 '", unit.name, "' 无法初始化，未提供有效分配")) end
if (unit.index == false) or unit.index < 1 then fail(util.c("环境探测器 '", unit.name, "' 无法初始化，提供的索引无效")) end
unit.type = RTU_UNIT_TYPE.ENV_DETECTOR
elseif type == "draconic_rf_storage" then
if unit.reactor ~= 0 then fail(util.c("能量核心 '", unit.name, "' 无法初始化，未分配到设施")) end
unit.type = RTU_UNIT_TYPE.ENERGY_CORE
else
resend_advert = false
log.error(util.c("虚拟设备 '", unit.name, "' 无法初始化为未知类型 (", type, ")"))
end
databus.tx_unit_hw_type(unit.uid, unit.type)
end
if invalid then
unit.hw_state = RTU_HW_STATE.OFFLINE
databus.tx_unit_hw_status(unit.uid, unit.hw_state)
return
end
if unit.type == RTU_UNIT_TYPE.BOILER_VALVE then
unit.rtu, faulted = boilerv_rtu.new(device)
unit.formed = util.trinary(faulted, false, nil)
elseif unit.type == RTU_UNIT_TYPE.TURBINE_VALVE then
unit.rtu, faulted = turbinev_rtu.new(device)
unit.formed = util.trinary(faulted, false, nil)
elseif unit.type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
unit.rtu, faulted = dynamicv_rtu.new(device)
unit.formed = util.trinary(faulted, false, nil)
elseif unit.type == RTU_UNIT_TYPE.IMATRIX then
unit.rtu, faulted = imatrix_rtu.new(device)
unit.formed = util.trinary(faulted, false, nil)
elseif unit.type == RTU_UNIT_TYPE.SPS then
unit.rtu, faulted = sps_rtu.new(device)
unit.formed = util.trinary(faulted, false, nil)
elseif unit.type == RTU_UNIT_TYPE.SNA then
unit.rtu, faulted = sna_rtu.new(device)
elseif unit.type == RTU_UNIT_TYPE.ENV_DETECTOR then
unit.rtu, faulted = envd_rtu.new(device)
elseif unit.type == RTU_UNIT_TYPE.ENERGY_CORE then
unit.rtu, faulted = ecore_rtu.new(device)
elseif unit.type == RTU_UNIT_TYPE.REDSTONE then
unit.rtu.remount_phy(device)
else
unknown = true
log.error(util.c("无法识别重连的 RTU 单元类型 (", unit.name, ")"), true)
end
if unit.is_multiblock then
unit.hw_state = RTU_HW_STATE.UNFORMED
if unit.formed == false then
log.info(util.c("假设 ", unit.name, " 在初始化时因 PPM 故障而未成型"))
end
elseif faulted then
unit.hw_state = RTU_HW_STATE.FAULTED
elseif not unknown then
unit.hw_state = RTU_HW_STATE.OK
else
unit.hw_state = RTU_HW_STATE.OFFLINE
end
databus.tx_unit_hw_status(unit.uid, unit.hw_state)
if not unknown then
unit.modbus_io = modbus.new(unit.rtu, true)
local type_name = types.rtu_type_to_string(unit.type)
local message = util.c("已在接口 ", unit.name, " 上重连 ", type_name)
println_ts(message)
log.info(message)
if resend_advert then
sys.rtu_comms.send_advertisement(sys.units)
else
sys.rtu_comms.send_remounted(unit.uid)
end
end
end
end
function threads.thread__main(smem)
local function println_ts(message) if not smem.rtu_state.fp_ok then util.println_ts(message) end end
local public = {}
function public.exec()
databus.tx_rt_status("main", true)
log.debug("OS: main thread start")
local loop_clock = util.new_clock(MAIN_CLOCK)
local rtu_state     = smem.rtu_state
local rtu_comms     = smem.rtu_sys.rtu_comms
local conn_watchdog = smem.rtu_sys.conn_watchdog
local units         = smem.rtu_sys.units
local sounders      = backplane.sounders()
local function loop_tick()
databus.heartbeat()
backplane.periodic()
for _, sounder in pairs(sounders) do
if sounder.stream.is_recompute_needed() then
sounder.stream.compute_buffer()
if sounder.stream.any_active() then sounder.play() else sounder.stop() end
end
end
if rtu_state.linked then
rtu_comms.manage_failover(backplane.active_nic())
else
local a_nic, s_nic = backplane.active_nic(), backplane.standby_nic()
if a_nic.is_network_up() then
rtu_comms.send_establish(a_nic, units)
elseif s_nic and s_nic.is_network_up() then
rtu_comms.send_establish(s_nic, units)
end
end
loop_clock.start()
end
rtu_comms.unlink(rtu_state)
loop_clock.start()
while true do
local event, param1, param2, param3, param4, param5 = util.pull_event()
if event == "modem_message" then
local packet = rtu_comms.parse_packet(param1, param2, param3, param4, param5)
if packet ~= nil then
smem.q.mq_comms.push_network(packet)
end
elseif event == "timer" then
if loop_clock.is_clock(param1) then
loop_tick()
elseif conn_watchdog.is_timer(param1) then
rtu_comms.close(rtu_state)
else
tcd.handle(param1)
end
elseif event == "speaker_audio_empty" then
for i = 1, #sounders do
local sounder = sounders[i]
if sounder.name == param1 then
sounder.continue()
break
end
end
elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or
event == "double_click" then
renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
elseif event == "peripheral" then
local type, device = ppm.mount(param1)
if type ~= nil and device ~= nil then
if type == "modem" or type == "speaker" then
backplane.attach(type, device, param1, println_ts)
else
for i = 1, #units do
handle_unit_mount(smem, println_ts, param1, type, device, units[i])
end
end
end
elseif event == "peripheral_detach" then
local type, device = ppm.handle_unmount(param1)
if type ~= nil and device ~= nil then
if type == "modem" or type == "speaker" then
backplane.detach(type, device, param1, println_ts)
else
for i = 1, #units do
if units[i].device == device then
local unit = units[i]
local type_name = types.rtu_type_to_string(unit.type)
println_ts(util.c("已在接口 ", unit.name, " 上丢失 ", type_name))
log.warning(util.c("已在接口 ", unit.name, " 上丢失 ", type_name, " 单元外设"))
unit.hw_state = RTU_HW_STATE.OFFLINE
databus.tx_unit_hw_status(unit.uid, unit.hw_state)
break
end
end
end
end
end
if event == "terminate" or ppm.should_terminate() then
rtu_state.shutdown = true
log.info("OS: terminate requested, main thread exiting")
break
end
end
end
function public.p_exec()
local rtu_state = smem.rtu_state
while not rtu_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("main", false)
if not rtu_state.shutdown then
log.info("OS: main thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
function threads.thread__comms(smem)
local public = {}
function public.exec()
databus.tx_rt_status("comms", true)
log.debug("OS: comms thread start")
local rtu_state   = smem.rtu_state
local rtu_comms   = smem.rtu_sys.rtu_comms
local units       = smem.rtu_sys.units
local comms_queue = smem.q.mq_comms
local sounders    = backplane.sounders()
local last_update = util.time()
while true do
local handle_start = util.time()
while comms_queue.ready() and not rtu_state.shutdown do
local msg = comms_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.NETWORK then
rtu_comms.handle_packet(msg.message, units, rtu_state, sounders)
end
end
if util.time() - handle_start > 100 then
log.warning("OS: comms thread exceeded 100ms queue process limit")
break
end
end
util.nop()
if rtu_state.shutdown then
rtu_comms.close(rtu_state)
log.info("OS: comms thread exiting")
break
end
last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
end
end
function public.p_exec()
local rtu_state = smem.rtu_state
while not rtu_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("comms", false)
if not rtu_state.shutdown then
log.info("OS: comms thread restarting in 5 seconds...")
util.psleep(5)
end
end
end
return public
end
function threads.thread__unit_comms(smem, unit)
local function println_ts(message) if not smem.rtu_state.fp_ok then util.println_ts(message) end end
local public = {}
function public.exec()
databus.tx_rt_status("unit_" .. unit.uid, true)
log.debug(util.c("OS: rtu unit thread start -> ", types.rtu_type_to_string(unit.type), " (", unit.name, ")"))
local rtu_state    = smem.rtu_state
local rtu_comms    = smem.rtu_sys.rtu_comms
local packet_queue = unit.pkt_queue
local last_update  = util.time()
local last_f_check = 0
local detail_name  = util.c(types.rtu_type_to_string(unit.type), " (", unit.name, ") ",
util.trinary(unit.index == false, "", util.c("[", unit.index, "] ")), "for ",
util.trinary(unit.reactor == 0, "the facility", util.c("reactor ", unit.reactor)))
local short_name   = util.c(types.rtu_type_to_string(unit.type), " (", unit.name, ")")
if packet_queue == nil then
log.error("OS: rtu unit thread created without a message queue, exiting...", true)
return
end
while true do
while packet_queue.ready() and not rtu_state.shutdown do
local msg = packet_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.NETWORK then
local _, reply = unit.modbus_io.handle_adu(msg.message)
rtu_comms.send_modbus(reply)
end
end
util.nop()
end
if rtu_state.shutdown then
log.info("OS: rtu unit thread exiting -> " .. short_name)
break
end
if unit.is_multiblock and (util.time_ms() - last_f_check > 250) then
last_f_check = util.time_ms()
local is_formed = unit.device.isFormed()
if unit.formed == nil then
unit.formed = is_formed
if is_formed then unit.hw_state = RTU_HW_STATE.OK end
elseif not unit.formed then
unit.hw_state = RTU_HW_STATE.UNFORMED
end
if (is_formed == true) and not unit.formed then
unit.hw_state = RTU_HW_STATE.OK
log.info(util.c(detail_name, " 现已成型"))
rtu_comms.send_remounted(unit.uid)
elseif (is_formed == false) and unit.formed then
log.warning(util.c(detail_name, " 不再成型"))
elseif (is_formed == nil) and (unit.hw_state ~= RTU_HW_STATE.OFFLINE) then
log.error(util.c(detail_name, " 无法检查是否成型，尝试重新挂载..."))
local type, dev = ppm.remount(unit.name)
if type and dev then
handle_unit_mount(smem, println_ts, unit.name, type, dev, unit)
else
log.error(util.c(detail_name, " 重新挂载失败"))
end
end
unit.formed = is_formed
end
if unit.device.__p_is_healthy() then
if unit.hw_state == RTU_HW_STATE.FAULTED then unit.hw_state = RTU_HW_STATE.OK end
else
if unit.hw_state == RTU_HW_STATE.OK then unit.hw_state = RTU_HW_STATE.FAULTED end
end
databus.tx_unit_hw_status(unit.uid, unit.hw_state)
last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
end
end
function public.p_exec()
local rtu_state = smem.rtu_state
while not rtu_state.shutdown do
local status, result = pcall(public.exec)
if status == false then
log.fatal(util.strval(result))
end
databus.tx_rt_status("unit_" .. unit.uid, false)
if not rtu_state.shutdown then
log.info(util.c("OS: rtu unit thread ", types.rtu_type_to_string(unit.type), " (", unit.name, ") restarting in 5 seconds..."))
util.psleep(5)
end
end
end
return public
end
return threads
