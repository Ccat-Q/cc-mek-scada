local BOOTLOADER_VERSION = "1.3"
print("SCADA BOOTLOADER V" .. BOOTLOADER_VERSION)
print("BOOT> 正在扫描应用程序...")
local exit_code
if fs.exists("reactor-plc/startup.lua") then
print("BOOT> 执行反应堆 PLC 启动")
exit_code = shell.execute("reactor-plc/startup")
elseif fs.exists("rtu/startup.lua") then
print("BOOT> 执行 RTU 启动")
exit_code = shell.execute("rtu/startup")
elseif fs.exists("supervisor/startup.lua") then
print("BOOT> 执行监控端启动")
exit_code = shell.execute("supervisor/startup")
elseif fs.exists("coordinator/startup.lua") then
print("BOOT> 执行协调器启动")
exit_code = shell.execute("coordinator/startup")
elseif fs.exists("pocket/startup.lua") then
print("BOOT> 执行 Pocket 启动")
exit_code = shell.execute("pocket/startup")
elseif fs.exists("sim/startup.lua") then
print("BOOT> 执行模拟器启动")
exit_code = shell.execute("sim/startup")
else
print("BOOT> 未找到 SCADA 启动程序")
print("BOOT> 退出")
return false
end
if not exit_code then print("BOOT> 应用程序崩溃") end
return exit_code
