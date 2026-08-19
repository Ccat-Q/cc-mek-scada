
local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
local tcd         = require("scada-common.tcd")
local types       = require("scada-common.types")
local util        = require("scada-common.util")
local facility    = require("supervisor.config.facility")
local mekanism    = require("supervisor.config.mekanism")
local system      = require("supervisor.config.system")
local core        = require("graphics.core")
local themes      = require("graphics.themes")
local DisplayBox  = require("graphics.elements.DisplayBox")
local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")
local PushButton  = require("graphics.elements.controls.PushButton")
local println = util.println
local tri = util.trinary
local cpair = core.cpair
local CENTER = core.ALIGN.CENTER
local changes = {
{ "v1.2.12", { "新增前面板 UI 主题", "新增颜色无障碍模式" } },
{ "v1.3.2", { "新增黑色关闭状态标准颜色模式", "新增蓝色指示灯颜色模式" } },
{ "v1.6.0", { "新增钠紧急冷却选项" } },
{ "v1.8.0", { "新增有线通信调制解调器支持", "新增允许 Pocket 连接选项", "新增允许 Pocket 测试命令选项" } },
{ "v1.9.5", { "新增 Mekanism Generators 配置选项" } },
{ "v1.9.9", { "新增废料比例配置选项" } },
{ "v1.10.4", { "新增使用 SNA 统计钋数据选项（默认）" } },
{ "v1.11.0", { "新增合并设施废料选项" } },
{ "v1.12.0", { "新增储能系统选项" } }
}
local configurator = {}
local style = {}
style.root          = cpair(colors.black, colors.lightGray)
style.header        = cpair(colors.white, colors.gray)
style.colors        = themes.smooth_stone.colors
style.bw_fg_bg      = cpair(colors.black, colors.white)
style.g_lg_fg_bg    = cpair(colors.gray, colors.lightGray)
style.nav_fg_bg     = style.bw_fg_bg
style.btn_act_fg_bg = cpair(colors.white, colors.gray)
style.btn_dis_fg_bg = cpair(colors.lightGray, colors.white)
local tool_ctl = {
launch_startup = false,
ask_config = false,
has_config = false,
viewing_config = false,
jumped_to_color = false,
view_cfg = nil,
color_cfg = nil,
color_next = nil,
color_apply = nil,
settings_apply = nil,
num_units = nil,
en_fac_tanks = nil,
tank_mode = nil,
tank_fluid_opts = {},
gen_summary = nil,
load_legacy = nil,
cooling_elems = {},
tank_elems = {},
aux_cool_elems = {},
ext_idling = nil,
sna_stats = nil,
com_waste = nil,
ess_opt = nil,
mek_profile = nil,
custom_configs = {},
waste_ratios = {},
gen_modem_list = function () end,
dw_free_space = nil,
dw_log_size = nil,
dw_del_log_btn = nil,
dw_continue = nil
}
local tmp_cfg = {
UnitCount = 1,
CoolingConfig = {},
FacilityTankMode = 0,
FacilityTankDefs = {},  ---@type integer[] each unit's tank connection target (0 = disconnected, 1 = unit, 2 = facility)
FacilityTankList = {},
FacilityTankConns = {},
TankFluidTypes = {},
AuxiliaryCoolant = {},
ExtChargeIdling = false,
UseSNAStatistics = true,
CombinedWaste = false,
EnergyStorageSystem = 1,
MekanismProfile = mekanism.profiles[1].name,
MekanismConfig = mekanism.profiles[1].fields,
MekanismWasteToPu = { 10, 1 },
MekanismWasteToPo = { 10, 1 },
WirelessModem = true,
WiredModem = false,
PLC_Listen = 1,
RTU_Listen = 1,
CRD_Listen = 1,
PocketEnabled = true,
PocketTest = true,
SVR_Channel = nil,
PLC_Channel = nil,
RTU_Channel = nil,
CRD_Channel = nil,
PKT_Channel = nil,
PLC_Timeout = nil,
RTU_Timeout = nil,
CRD_Timeout = nil,
PKT_Timeout = nil,
TrustedRange = nil,
AuthKey = nil,
LogMode = 0,
LogPath = "",
LogDebug = false,
FrontPanelTheme = 1,
ColorMode = 1
}
local ini_cfg = {}
local settings_cfg = {}
local fields = {
{ "UnitCount", "反应堆数量", 1 },
{ "CoolingConfig", "冷却配置", {} },
{ "FacilityTankMode", "设施储罐模式", 0 },
{ "FacilityTankDefs", "设施储罐定义", {} },
{ "FacilityTankList", "设施储罐列表", {} },
{ "FacilityTankConns", "设施储罐连接", {} },
{ "TankFluidTypes", "储罐流体类型", {} },
{ "AuxiliaryCoolant", "辅助水冷却", {} },
{ "ExtChargeIdling", "延长充能待机", false },
{ "UseSNAStatistics", "使用 SNA 统计", true },
{ "CombinedWaste", "合并设施废料", false },
{ "EnergyStorageSystem", "储能系统", types.ESS.INDUCTION_MATRIX },
{ "MekanismProfile", "Mekanism 配置档案", mekanism.profiles[1].name },
{ "MekanismConfig", "Mekanism 配置", mekanism.profiles[1].fields },
{ "MekanismWasteToPu", "核废料转钚", { 10, 1 } },
{ "MekanismWasteToPo", "核废料转钋", { 10, 1 } },
{ "WirelessModem", "无线/末地通信调制解调器", true },
{ "WiredModem", "有线通信调制解调器", false },
{ "PLC_Listen", "PLC 监听模式", types.LISTEN_MODE.WIRELESS },
{ "RTU_Listen", "RTU 网关监听模式", types.LISTEN_MODE.WIRELESS },
{ "CRD_Listen", "协调器监听模式", types.LISTEN_MODE.WIRELESS },
{ "PocketEnabled", "Pocket 连接", true },
{ "PocketTest", "Pocket 测试功能", true },
{ "SVR_Channel", "SVR 频道", 16240 },
{ "PLC_Channel", "PLC 频道", 16241 },
{ "RTU_Channel", "RTU 频道", 16242 },
{ "CRD_Channel", "CRD 频道", 16243 },
{ "PKT_Channel", "PKT 频道", 16244 },
{ "PLC_Timeout", "PLC 连接超时", 5 },
{ "RTU_Timeout", "RTU 连接超时", 5 },
{ "CRD_Timeout", "CRD 连接超时", 5 },
{ "PKT_Timeout", "PKT 连接超时", 5 },
{ "TrustedRange", "信任范围", 0 },
{ "AuthKey", "设施认证密钥" , "" },
{ "LogMode", "日志模式", log.MODE.APPEND },
{ "LogPath", "日志路径", "/log.txt" },
{ "LogDebug", "启用日志调试消息", false },
{ "FrontPanelTheme", "前面板主题", themes.FP_THEME.SANDSTONE },
{ "ColorMode", "颜色模式", themes.COLOR_MODE.STANDARD }
}
local function load_settings(target, raw)
for _, v in pairs(fields) do settings.unset(v[1]) end
local loaded = settings.load("/supervisor.settings")
for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end
return loaded
end
local function config_view(display)
local bw_fg_bg      = style.bw_fg_bg
local g_lg_fg_bg    = style.g_lg_fg_bg
local nav_fg_bg     = style.nav_fg_bg
local btn_act_fg_bg = style.btn_act_fg_bg
local btn_dis_fg_bg = style.btn_dis_fg_bg
local function exit() os.queueEvent("terminate") end
TextBox{parent=display,y=1,text="监控端配置程序",alignment=CENTER,fg_bg=style.header}
local root_pane_div = Div{parent=display,y=2}
local main_page = Div{parent=root_pane_div,y=1}
local fac_cfg = Div{parent=root_pane_div,y=1}
local mek_cfg = Div{parent=root_pane_div,y=1}
local net_cfg = Div{parent=root_pane_div,y=1}
local log_cfg = Div{parent=root_pane_div,y=1}
local clr_cfg = Div{parent=root_pane_div,y=1}
local summary = Div{parent=root_pane_div,y=1}
local changelog = Div{parent=root_pane_div,y=1}
local import_err = Div{parent=root_pane_div,y=1}
local disk_warn = Div{parent=root_pane_div,y=1}
local main_pane = MultiPane{parent=root_pane_div,y=1,panes={main_page,fac_cfg,mek_cfg,net_cfg,log_cfg,clr_cfg,summary,changelog,import_err,disk_warn}}
local req_space = log.MIN_SPACE
if fs.exists("/supervisor.settings") then
req_space = math.max(0, req_space - fs.getSize("/supervisor.settings"))
end
if fs.getFreeSpace("/") < req_space then main_pane.set_value(10) end
local y_start = 5
TextBox{parent=main_page,x=2,y=2,height=2,text="欢迎使用监控端配置程序！请选择以下选项之一。"}
if tool_ctl.ask_config then
TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="注意：此设备尚未针对此版本的监控端进行配置。若您之前有有效配置，它并未丢失。您可查看更新日志了解变更内容。",fg_bg=cpair(colors.red,colors.lightGray)}
y_start = y_start + 5
end
local function view_config()
tool_ctl.viewing_config = true
tool_ctl.gen_summary(settings_cfg)
tool_ctl.settings_apply.hide(true)
main_pane.set_value(7)
end
if fs.exists("/supervisor/config.lua") then
PushButton{parent=main_page,x=2,y=y_start,min_width=28,text="导入旧版 'config.lua'",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
y_start = y_start + 2
end
PushButton{parent=main_page,x=2,y=y_start,min_width=18,text="配置系统",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
tool_ctl.view_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=20,text="查看配置",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
local function jump_color()
tool_ctl.jumped_to_color = true
tool_ctl.color_next.hide(true)
tool_ctl.color_apply.show()
main_pane.set_value(6)
end
local function startup()
tool_ctl.launch_startup = true
exit()
end
tool_ctl.color_cfg = PushButton{parent=main_page,x=36,y=y_start,min_width=15,text="颜色选项",callback=jump_color,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
PushButton{parent=main_page,x=39,y=y_start+2,min_width=12,text="更新日志",callback=function()main_pane.set_value(8)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
if tool_ctl.ask_config then
PushButton{parent=main_page,x=2,y=17,min_width=6,text="退出",callback=exit,dis_fg_bg=btn_dis_fg_bg}.disable()
PushButton{parent=main_page,x=35,y=17,min_width=16,text="恢复启动",callback=exit,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}
else
PushButton{parent=main_page,x=2,y=17,min_width=6,text="退出",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
PushButton{parent=main_page,x=42,y=17,min_width=9,text="启动",callback=startup,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
end
if not tool_ctl.has_config then
tool_ctl.view_cfg.disable()
tool_ctl.color_cfg.disable()
end
TextBox{parent=disk_warn,y=2,text=" 磁盘空间不足",fg_bg=cpair(colors.white,colors.black)}
local disk_page = Div{parent=disk_warn,x=2,y=4,width=49}
local function delete_log()
fs.delete(ini_cfg.LogPath)
local space = fs.getFreeSpace("/")
tool_ctl.dw_free_space.set_value("可用空间: "..space.." 字节")
if not fs.exists(ini_cfg.LogPath) then
tool_ctl.dw_log_size.set_value("日志文件大小: 0 字节")
tool_ctl.dw_del_log_btn.disable()
end
if space >= req_space then tool_ctl.dw_continue.enable() end
end
TextBox{parent=disk_page,height=3,text="磁盘空间不足，无法安全配置此设备。保存配置可能失败，并可能导致配置数据丢失。"}
TextBox{parent=disk_page,y=5,height=1,text="总容量:             "..fs.getCapacity("/").." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}
tool_ctl.dw_free_space = TextBox{parent=disk_page,height=1,text="可用空间: "..fs.getFreeSpace("/").." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}
TextBox{parent=disk_page,height=1,text="所需空间:  "..req_space.." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}
if fs.exists(ini_cfg.LogPath) then
TextBox{parent=disk_page,y=9,height=2,text="如果您的日志文件在本机而非外部磁盘，删除它可能有助于释放空间。"}
tool_ctl.dw_log_size = TextBox{parent=disk_page,y=12,height=1,text="日志文件大小: "..fs.getSize(ini_cfg.LogPath).." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}
tool_ctl.dw_del_log_btn = PushButton{parent=disk_page,x=33,y=12,min_width=17,text="删除日志文件",callback=delete_log,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
else
TextBox{parent=disk_page,y=9,height=4,text="未找到日志文件，因此您需要手动释放空间。请删除您可能手动创建、与此应用无关的文件。"}
end
PushButton{parent=disk_page,y=14,min_width=6,text="退出",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
tool_ctl.dw_continue = PushButton{parent=disk_page,x=40,y=14,min_width=10,text="继续",callback=function()main_pane.set_value(1)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
tool_ctl.dw_continue.disable()
local settings = { settings_cfg, ini_cfg, tmp_cfg, fields, load_settings }
local fac_pane = facility.create(tool_ctl, main_pane, settings, fac_cfg, style)
local mek_pane = mekanism.create(tool_ctl, main_pane, settings, mek_cfg, style)
local divs = { net_cfg, log_cfg, clr_cfg, summary, import_err }
system.create(tool_ctl, main_pane, settings, divs, fac_pane, mek_pane, style, startup, exit)
local cl = Div{parent=changelog,x=2,y=4,width=49}
TextBox{parent=changelog,y=2,text=" 配置更新日志",fg_bg=bw_fg_bg}
local c_log = ListBox{parent=cl,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}
for _, change in ipairs(changes) do
TextBox{parent=c_log,text=change[1],fg_bg=bw_fg_bg}
for _, v in ipairs(change[2]) do
local e = Div{parent=c_log,height=#util.strwrap(v,46)}
TextBox{parent=e,y=1,text="- ",fg_bg=cpair(colors.gray,colors.white)}
TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
end
end
PushButton{parent=cl,y=14,text="\x1b 返回",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
end
local function reset_term()
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
end
function configurator.configure(ask_config)
tool_ctl.ask_config = ask_config == true
load_settings(settings_cfg, true)
tool_ctl.has_config = load_settings(ini_cfg)
tmp_cfg.WiredModem = ini_cfg.WiredModem
tmp_cfg.FacilityTankMode = ini_cfg.FacilityTankMode
tmp_cfg.TankFluidTypes = { table.unpack(ini_cfg.TankFluidTypes) }
reset_term()
ppm.mount_all()
for i = 1, #style.colors do
term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
end
local status, error = pcall(function ()
local display = DisplayBox{window=term.current(),fg_bg=style.root}
config_view(display)
tool_ctl.gen_modem_list()
while true do
local event, param1, param2, param3 = util.pull_event()
if event == "timer" then
tcd.handle(param1)
elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
local m_e = core.events.new_mouse_event(event, param1, param2, param3)
if m_e then display.handle_mouse(m_e) end
elseif event == "char" or event == "key" or event == "key_up" then
local k_e = core.events.new_key_event(event, param1, param2)
if k_e then display.handle_key(k_e) end
elseif event == "paste" then
display.handle_paste(param1)
elseif event == "peripheral_detach" then
ppm.handle_unmount(param1)
tool_ctl.gen_modem_list()
elseif event == "peripheral" then
ppm.mount(param1)
tool_ctl.gen_modem_list()
end
if event == "terminate" then return end
end
end)
for i = 1, #style.colors do
local r, g, b = term.nativePaletteColor(style.colors[i].c)
term.setPaletteColor(style.colors[i].c, r, g, b)
end
reset_term()
if not status then
println("configurator error: " .. error)
end
return status, error, tool_ctl.launch_startup
end
return configurator
