
local log  = require("scada-common.log")
local util = require("scada-common.util")
local ppm = {}
local ACCESS_FAULT        = nil
local UNDEFINED_FIELD     = "__PPM_UNDEF_FIELD__"
local VIRTUAL_DEVICE_TYPE = "ppm_vdev"
ppm.ACCESS_FAULT          = ACCESS_FAULT
ppm.UNDEFINED_FIELD       = UNDEFINED_FIELD
ppm.VIRTUAL_DEVICE_TYPE   = VIRTUAL_DEVICE_TYPE
local REPORT_FREQUENCY = 20
local _ppm = {
mounts = {},
next_vid = 0,
auto_cf = false,
faulted = false,
last_fault = "",
terminate = false,
mute = false
}
local function peri_init(iface)
local self = {
faulted = false,
last_fault = "",
fault_counts = {},
auto_cf = true,
type = VIRTUAL_DEVICE_TYPE,
device = {}
}
if iface ~= "__virtual__" then
self.type = peripheral.getType(iface)
self.device = peripheral.wrap(iface)
end
local function protect_peri_function(key, func)
return function (...)
local return_table = table.pack(pcall(func, ...))
local status = return_table[1]
table.remove(return_table, 1)
if status then
if self.auto_cf then self.faulted = false end
if _ppm.auto_cf then _ppm.faulted = false end
self.fault_counts[key] = 0
return table.unpack(return_table)
else
local result = return_table[1]
self.faulted = true
self.last_fault = result
_ppm.faulted = true
_ppm.last_fault = result
if not _ppm.mute and (self.fault_counts[key] % REPORT_FREQUENCY == 0) then
local count_str = ""
if self.fault_counts[key] > 0 then
count_str = " [累计 " .. self.fault_counts[key] .. " 次故障]"
end
log.error(util.c("PPM: [@", iface, "] 调用 ", key, "() 失败 -> ", result, count_str))
end
self.fault_counts[key] = self.fault_counts[key] + 1
if result == "Terminated" then _ppm.terminate = true end
return ACCESS_FAULT, result
end
end
end
local function clear_fault() self.faulted = false end
local function get_last_fault() return self.last_fault end
local function is_faulted() return self.faulted end
local function is_ok() return not self.faulted end
local function is_healthy()
for _, v in pairs(self.fault_counts) do if v > 0 then return false end end
return true
end
local function enable_afc() self.auto_cf = true end
local function disable_afc() self.auto_cf = false end
self.device.__p_clear_fault = clear_fault
self.device.__p_last_fault  = get_last_fault
self.device.__p_is_faulted  = is_faulted
self.device.__p_is_ok       = is_ok
self.device.__p_is_healthy  = is_healthy
self.device.__p_enable_afc  = enable_afc
self.device.__p_disable_afc = disable_afc
local dev = self.device
dev.__p_clear_fault = clear_fault
dev.__p_last_fault  = get_last_fault
dev.__p_is_faulted  = is_faulted
dev.__p_is_ok       = is_ok
dev.__p_is_healthy  = is_healthy
dev.__p_enable_afc  = enable_afc
dev.__p_disable_afc = disable_afc
for key, func in pairs(self.device) do
self.fault_counts[key] = 0
self.device[key] = protect_peri_function(key, func)
end
local mt = {
__index = function (_, key)
local funcs = peripheral.wrap(iface)
if (type(funcs) == "table") and (type(funcs[key]) == "function") then
self.fault_counts[key] = 0
self.device[key] = protect_peri_function(key, funcs[key])
log.info(util.c("PPM: [@", iface, "] 初始化了此前未定义的字段 ", key, "()"))
return self.device[key]
end
return (function ()
if self.fault_counts[key] == nil then self.fault_counts[key] = 0 end
self.faulted = true
self.last_fault = UNDEFINED_FIELD
_ppm.faulted = true
_ppm.last_fault = UNDEFINED_FIELD
if not _ppm.mute and (self.fault_counts[key] % REPORT_FREQUENCY == 0) then
local count_str = ""
if self.fault_counts[key] > 0 then
count_str = " [累计 " .. self.fault_counts[key] .. " 次调用]"
end
log.error(util.c("PPM: [@", iface, "] 捕获到未定义的函数 ", key, "()", count_str))
end
self.fault_counts[key] = self.fault_counts[key] + 1
return ACCESS_FAULT, UNDEFINED_FIELD
end)
end
}
setmetatable(self.device, mt)
local entry = { type = self.type, dev = self.device }
return entry
end
function ppm.disable_reporting() _ppm.mute = true end
function ppm.enable_reporting() _ppm.mute = false end
function ppm.enable_afc() _ppm.auto_cf = true end
function ppm.disable_afc() _ppm.auto_cf = false end
function ppm.clear_fault() _ppm.faulted = false end
function ppm.is_faulted() return _ppm.faulted end
function ppm.get_last_fault() return _ppm.last_fault end
function ppm.should_terminate() return _ppm.terminate end
function ppm.mount_all()
local ifaces = peripheral.getNames()
_ppm.mounts = {}
for i = 1, #ifaces do
_ppm.mounts[ifaces[i]] = peri_init(ifaces[i])
log.info(util.c("PPM: 发现一个 ", _ppm.mounts[ifaces[i]].type, " (", ifaces[i], ")"))
end
if #ifaces == 0 then
log.warning("PPM: mount_all() -> 未发现任何设备")
end
end
function ppm.mount(iface)
local ifaces = peripheral.getNames()
local pm_dev = nil
local pm_type = nil
for i = 1, #ifaces do
if iface == ifaces[i] then
_ppm.mounts[iface] = peri_init(iface)
pm_type = _ppm.mounts[iface].type
pm_dev = _ppm.mounts[iface].dev
log.info(util.c("PPM: mount(", iface, ") -> 发现一个 ", pm_type))
break
end
end
return pm_type, pm_dev
end
function ppm.remount(iface)
local ifaces = peripheral.getNames()
local pm_dev = nil
local pm_type = nil
for i = 1, #ifaces do
if iface == ifaces[i] then
log.info(util.c("PPM: remount(", iface, ") -> 是一个 ", pm_type))
ppm.unmount(_ppm.mounts[iface].dev)
_ppm.mounts[iface] = peri_init(iface)
pm_type = _ppm.mounts[iface].type
pm_dev = _ppm.mounts[iface].dev
log.info(util.c("PPM: remount(", iface, ") -> 已重新挂载 ", pm_type))
break
end
end
return pm_type, pm_dev
end
function ppm.mount_virtual()
local iface = "ppm_vdev_" .. _ppm.next_vid
_ppm.mounts[iface] = peri_init("__virtual__")
_ppm.next_vid = _ppm.next_vid + 1
log.info(util.c("PPM: mount_virtual() -> 已分配新的虚拟设备 ", iface))
return _ppm.mounts[iface].type, _ppm.mounts[iface].dev
end
function ppm.unmount(device)
if device then
for iface, data in pairs(_ppm.mounts) do
if data.dev == device then
log.warning(util.c("PPM: 手动卸载了 ", data.type, "（挂载于 ", iface, "）"))
_ppm.mounts[iface] = nil
break
end
end
end
end
function ppm.handle_unmount(iface)
local pm_dev = nil
local pm_type = nil
local lost_dev = _ppm.mounts[iface]
if lost_dev then
pm_type = lost_dev.type
pm_dev = lost_dev.dev
log.warning(util.c("PPM: 丢失设备 ", pm_type, "（挂载于 ", iface, "）"))
else
log.error(util.c("PPM: 丢失了 PPM 未知的设备，挂载于 ", iface))
end
_ppm.mounts[iface] = nil
return pm_type, pm_dev
end
function ppm.log_mounts()
for iface, mount in pairs(_ppm.mounts) do
log.info(util.c("PPM: 曾发现一个 ", mount.type, " (", iface, ")"))
end
if util.table_len(_ppm.mounts) == 0 then
log.warning("PPM: 未发现任何设备")
end
end
function ppm.list_avail() return peripheral.getNames() end
function ppm.list_mounts()
local list = {}
for k, v in pairs(_ppm.mounts) do list[k] = v end
return list
end
function ppm.get_iface(device)
if device then
for iface, data in pairs(_ppm.mounts) do
if data.dev == device then return iface end
end
end
return nil
end
function ppm.get_periph(iface)
if _ppm.mounts[iface] then
return _ppm.mounts[iface].dev
else return nil end
end
function ppm.get_type(iface)
if _ppm.mounts[iface] then
return _ppm.mounts[iface].type
else return nil end
end
function ppm.get_all_devices(type)
local devices = {}
for _, data in pairs(_ppm.mounts) do
if data.type == type then
table.insert(devices, data.dev)
end
end
return devices
end
function ppm.get_device(type)
local device, d_iface = nil, nil
for iface, data in pairs(_ppm.mounts) do
if data.type == type then
device = data.dev
d_iface = iface
break
end
end
return device, d_iface
end
function ppm.get_fission_reactor()
local dev, iface = ppm.get_device("fissionReactorLogicAdapter")
return dev, iface
end
function ppm.get_modem(iface)
local modem  = nil
local device = _ppm.mounts[iface]
if device and device.type == "modem" then modem = device.dev end
return modem
end
function ppm.get_wireless_modem()
local w_modem, w_iface = nil, nil
local emulated_env = periphemu ~= nil
for iface, device in pairs(_ppm.mounts) do
if device.type == "modem" and (emulated_env or device.dev.isWireless()) then
w_modem = device.dev
w_iface = iface
break
end
end
return w_modem, w_iface
end
function ppm.get_wired_modem_list()
local list = {}
for iface, device in pairs(_ppm.mounts) do
if device.type == "modem" and not device.dev.isWireless() then list[iface] = device end
end
return list
end
function ppm.get_monitor_list()
local list = {}
for iface, device in pairs(_ppm.mounts) do
if device.type == "monitor" then list[iface] = device end
end
return list
end
function ppm.monitor_block_size(width, height)
return math.floor((width - 15) / 21) + 1, math.floor((height - 10) / 14) + 1
end
return ppm
