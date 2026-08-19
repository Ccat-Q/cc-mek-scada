local ppm         = require("scada-common.ppm")
local types       = require("scada-common.types")
local util        = require("scada-common.util")
local core        = require("graphics.core")
local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")
local PushButton  = require("graphics.elements.controls.PushButton")
local RadioButton = require("graphics.elements.controls.RadioButton")
local NumberField = require("graphics.elements.form.NumberField")
local cpair = core.cpair
local self = {
apply_mon = nil,
edit_monitor = nil,
mon_iface = "",
mon_expect = {}
}
local hmi = {}
function hmi.create(tool_ctl, main_pane, cfg_sys, divs, style)
local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
local mon_cfg, spkr_cfg, crd_cfg = divs[1], divs[2], divs[3]
local bw_fg_bg      = style.bw_fg_bg
local g_lg_fg_bg    = style.g_lg_fg_bg
local nav_fg_bg     = style.nav_fg_bg
local btn_act_fg_bg = style.btn_act_fg_bg
local btn_dis_fg_bg = style.btn_dis_fg_bg
local mon_c_1 = Div{parent=mon_cfg,x=2,y=4,width=49}
local mon_c_2 = Div{parent=mon_cfg,x=2,y=4,width=49}
local mon_c_3 = Div{parent=mon_cfg,x=2,y=4,width=49}
local mon_pane = MultiPane{parent=mon_cfg,y=4,panes={mon_c_1,mon_c_2,mon_c_3}}
TextBox{parent=mon_cfg,y=2,text=" 监视器配置",fg_bg=cpair(colors.black,colors.blue)}
TextBox{parent=mon_c_1,y=1,height=5,text="您的配置需要以下监视器。主监视器和流程监视器的高度取决于您的机组数量和冷却配置。如果您手动输入了机组数量，可能不准确的计算会显示 *。"}
local mon_reqs = ListBox{parent=mon_c_1,y=7,height=6,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}
local function next_from_reqs()
for i = tmp_cfg.UnitCount + 1, 4 do tmp_cfg.UnitDisplays[i] = nil end
tool_ctl.gen_mon_list()
mon_pane.set_value(2)
end
PushButton{parent=mon_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=mon_c_1,x=44,y=14,text="下一步 \x1a",callback=next_from_reqs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=mon_c_2,y=1,height=5,text="请在下方配置您的监视器。您可以返回上一页而不丢失进度，以再次核对您需要的配置。所有监视器都必须完成分配后才能继续。"}
local mon_list = ListBox{parent=mon_c_2,y=6,height=7,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}
local assign_err = TextBox{parent=mon_c_2,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
local function submit_monitors()
if tmp_cfg.MainDisplay == nil then
assign_err.set_value("请分配主监视器。")
elseif tmp_cfg.FlowDisplay == nil then
assign_err.set_value("请分配流程监视器。")
elseif util.table_len(tmp_cfg.UnitDisplays) ~= tmp_cfg.UnitCount then
for i = 1, tmp_cfg.UnitCount do
if tmp_cfg.UnitDisplays[i] == nil then
assign_err.set_value("请分配机组 " .. i .. " 的监视器。")
break
end
end
else
assign_err.hide(true)
main_pane.set_value(5)
return
end
assign_err.show()
end
PushButton{parent=mon_c_2,y=14,text="\x1b 返回",callback=function()mon_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=mon_c_2,x=44,y=14,text="下一步 \x1a",callback=submit_monitors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
local mon_desc = TextBox{parent=mon_c_3,y=1,height=4,text=""}
local mon_unit_l, mon_unit = nil, nil
local mon_warn = TextBox{parent=mon_c_3,y=11,height=2,text="",fg_bg=cpair(colors.red,colors.lightGray)}
local function on_assign_mon(val)
if not util.table_contains(self.mon_expect, val) then
self.apply_mon.disable()
mon_warn.set_value("该分配与监视器尺寸不匹配。您需要调整监视器大小才能使其正常工作。")
mon_warn.show()
else
self.apply_mon.enable()
mon_warn.hide(true)
end
if val == 3 then
mon_unit_l.show()
mon_unit.show()
else
mon_unit_l.hide(true)
mon_unit.hide(true)
end
local value = mon_unit.get_value()
mon_unit.set_max(tmp_cfg.UnitCount)
if value == "0" or value == nil then mon_unit.set_value(0) end
end
TextBox{parent=mon_c_3,y=6,width=10,text="分配"}
local mon_assign = RadioButton{parent=mon_c_3,y=7,default=1,options={"主监视器","流程监视器","机组监视器"},callback=on_assign_mon,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.blue}
mon_unit_l = TextBox{parent=mon_c_3,x=18,y=6,width=7,text="机组 ID"}
mon_unit = NumberField{parent=mon_c_3,x=18,y=7,width=10,max_chars=2,min=1,max=4,fg_bg=bw_fg_bg}
local mon_u_err = TextBox{parent=mon_c_3,x=8,y=14,width=35,text="请提供机组 ID。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
local function purge_assignments(iface)
if tmp_cfg.MainDisplay == iface then
tmp_cfg.MainDisplay = nil
elseif tmp_cfg.FlowDisplay == iface then
tmp_cfg.FlowDisplay = nil
else
for i = 1, tmp_cfg.UnitCount do
if tmp_cfg.UnitDisplays[i] == iface then tmp_cfg.UnitDisplays[i] = nil end
end
end
end
local function apply_monitor()
local iface = self.mon_iface
local type = mon_assign.get_value()
local u_id = tonumber(mon_unit.get_value())
if type == 1 then
purge_assignments(iface)
tmp_cfg.MainDisplay = iface
elseif type == 2 then
purge_assignments(iface)
tmp_cfg.FlowDisplay = iface
elseif u_id and u_id > 0 then
purge_assignments(iface)
tmp_cfg.UnitDisplays[u_id] = iface
else
mon_u_err.show()
return
end
tool_ctl.gen_mon_list()
mon_u_err.hide(true)
mon_pane.set_value(2)
end
PushButton{parent=mon_c_3,y=14,text="\x1b 返回",callback=function()mon_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
self.apply_mon = PushButton{parent=mon_c_3,x=43,y=14,min_width=7,text="应用",callback=apply_monitor,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
local spkr_c = Div{parent=spkr_cfg,x=2,y=4,width=49}
TextBox{parent=spkr_cfg,y=2,text=" 扬声器配置",fg_bg=cpair(colors.black,colors.cyan)}
TextBox{parent=spkr_c,y=1,height=2,text="协调器使用扬声器播放警报音。"}
TextBox{parent=spkr_c,y=4,height=3,text="您可以更改扬声器音频音量（相对于默认值）。范围为 0.0 至 3.0，其中 1.0 为标准音量。"}
tool_ctl.s_vol = NumberField{parent=spkr_c,y=8,width=9,max_chars=7,allow_decimal=true,default=ini_cfg.SpeakerVolume,min=0,max=3,fg_bg=bw_fg_bg}
TextBox{parent=spkr_c,y=10,height=3,text="注意：警报正弦波为半幅度，因此需要多个才能达到满幅度。",fg_bg=g_lg_fg_bg}
local s_vol_err = TextBox{parent=spkr_c,x=8,y=14,width=35,text="请设置音量。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
local function submit_vol()
local vol = tonumber(tool_ctl.s_vol.get_value())
if vol ~= nil then
s_vol_err.hide(true)
tmp_cfg.SpeakerVolume = vol
main_pane.set_value(6)
else s_vol_err.show() end
end
PushButton{parent=spkr_c,y=14,text="\x1b 返回",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=spkr_c,x=44,y=14,text="下一步 \x1a",callback=submit_vol,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
local crd_c_1 = Div{parent=crd_cfg,x=2,y=4,width=49}
TextBox{parent=crd_cfg,y=2,text=" 协调器 UI 配置",fg_bg=cpair(colors.black,colors.lime)}
TextBox{parent=crd_c_1,y=1,height=2,text="您可以使用下面的界面选项自定义 UI。"}
TextBox{parent=crd_c_1,y=4,text="时钟时间格式"}
tool_ctl.clock_fmt = RadioButton{parent=crd_c_1,y=5,default=util.trinary(ini_cfg.Time24Hour,1,2),options={"24 小时","12 小时"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}
TextBox{parent=crd_c_1,x=20,y=4,text="Po/Pu 燃料丸颜色"}
tool_ctl.pellet_color = RadioButton{parent=crd_c_1,x=20,y=5,default=util.trinary(ini_cfg.GreenPuPellet,1,2),options={"绿色 Pu/青色 Po","青色 Pu/绿色 Po (Mek 10.4+)"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}
TextBox{parent=crd_c_1,y=8,text="温度单位"}
tool_ctl.temp_scale = RadioButton{parent=crd_c_1,y=9,default=ini_cfg.TempScale,options=types.TEMP_SCALE_NAMES,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}
TextBox{parent=crd_c_1,x=20,y=8,text="能量单位"}
tool_ctl.energy_scale = RadioButton{parent=crd_c_1,x=20,y=9,default=ini_cfg.EnergyScale,options=types.ENERGY_SCALE_NAMES,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}
local function submit_ui_opts()
tmp_cfg.Time24Hour = tool_ctl.clock_fmt.get_value() == 1
tmp_cfg.GreenPuPellet = tool_ctl.pellet_color.get_value() == 1
tmp_cfg.TempScale = tool_ctl.temp_scale.get_value()
tmp_cfg.EnergyScale = tool_ctl.energy_scale.get_value()
main_pane.set_value(7)
end
PushButton{parent=crd_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=crd_c_1,x=44,y=14,text="下一步 \x1a",callback=submit_ui_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
function tool_ctl.update_mon_reqs()
local plural = tmp_cfg.UnitCount > 1
if tool_ctl.sv_cool_conf ~= nil then
local cnf = tool_ctl.sv_cool_conf
local row1_tall = cnf[1][1] > 1 or cnf[1][2] > 2 or (cnf[2] and (cnf[2][1] > 1 or cnf[2][2] > 2))
local row1_short = (cnf[1][1] == 0 and cnf[1][2] == 1) and (cnf[2] == nil or (cnf[2][1] == 0 and cnf[2][2] == 1))
local row2_tall = (cnf[3] and (cnf[3][1] > 1 or cnf[3][2] > 2)) or (cnf[4] and (cnf[4][1] > 1 or cnf[4][2] > 2))
local row2_short = (cnf[3] == nil or (cnf[3][1] == 0 and cnf[3][2] == 1)) and (cnf[4] == nil or (cnf[4][1] == 0 and cnf[4][2] == 1))
if tmp_cfg.UnitCount <= 2 then
tool_ctl.main_mon_h = util.trinary(row1_tall, 5, 4)
else
if row1_tall or row2_tall then
tool_ctl.main_mon_h = util.trinary((row1_short and row2_tall) or (row1_tall and row2_short), 5, 6)
else tool_ctl.main_mon_h = 5 end
end
else
tool_ctl.main_mon_h = util.trinary(tmp_cfg.UnitCount <= 2, 4, 5)
end
tool_ctl.flow_mon_h = 2 + tmp_cfg.UnitCount
local asterisk = util.trinary(tool_ctl.sv_cool_conf == nil, "*", "")
local m_at_least = util.trinary(tool_ctl.main_mon_h < 6, "至少 ", "")
local f_at_least = util.trinary(tool_ctl.flow_mon_h < 6, "至少 ", "")
mon_reqs.remove_all()
TextBox{parent=mon_reqs,y=1,text="\x1a "..tmp_cfg.UnitCount.." 台机组视图监视器"..util.trinary(plural,"","")}
TextBox{parent=mon_reqs,y=1,text="  "..util.trinary(plural,"每台","").."必须为 4 格宽 × 4 格高",fg_bg=cpair(colors.gray,colors.white)}
TextBox{parent=mon_reqs,y=1,text="\x1a 1 台主视图监视器"}
TextBox{parent=mon_reqs,y=1,text="  必须为 8 格宽 × "..m_at_least..tool_ctl.main_mon_h..asterisk.." 格高",fg_bg=cpair(colors.gray,colors.white)}
TextBox{parent=mon_reqs,y=1,text="\x1a 1 台流程视图监视器"}
TextBox{parent=mon_reqs,y=1,text="  必须为 8 格宽 × "..f_at_least..tool_ctl.flow_mon_h.." 格高",fg_bg=cpair(colors.gray,colors.white)}
end
function self.edit_monitor(iface, device)
self.mon_iface = iface
local dev = device.dev
local w, h = ppm.monitor_block_size(dev.getSize())
local msg = "此尺寸与所需屏幕不匹配。请返回并调整大小，或冒其无法正常工作的风险在下方进行配置。"
self.mon_expect = {}
mon_assign.set_value(1)
mon_unit.set_value(0)
if w == 4 and h == 4 then
msg = "此尺寸可用作机组显示器。请在下方配置。"
self.mon_expect = { 3 }
mon_assign.set_value(3)
elseif w == 8 then
if h >= tool_ctl.main_mon_h and h >= tool_ctl.flow_mon_h then
msg = "此尺寸可用作主监视器或流程监视器。请在下方配置。"
self.mon_expect = { 1, 2 }
if tmp_cfg.MainDisplay then mon_assign.set_value(2) end
elseif h >= tool_ctl.main_mon_h then
msg = "此尺寸可用作主监视器。请在下方配置。"
self.mon_expect = { 1 }
elseif h >= tool_ctl.flow_mon_h then
msg = "此尺寸可用作流程监视器。请在下方配置。"
self.mon_expect = { 2 }
mon_assign.set_value(2)
end
end
if tmp_cfg.MainDisplay == iface then
mon_assign.set_value(1)
elseif tmp_cfg.FlowDisplay == iface then
mon_assign.set_value(2)
else
for i = 1, tmp_cfg.UnitCount do
if tmp_cfg.UnitDisplays[i] == iface then
mon_assign.set_value(3)
mon_unit.set_value(i)
break
end
end
end
on_assign_mon(mon_assign.get_value())
mon_desc.set_value(util.c("您已选择 '", iface, "'，其尺寸为 ", w, " 格宽 × ", h, " 格高。", msg))
mon_pane.set_value(3)
end
function tool_ctl.gen_mon_list()
mon_list.remove_all()
local missing = { main = tmp_cfg.MainDisplay ~= nil, flow = tmp_cfg.FlowDisplay ~= nil, unit = {} }
for i = 1, tmp_cfg.UnitCount do missing.unit[i] = tmp_cfg.UnitDisplays[i] ~= nil end
local monitors = ppm.get_monitor_list()
for iface, device in pairs(monitors) do
local dev = device.dev
dev.setTextScale(0.5)
dev.setTextColor(colors.white)
dev.setBackgroundColor(colors.black)
dev.clear()
dev.setCursorPos(1, 1)
dev.setTextColor(colors.magenta)
dev.write("这是监视器")
dev.setCursorPos(1, 2)
dev.setTextColor(colors.white)
dev.write(iface)
local assignment = "Unused"
if tmp_cfg.MainDisplay == iface then
assignment = "主"
missing.main = false
elseif tmp_cfg.FlowDisplay == iface then
assignment = "流程"
missing.flow = false
else
for i = 1, tmp_cfg.UnitCount do
if tmp_cfg.UnitDisplays[i] == iface then
missing.unit[i] = false
assignment = "机组 " .. i
break
end
end
end
local line = Div{parent=mon_list,y=1,height=1}
TextBox{parent=line,y=1,width=6,text=assignment,fg_bg=cpair(util.trinary(assignment=="Unused",colors.red,colors.blue),colors.white)}
TextBox{parent=line,x=8,y=1,text=iface}
local w, h = ppm.monitor_block_size(dev.getSize())
local function unset_mon()
purge_assignments(iface)
tool_ctl.gen_mon_list()
end
TextBox{parent=line,x=33,y=1,width=4,text=w.."x"..h,fg_bg=cpair(colors.black,colors.white)}
PushButton{parent=line,x=37,y=1,min_width=5,height=1,text="设置",callback=function()self.edit_monitor(iface,device)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
local unset = PushButton{parent=line,x=42,y=1,min_width=7,height=1,text="取消",callback=unset_mon,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.black,colors.gray)}
if assignment == "Unused" then unset.disable() end
end
local dc_list = {}
if missing.main then table.insert(dc_list, { "主", tmp_cfg.MainDisplay }) end
if missing.flow then table.insert(dc_list, { "流程", tmp_cfg.FlowDisplay }) end
for i = 1, tmp_cfg.UnitCount do
if missing.unit[i] then table.insert(dc_list, { "机组 " .. i, tmp_cfg.UnitDisplays[i] }) end
end
for i = 1, #dc_list do
local line = Div{parent=mon_list,y=1,height=1}
TextBox{parent=line,y=1,width=6,text=dc_list[i][1],fg_bg=cpair(colors.blue,colors.white)}
TextBox{parent=line,x=8,y=1,text="已断开",fg_bg=cpair(colors.red,colors.white)}
local function unset_mon()
purge_assignments(dc_list[i][2])
tool_ctl.gen_mon_list()
end
TextBox{parent=line,x=33,y=1,width=4,text="?x?",fg_bg=cpair(colors.black,colors.white)}
PushButton{parent=line,x=37,y=1,min_width=5,height=1,text="设置",callback=function()end,dis_fg_bg=cpair(colors.black,colors.gray)}.disable()
PushButton{parent=line,x=42,y=1,min_width=7,height=1,text="取消",callback=unset_mon,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.black,colors.gray)}
end
end
return mon_pane
end
return hmi
