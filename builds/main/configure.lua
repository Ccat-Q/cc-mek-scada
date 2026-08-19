print("CONFIGURE> 正在扫描配置器...")
for _, app in ipairs({ "reactor-plc", "rtu", "supervisor", "coordinator", "pocket", "sim" }) do
if fs.exists(app .. "/configure.lua") then
local _, _, launch = require(app .. ".configure").configure()
if launch then shell.execute("/startup") end
return
end
end
print("CONFIGURE> 未找到配置器")
print("CONFIGURE> 退出")
