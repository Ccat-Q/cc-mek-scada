local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local ppm          = require("scada-common.ppm")
local rsio         = require("scada-common.rsio")
local types        = require("scada-common.types")
local util         = require("scada-common.util")
local databus      = require("rtu.databus")
local modbus       = require("rtu.modbus")
local rtu          = require("rtu.rtu")
local threads      = require("rtu.threads")
local boilerv_rtu  = require("rtu.dev.boilerv_rtu")
local dynamicv_rtu = require("rtu.dev.dynamicv_rtu")
local ecore_rtu    = require("rtu.dev.ecore_rtu")
local envd_rtu     = require("rtu.dev.envd_rtu")
local imatrix_rtu  = require("rtu.dev.imatrix_rtu")
local redstone_rtu = require("rtu.dev.redstone_rtu")
local sna_rtu      = require("rtu.dev.sna_rtu")
local sps_rtu      = require("rtu.dev.sps_rtu")
local turbinev_rtu = require("rtu.dev.turbinev_rtu")
local println = util.println
local println_ts = util.println_ts
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local RTU_HW_STATE = databus.RTU_HW_STATE
local function log_fail(msg)
println(msg)
log.fatal(msg)
end
local function entry_iface_name(entry)
return util.trinary(entry.color ~= nil, util.c(entry.side, "/", rsio.color_name(entry.color)), entry.side)
end
return function(config, __shared_memory)
local units = __shared_memory.rtu_sys.units
local rtu_redstone = config.Redstone
local rtu_devices = config.Peripherals
local rs_rtus   = {}
local all_conns = { [0] = {}, {}, {}, {}, {} }
for entry_idx = 1, #rtu_redstone do
local entry = rtu_redstone[entry_idx]
local assignment
local for_reactor = entry.unit
local phy         = entry.relay or 0
local phy_name    = entry.relay or "local"
local iface_name  = entry_iface_name(entry)
if util.is_int(entry.unit) and entry.unit > 0 and entry.unit < 5 then
assignment = "反应堆机组 " .. entry.unit
elseif entry.unit == nil then
assignment = "设施"
for_reactor = 0
else
log_fail(util.c("uinit> 块索引 #", entry_idx, " 处的机组分配无效"))
return false
end
if entry.relay then
if type(entry.relay) ~= "string" then
log_fail(util.c("uinit> 红石继电器 '", entry.relay, '" 无效'))
return false
elseif not rs_rtus[entry.relay] then
log.debug(util.c("uinit> 已在接口 ", entry.relay, " 上分配继电器红石 RTU"))
local hw_state = RTU_HW_STATE.OK
local relay    = ppm.get_periph(entry.relay)
if not relay then
hw_state = RTU_HW_STATE.OFFLINE
log.warning(util.c("uinit> 红石继电器 ", entry.relay, " 未连接"))
local _, v_device = ppm.mount_virtual()
relay = v_device
elseif ppm.get_type(entry.relay) ~= "redstone_relay" then
hw_state = RTU_HW_STATE.FAULTED
log.warning(util.c("uinit> 红石继电器 ", entry.relay, " 不是红石继电器"))
end
rs_rtus[entry.relay] = { name = entry.relay, hw_state = hw_state, rtu = redstone_rtu.new(relay), phy = relay, banks = { [0] = {}, {}, {}, {}, {} } }
end
elseif rs_rtus[0] == nil then
log.debug(util.c("uinit> 已分配本机红石 RTU"))
rs_rtus[0] = { name = "redstone_local", hw_state = RTU_HW_STATE.OK, rtu = redstone_rtu.new(), phy = rs, banks = { [0] = {}, {}, {}, {}, {} } }
end
local valid = false
if rsio.is_valid_port(entry.port) and rsio.is_valid_side(entry.side) then
valid = util.trinary(entry.color == nil, true, rsio.is_color(entry.color))
end
local bank  = rs_rtus[phy].banks[for_reactor]
local conns = all_conns[for_reactor]
if not valid then
log_fail(util.c("uinit> 块索引 #", entry_idx, " 处的红石定义无效"))
return false
else
local mode = rsio.get_io_mode(entry.port)
if mode == rsio.IO_MODE.DIGITAL_IN then
if util.table_contains(conns, entry.port) then
local message = util.c("uinit> 跳过端口 ", rsio.to_string(entry.port), " 在侧 ", iface_name, " @ ", phy_name, " 上的重复输入")
println(message)
log.warning(message)
else
table.insert(bank, entry)
end
elseif mode == rsio.IO_MODE.ANALOG_IN then
if util.table_contains(conns, entry.port) then
local message = util.c("uinit> 跳过端口 ", rsio.to_string(entry.port), " 在侧 ", iface_name, " @ ", phy_name, " 上的重复输入")
println(message)
log.warning(message)
else
table.insert(bank, entry)
end
elseif (mode == rsio.IO_MODE.DIGITAL_OUT) or (mode == rsio.IO_MODE.ANALOG_OUT) then
table.insert(bank, entry)
else
log.fatal("uinit> 无法识别块索引 #" .. entry_idx .. " 处的 IO 模式")
println("uinit> 遇到软件错误，请检查日志")
return false
end
table.insert(conns, entry.port)
log.debug(util.c("uinit> 已分组红石 ", #conns, ": ", rsio.to_string(entry.port), " (", iface_name, " @ ", phy_name, ") 用于 ", assignment))
end
end
for _, def in pairs(rs_rtus) do
local rtu_conns = { [0] = {}, {}, {}, {}, {} }
for for_reactor = 0, #def.banks do
local bank   = def.banks[for_reactor]
local conns  = rtu_conns[for_reactor]
local assign = util.trinary(for_reactor > 0, "反应堆机组 " .. for_reactor, "设施")
for i = 1, #bank do
local conn     = bank[i]
local phy_name = conn.relay or "local"
local mode = rsio.get_io_mode(conn.port)
if mode == rsio.IO_MODE.DIGITAL_IN then
def.rtu.link_di(conn.side, conn.color, conn.invert)
elseif mode == rsio.IO_MODE.DIGITAL_OUT then
def.rtu.link_do(conn.side, conn.color, conn.invert)
elseif mode == rsio.IO_MODE.ANALOG_IN then
def.rtu.link_ai(conn.side)
elseif mode == rsio.IO_MODE.ANALOG_OUT then
def.rtu.link_ao(conn.side)
else
log.fatal(util.c("uinit> 无法识别 ", rsio.to_string(conn.port), " (", entry_iface_name(conn), " @ ", phy_name, ") 用于 ", assign, " 的 IO 模式"))
println("uinit> 遇到软件错误，请检查日志")
return false
end
table.insert(conns, conn.port)
log.debug(util.c("uinit> 已连接红石 ", for_reactor, ".", #conns, ": ", rsio.to_string(conn.port), " (", entry_iface_name(conn), ")", " @ ", phy_name, ") 用于 ", assign))
end
end
local unit = {
uid = 0,
name = def.name,
type = RTU_UNIT_TYPE.REDSTONE,
index = false,
reactor = nil,
device = def.phy,
rs_conns = rtu_conns,
is_multiblock = false,
formed = nil,
hw_state = def.hw_state,
rtu = def.rtu,
modbus_io = modbus.new(def.rtu, false),
pkt_queue = nil,
thread = nil
}
table.insert(units, unit)
local type = util.trinary(def.phy == rs, "redstone", "redstone_relay")
log.info(util.c("uinit> 已初始化 RTU 单元 #", #units, ": ", unit.name, " (", type, ")"))
unit.uid = #units
databus.tx_unit_hw_status(unit.uid, unit.hw_state)
end
for i = 1, #rtu_devices do
local entry = rtu_devices[i]
local name = entry.name
local index = entry.index
local for_reactor = util.trinary(entry.unit == nil, 0, entry.unit)
if type(name) ~= "string" then
log_fail(util.c("uinit> 设备条目 #", i, ": 设备 ", name, " 不是字符串"))
return false
end
if (index ~= nil) and (not util.is_int(index)) then
log_fail(util.c("uinit> 设备条目 #", i, ": 索引 ", index, " 无效"))
return false
end
local function validate_index(min, max)
if (not util.is_int(index)) or ((index < min) and (max ~= nil and index > max)) then
local message = util.c("uinit> 设备条目 #", i, ": 索引 ", index, " 不满足 >= ", min)
if max ~= nil then message = util.c(message, " 且 <= ", max) end
log_fail(message)
return false
else return true end
end
local function validate_assign(for_facility)
if for_facility and for_reactor ~= 0 then
log_fail(util.c("uinit> 设备条目 #", i, ": 只能用于设施"))
return false
elseif (not for_facility) and ((not util.is_int(for_reactor)) or (for_reactor < 1) or (for_reactor > 4)) then
log_fail(util.c("uinit> 设备条目 #", i, ": 机组分配 ", for_reactor, " 无效"))
return false
else return true end
end
local device = ppm.get_periph(name)
local type
local rtu_iface
local rtu_type
local is_multiblock = false
local formed = nil
local faulted = nil
if device == nil then
local message = util.c("uinit> 未找到 '", name, "'，使用占位符")
println(message)
log.warning(message)
type, device = ppm.mount_virtual()
else
type = ppm.get_type(name)
end
if type == "boilerValve" then
if not validate_index(1, 2) then return false end
if not validate_assign() then return false end
rtu_type = RTU_UNIT_TYPE.BOILER_VALVE
rtu_iface, faulted = boilerv_rtu.new(device)
is_multiblock = true
formed = device.isFormed()
if formed == ppm.ACCESS_FAULT then
println_ts(util.c("uinit> 无法检查 '", name, "' 是否成型"))
log.warning(util.c("uinit> 无法检查 '", name, "' 是否为成型的锅炉多方块结构"))
end
elseif type == "turbineValve" then
if not validate_index(1, 3) then return false end
if not validate_assign() then return false end
rtu_type = RTU_UNIT_TYPE.TURBINE_VALVE
rtu_iface, faulted = turbinev_rtu.new(device)
is_multiblock = true
formed = device.isFormed()
if formed == ppm.ACCESS_FAULT then
println_ts(util.c("uinit> 无法检查 '", name, "' 是否成型"))
log.warning(util.c("uinit> 无法检查 '", name, "' 是否为成型的涡轮机多方块结构"))
end
elseif type == "dynamicValve" then
if entry.unit == nil then
if not validate_index(1, 4) then return false end
if not validate_assign(true) then return false end
else
if not validate_index(1, 1) then return false end
if not validate_assign() then return false end
end
rtu_type = RTU_UNIT_TYPE.DYNAMIC_VALVE
rtu_iface, faulted = dynamicv_rtu.new(device)
is_multiblock = true
formed = device.isFormed()
if formed == ppm.ACCESS_FAULT then
println_ts(util.c("uinit> 无法检查 '", name, "' 是否成型"))
log.warning(util.c("uinit> 无法检查 '", name, "' 是否为成型的动态储罐多方块结构"))
end
elseif type == "inductionPort" or type == "reinforcedInductionPort" then
if not validate_assign(true) then return false end
rtu_type = RTU_UNIT_TYPE.IMATRIX
rtu_iface, faulted = imatrix_rtu.new(device)
is_multiblock = true
formed = device.isFormed()
if formed == ppm.ACCESS_FAULT then
println_ts(util.c("uinit> 无法检查 '", name, "' 是否成型"))
log.warning(util.c("uinit> 无法检查 '", name, "' 是否为成型的感应矩阵多方块结构"))
end
elseif type == "spsPort" then
if not validate_assign(true) then return false end
rtu_type = RTU_UNIT_TYPE.SPS
rtu_iface, faulted = sps_rtu.new(device)
is_multiblock = true
formed = device.isFormed()
if formed == ppm.ACCESS_FAULT then
println_ts(util.c("uinit> 无法检查 '", name, "' 是否成型"))
log.warning(util.c("uinit> 无法检查 '", name, "' 是否为成型的 SPS 多方块结构"))
end
elseif type == "solarNeutronActivator" or type == "largeSolarNeutronActivator" then
if not validate_assign(entry.unit == nil) then return false end
rtu_type = RTU_UNIT_TYPE.SNA
rtu_iface, faulted = sna_rtu.new(device)
elseif type == "environmentDetector" or type == "environment_detector" then
if not validate_index(1) then return false end
if not validate_assign(entry.unit == nil) then return false end
rtu_type = RTU_UNIT_TYPE.ENV_DETECTOR
rtu_iface, faulted = envd_rtu.new(device)
elseif type == "draconic_rf_storage" then
if not validate_assign(true) then return false end
rtu_type = RTU_UNIT_TYPE.ENERGY_CORE
rtu_iface, faulted = ecore_rtu.new(device)
elseif type == ppm.VIRTUAL_DEVICE_TYPE then
rtu_type = RTU_UNIT_TYPE.VIRTUAL
rtu_iface = rtu.init_unit().interface()
else
log_fail(util.c("uinit> 设备 '", name, "' 不是已知类型 (", type, ")"))
return false
end
if is_multiblock then
if not formed then
if formed == false then
log.info(util.c("uinit> 设备 '", name, "' 未成型"))
else formed = false end
elseif faulted then
formed = false
log.warning(util.c("uinit> 设备 '", name, "' 已成型，但初始化时出现一个或多个故障：标记为未成型"))
end
end
local rtu_unit = {
uid = 0,
name = name,
type = rtu_type,
index = index or false,
reactor = for_reactor,
device = device,
rs_conns = nil,
is_multiblock = is_multiblock,
formed = formed,
hw_state = RTU_HW_STATE.OFFLINE,
rtu = rtu_iface,
modbus_io = modbus.new(rtu_iface, true),
pkt_queue = mqueue.new(),
thread = nil
}
rtu_unit.thread = threads.thread__unit_comms(__shared_memory, rtu_unit)
table.insert(units, rtu_unit)
local for_message = "设施"
if for_reactor > 0 then
for_message = util.c("反应堆 ", for_reactor)
end
local index_str = util.trinary(index ~= nil, util.c(" [", index, "]"), "")
log.info(util.c("uinit> 已初始化 RTU 单元 #", #units, ": ", name, " (", types.rtu_type_to_string(rtu_type), ")", index_str, " 用于 ", for_message))
rtu_unit.uid = #units
if rtu_unit.type == RTU_UNIT_TYPE.VIRTUAL then
rtu_unit.hw_state = RTU_HW_STATE.OFFLINE
else
if rtu_unit.is_multiblock then
rtu_unit.hw_state = util.trinary(rtu_unit.formed == true, RTU_HW_STATE.OK, RTU_HW_STATE.UNFORMED)
elseif faulted then
rtu_unit.hw_state = RTU_HW_STATE.FAULTED
else
rtu_unit.hw_state = RTU_HW_STATE.OK
end
end
databus.tx_unit_hw_status(rtu_unit.uid, rtu_unit.hw_state)
end
return true
end
