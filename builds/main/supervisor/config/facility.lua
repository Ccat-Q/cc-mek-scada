local util        = require("scada-common.util")
local core        = require("graphics.core")
local Div         = require("graphics.elements.Div")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")
local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local Radio2D     = require("graphics.elements.controls.Radio2D")
local RadioButton = require("graphics.elements.controls.RadioButton")
local NumberField = require("graphics.elements.form.NumberField")
local tri = util.trinary
local cpair = core.cpair
local self = {
any_has_tank = false,
vis_draw = nil,
draw_fluid_ops = nil,
vis_ftanks = {},
vis_utanks = {}
}
local facility = {}
function facility.generate_tank_list_and_conns(mode, defs)
local tank_mode = mode
local tank_defs = defs
local tank_list = { table.unpack(tank_defs) }
local tank_conns = { table.unpack(tank_defs) }
local function calc_fdef(start_idx, end_idx)
local first = 4
for i = start_idx, end_idx do
if tank_defs[i] == 2 then
if i < first then first = i end
end
end
return first
end
for i = 1, #tank_defs do
if tank_defs[i] == 1 then tank_conns[i] = i end
end
if tank_mode == 1 then
local first_fdef = calc_fdef(1, #tank_defs)
for i = 1, #tank_defs do
if (i >= first_fdef) and (tank_defs[i] == 2) then
tank_conns[i] = first_fdef
if i > first_fdef then tank_list[i] = 0 end
end
end
elseif tank_mode == 2 then
local first_fdef = calc_fdef(1, math.min(3, #tank_defs))
for i = 1, #tank_defs do
if (i >= first_fdef) and (tank_defs[i] == 2) then
if i == 4 then
tank_conns[i] = 4
else
tank_conns[i] = first_fdef
if i > first_fdef then tank_list[i] = 0 end
end
end
end
elseif tank_mode == 3 then
for _, a in pairs({ 1, 3 }) do
local b = a + 1
if tank_defs[a] == 2 then
tank_conns[a] = a
elseif tank_defs[b] == 2 then
tank_conns[b] = b
end
if (tank_defs[a] == 2) and (tank_defs[b] == 2) then
tank_list[b] = 0
tank_conns[b] = a
end
end
elseif tank_mode == 4 then
local first_fdef = calc_fdef(2, #tank_defs)
for i = 1, #tank_defs do
if tank_defs[i] == 2 then
if i == 1 then
tank_conns[i] = 1
elseif i >= first_fdef then
tank_conns[i] = first_fdef
if i > first_fdef then tank_list[i] = 0 end
end
end
end
elseif tank_mode == 5 then
local first_fdef = calc_fdef(1, math.min(2, #tank_defs))
for i = 1, #tank_defs do
if (i >= first_fdef) and (tank_defs[i] == 2) then
if i == 3 or i == 4 then
tank_conns[i] = i
elseif i >= first_fdef then
tank_conns[i] = first_fdef
if i > first_fdef then tank_list[i] = 0 end
end
end
end
elseif tank_mode == 6 then
local first_fdef = calc_fdef(2, math.min(3, #tank_defs))
for i = 1, #tank_defs do
if tank_defs[i] == 2 then
if i == 1 or i == 4 then
tank_conns[i] = i
elseif i >= first_fdef then
tank_conns[i] = first_fdef
if i > first_fdef then tank_list[i] = 0 end
end
end
end
elseif tank_mode == 7 then
local first_fdef = calc_fdef(3, #tank_defs)
for i = 1, #tank_defs do
if tank_defs[i] == 2 then
if i == 1 or i == 2 then
tank_conns[i] = i
elseif i >= first_fdef then
tank_conns[i] = first_fdef
if i > first_fdef then tank_list[i] = 0 end
end
end
end
elseif tank_mode == 8 then
for i = 1, #tank_defs do
if tank_defs[i] == 2 then tank_conns[i] = i end
end
end
return tank_list, tank_conns
end
function facility.create(tool_ctl, main_pane, cfg_sys, fac_cfg, style)
local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
local bw_fg_bg      = style.bw_fg_bg
local g_lg_fg_bg    = style.g_lg_fg_bg
local nav_fg_bg     = style.nav_fg_bg
local btn_act_fg_bg = style.btn_act_fg_bg
local fac_c_1 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_2 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_3 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_4 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_5 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_6 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_7 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_8 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_9 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_10 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_11 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_c_12 = Div{parent=fac_cfg,x=2,y=4,width=49}
local fac_pane = MultiPane{parent=fac_cfg,y=4,panes={fac_c_1,fac_c_2,fac_c_3,fac_c_4,fac_c_5,fac_c_6,fac_c_7,fac_c_8,fac_c_9,fac_c_10,fac_c_11,fac_c_12}}
TextBox{parent=fac_cfg,y=2,text=" 设施配置",fg_bg=cpair(colors.black,colors.yellow)}
TextBox{parent=fac_c_1,y=1,height=3,text="请输入您拥有的反应堆数量，也简称为反应堆机组或“机组”。目前最多支持 4 台。"}
tool_ctl.num_units = NumberField{parent=fac_c_1,y=5,width=5,max_chars=2,default=ini_cfg.UnitCount,min=1,max=4,fg_bg=bw_fg_bg}
TextBox{parent=fac_c_1,x=7,y=5,text="反应堆"}
TextBox{parent=fac_c_1,y=7,height=3,text="如果您已经配置了协调器，请确保更新协调器中配置的机组数量。",fg_bg=cpair(colors.yellow,colors._INHERIT)}
local nu_error = TextBox{parent=fac_c_1,x=8,y=14,width=35,text="请设置反应堆数量。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
local function submit_num_units()
local count = tonumber(tool_ctl.num_units.get_value())
if count ~= nil and count > 0 and count < 5 then
nu_error.hide(true)
tmp_cfg.UnitCount = count
local c_confs = tool_ctl.cooling_elems
local a_confs = tool_ctl.aux_cool_elems
for i = 2, 4 do
if count >= i then
c_confs[i].line.show()
a_confs[i].line.show()
else
c_confs[i].line.hide(true)
a_confs[i].line.hide(true)
end
end
fac_pane.set_value(2)
else nu_error.show() end
end
PushButton{parent=fac_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_1,x=44,y=14,text="下一步 \x1a",callback=submit_num_units,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_2,y=1,height=4,text="请在下方提供反应堆冷却配置。包括涡轮机、锅炉的数量，以及该反应堆是否连接到动态储罐以提供紧急冷却。"}
TextBox{parent=fac_c_2,y=6,text="机组    涡轮机  锅炉  是否连接储罐?",fg_bg=g_lg_fg_bg}
for i = 1, 4 do
local num_t, num_b, has_t = 1, 0, false
if ini_cfg.CoolingConfig[i] then
local conf = ini_cfg.CoolingConfig[i]
if util.is_int(conf.TurbineCount) then num_t = math.min(3, math.max(1, conf.TurbineCount or 1)) end
if util.is_int(conf.BoilerCount) then num_b = math.min(2, math.max(0, conf.BoilerCount or 0)) end
has_t = conf.TankConnection == true
end
local line = Div{parent=fac_c_2,y=7+i,height=1}
TextBox{parent=line,text="机组 "..i,width=6}
local turbines = NumberField{parent=line,x=9,y=1,width=5,max_chars=2,default=num_t,min=1,max=3,fg_bg=bw_fg_bg}
local boilers = NumberField{parent=line,x=20,y=1,width=5,max_chars=2,default=num_b,min=0,max=2,fg_bg=bw_fg_bg}
local tank = Checkbox{parent=line,x=30,y=1,label="已连接",default=has_t,box_fg_bg=cpair(colors.yellow,colors.black)}
tool_ctl.cooling_elems[i] = { line = line, turbines = turbines, boilers = boilers, tank = tank }
end
local cool_err = TextBox{parent=fac_c_2,x=8,y=14,width=33,text="请填写所有字段。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
local function submit_cooling()
local any_missing = false
for i = 1, tmp_cfg.UnitCount do
local conf = tool_ctl.cooling_elems[i]
any_missing = any_missing or (tonumber(conf.turbines.get_value()) == nil)
any_missing = any_missing or (tonumber(conf.boilers.get_value()) == nil)
end
if any_missing then
cool_err.show()
else
self.any_has_tank = false
tmp_cfg.CoolingConfig = {}
for i = 1, tmp_cfg.UnitCount do
local conf = tool_ctl.cooling_elems[i]
tmp_cfg.CoolingConfig[i] = {
TurbineCount = tonumber(conf.turbines.get_value()),
BoilerCount = tonumber(conf.boilers.get_value()),
TankConnection = conf.tank.get_value()
}
if conf.tank.get_value() then self.any_has_tank = true end
end
for i = 1, 4 do
local elem = tool_ctl.tank_elems[i]
if i <= tmp_cfg.UnitCount then
elem.div.show()
if tmp_cfg.CoolingConfig[i].TankConnection then
elem.no_tank.hide()
elem.tank_opt.show()
else
elem.tank_opt.hide(true)
elem.no_tank.show()
end
else elem.div.hide(true) end
end
if not self.any_has_tank then
tmp_cfg.FacilityTankMode = 0
tmp_cfg.FacilityTankDefs = {}
tmp_cfg.FacilityTankList = {}
tmp_cfg.FacilityTankConns = {}
tmp_cfg.TankFluidTypes = {}
end
if self.any_has_tank then fac_pane.set_value(3) else fac_pane.set_value(8) end
end
end
PushButton{parent=fac_c_2,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_2,x=44,y=14,text="下一步 \x1a",callback=submit_cooling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_3,y=1,height=6,text="您已将一台或多台机组设置为使用动态储罐提供紧急冷却。您有两条配置路径。第一种是为反应堆机组分配动态储罐；每个反应堆一个储罐，仅连接到该反应堆。RTU 配置也必须如此分配。"}
TextBox{parent=fac_c_3,y=8,height=3,text="或者，您可以将它们配置为设施储罐，以连接到多台反应堆机组。这些可以与机组专用储罐混合使用。"}
tool_ctl.en_fac_tanks = Checkbox{parent=fac_c_3,y=12,label="使用设施动态储罐",default=ini_cfg.FacilityTankMode>0,box_fg_bg=cpair(colors.yellow,colors.black)}
local function submit_en_fac_tank()
if tool_ctl.en_fac_tanks.get_value() then
fac_pane.set_value(4)
tmp_cfg.FacilityTankMode = tri(tmp_cfg.FacilityTankMode == 0, 1, math.min(8, math.max(1, ini_cfg.FacilityTankMode)))
else
tmp_cfg.FacilityTankMode = 0
tmp_cfg.FacilityTankDefs = {}
for i = 1, tmp_cfg.UnitCount do
tmp_cfg.FacilityTankDefs[i] = tri(tmp_cfg.CoolingConfig[i].TankConnection, 1, 0)
end
tmp_cfg.FacilityTankList, tmp_cfg.FacilityTankConns = facility.generate_tank_list_and_conns(tmp_cfg.FacilityTankMode, tmp_cfg.FacilityTankDefs)
self.draw_fluid_ops()
fac_pane.set_value(7)
end
end
PushButton{parent=fac_c_3,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_3,x=44,y=14,text="下一步 \x1a",callback=submit_en_fac_tank,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_4,y=1,height=4,text="请设置机组与动态储罐的连接，至少选择一个设施储罐。设施储罐的布局将在下一步配置。"}
for i = 1, 4 do
local val = math.max(1, ini_cfg.FacilityTankDefs[i] or 2)
local div = Div{parent=fac_c_4,y=3+(2*i),height=2}
TextBox{parent=div,y=1,width=33,text="机组 "..i.." 将连接到..."}
TextBox{parent=div,x=6,y=2,width=3,text="..."}
local tank_opt = Radio2D{parent=div,x=9,y=2,rows=1,columns=2,default=val,options={"自身机组储罐","设施储罐"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
local no_tank = TextBox{parent=div,x=9,y=2,width=34,text="无储罐（如两步前所设置）",fg_bg=cpair(colors.gray,colors.lightGray),hidden=true}
tool_ctl.tank_elems[i] = { div = div, tank_opt = tank_opt, no_tank = no_tank }
end
local tank_err = TextBox{parent=fac_c_4,x=8,y=14,width=33,text="您未选择任何设施储罐。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
local function hide_fconn(i)
if i > 1 then self.vis_ftanks[i].pipe_conn.hide(true)
else self.vis_ftanks[i].line.hide(true) end
end
local function submit_tank_defs()
local any_fac = false
tmp_cfg.FacilityTankDefs = {}
for i = 1, tmp_cfg.UnitCount do
local def
if tmp_cfg.CoolingConfig[i].TankConnection then
def = tool_ctl.tank_elems[i].tank_opt.get_value()
any_fac = any_fac or (def == 2)
else def = 0 end
if def == 1 then
self.vis_utanks[i].line.show()
self.vis_utanks[i].label.set_value("储罐 U" .. i)
hide_fconn(i)
else
if def == 2 then
if i > 1 then self.vis_ftanks[i].pipe_conn.show()
else self.vis_ftanks[i].line.show() end
else hide_fconn(i) end
self.vis_utanks[i].line.hide(true)
end
tmp_cfg.FacilityTankDefs[i] = def
end
for i = tmp_cfg.UnitCount + 1, 4 do
self.vis_utanks[i].line.hide(true)
end
self.vis_draw(tmp_cfg.FacilityTankMode)
if any_fac then
tank_err.hide(true)
fac_pane.set_value(5)
else tank_err.show() end
end
PushButton{parent=fac_c_4,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_4,x=44,y=14,text="下一步 \x1a",callback=submit_tank_defs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_5,y=1,text="请选择您的动态储罐布局。"}
TextBox{parent=fac_c_5,x=12,y=3,text="设施储罐                机组储罐",fg_bg=g_lg_fg_bg}
local pipe_cpair = cpair(colors.blue,colors.lightGray)
local vis = Div{parent=fac_c_5,x=14,y=5,height=7}
local vis_unit_list = TextBox{parent=vis,x=15,y=1,width=6,height=7,text="机组 1\n\n机组 2\n\n机组 3\n\n机组 4"}
for i = 1, 4 do
local line = Div{parent=vis,x=22,y=(i*2)-1,width=13,height=1}
TextBox{parent=line,width=5,text=string.rep("\x8c",5),fg_bg=pipe_cpair}
local label = TextBox{parent=line,x=7,y=1,width=7,text="储罐 ?"}
self.vis_utanks[i] = { line = line, label = label }
end
local ftank_1 = Div{parent=vis,y=1,width=13,height=1}
TextBox{parent=ftank_1,width=7,text="储罐 F1"}
self.vis_ftanks[1] = {
line = ftank_1, pipe_direct = TextBox{parent=ftank_1,x=9,y=1,width=5,text=string.rep("\x8c",5),fg_bg=pipe_cpair}
}
for i = 2, 4 do
local line = Div{parent=vis,y=(i-1)*2,width=13,height=2}
local pipe_conn = TextBox{parent=line,x=13,y=2,width=1,text="\x8c",fg_bg=pipe_cpair}
local pipe_chain = TextBox{parent=line,x=12,y=1,width=1,height=2,text="\x95\n\x8d",fg_bg=pipe_cpair}
local pipe_direct = TextBox{parent=line,x=9,y=2,width=4,text="\x8c\x8c\x8c\x8c",fg_bg=pipe_cpair}
local label = TextBox{parent=line,y=2,width=7,text=""}
self.vis_ftanks[i] = { line = line, pipe_conn = pipe_conn, pipe_chain = pipe_chain, pipe_direct = pipe_direct, label = label }
end
function self.vis_draw(mode)
local function is_ft(i) return tmp_cfg.FacilityTankDefs[i] == 2 end
local u_text = ""
for i = 1, tmp_cfg.UnitCount do
u_text = u_text .. "机组 " .. i .. "\n\n"
end
vis_unit_list.set_value(u_text)
local vis_ftanks = self.vis_ftanks
local next_idx = 1
if is_ft(1) then
next_idx = 2
if (mode == 1 and (is_ft(2) or is_ft(3) or is_ft(4))) or (mode == 2 and (is_ft(2) or is_ft(3))) or ((mode == 3 or mode == 5) and is_ft(2)) then
vis_ftanks[1].pipe_direct.set_value("\x8c\x8c\x8c\x9c\x8c")
else
vis_ftanks[1].pipe_direct.set_value(string.rep("\x8c",5))
end
end
local _2_12_need_passt = (mode == 1 and (is_ft(3) or is_ft(4))) or (mode == 2 and is_ft(3))
local _2_46_need_chain = (mode == 4 and (is_ft(3) or is_ft(4))) or (mode == 6 and is_ft(3))
if is_ft(2) then
vis_ftanks[2].label.set_value("储罐 F" .. next_idx)
if (mode < 4 or mode == 5) and is_ft(1) then
vis_ftanks[2].label.hide(true)
vis_ftanks[2].pipe_direct.hide(true)
if _2_12_need_passt then
vis_ftanks[2].pipe_chain.set_value("\x95\n\x9d")
else
vis_ftanks[2].pipe_chain.set_value("\x95\n\x8d")
end
vis_ftanks[2].pipe_chain.show()
else
vis_ftanks[2].label.show()
next_idx = next_idx + 1
vis_ftanks[2].pipe_chain.hide(true)
if _2_12_need_passt or _2_46_need_chain then
vis_ftanks[2].pipe_direct.set_value("\x8c\x8c\x8c\x9c")
else
vis_ftanks[2].pipe_direct.set_value("\x8c\x8c\x8c\x8c")
end
vis_ftanks[2].pipe_direct.show()
end
vis_ftanks[2].line.show()
elseif is_ft(1) and _2_12_need_passt then
vis_ftanks[2].label.hide(true)
vis_ftanks[2].pipe_direct.hide(true)
vis_ftanks[2].pipe_chain.set_value("\x95\n\x95")
vis_ftanks[2].pipe_chain.show()
vis_ftanks[2].line.show()
else
vis_ftanks[2].line.hide(true)
end
if is_ft(3) then
vis_ftanks[3].label.set_value("储罐 F" .. next_idx)
if (mode < 3 and (is_ft(1) or is_ft(2))) or ((mode == 4 or mode == 6) and is_ft(2)) then
vis_ftanks[3].label.hide(true)
vis_ftanks[3].pipe_direct.hide(true)
if (mode == 1 or mode == 4) and is_ft(4) then
vis_ftanks[3].pipe_chain.set_value("\x95\n\x9d")
else
vis_ftanks[3].pipe_chain.set_value("\x95\n\x8d")
end
vis_ftanks[3].pipe_chain.show()
else
vis_ftanks[3].label.show()
next_idx = next_idx + 1
vis_ftanks[3].pipe_chain.hide(true)
if (mode == 1 or mode == 3 or mode == 4 or mode == 7) and is_ft(4) then
vis_ftanks[3].pipe_direct.set_value("\x8c\x8c\x8c\x9c")
else
vis_ftanks[3].pipe_direct.set_value("\x8c\x8c\x8c\x8c")
end
vis_ftanks[3].pipe_direct.show()
end
vis_ftanks[3].line.show()
elseif (mode == 1 and is_ft(4) and (is_ft(1) or is_ft(2))) or (mode == 4 and is_ft(2) and is_ft(4)) then
vis_ftanks[3].label.hide(true)
vis_ftanks[3].pipe_direct.hide(true)
vis_ftanks[3].pipe_chain.set_value("\x95\n\x95")
vis_ftanks[3].pipe_chain.show()
vis_ftanks[3].line.show()
else
vis_ftanks[3].line.hide(true)
end
if is_ft(4) then
vis_ftanks[4].label.set_value("储罐 F" .. next_idx)
if (mode == 1 and (is_ft(1) or is_ft(2) or is_ft(3))) or ((mode == 3 or mode == 7) and is_ft(3)) or (mode == 4 and (is_ft(2) or is_ft(3))) then
vis_ftanks[4].label.hide(true)
vis_ftanks[4].pipe_direct.hide(true)
vis_ftanks[4].pipe_chain.show()
else
vis_ftanks[4].label.show()
vis_ftanks[4].pipe_chain.hide(true)
vis_ftanks[4].pipe_direct.show()
end
vis_ftanks[4].line.show()
else
vis_ftanks[4].line.hide(true)
end
end
local function change_mode(mode)
tmp_cfg.FacilityTankMode = mode
self.vis_draw(mode)
end
local tank_modes = { "模式 1", "模式 2", "模式 3", "模式 4", "模式 5", "模式 6", "模式 7", "模式 8" }
tool_ctl.tank_mode = RadioButton{parent=fac_c_5,y=4,callback=change_mode,default=math.max(1,ini_cfg.FacilityTankMode),options=tank_modes,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow}
local function next_from_tank_mode()
tmp_cfg.FacilityTankList, tmp_cfg.FacilityTankConns = facility.generate_tank_list_and_conns(tmp_cfg.FacilityTankMode, tmp_cfg.FacilityTankDefs)
self.draw_fluid_ops()
fac_pane.set_value(7)
end
PushButton{parent=fac_c_5,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_5,x=44,y=14,text="下一步 \x1a",callback=next_from_tank_mode,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_5,x=8,y=14,min_width=7,text="关于",callback=function()fac_pane.set_value(6)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_6,height=3,text="此可视化工具显示您所选特定动态储罐配置所需的管道连接。"}
TextBox{parent=fac_c_6,y=5,height=4,text="示例：U2 储罐应在 RTU 上配置为 2 号机组的动态储罐。F3 储罐应在 RTU 上配置为设施的 3 号动态储罐。"}
TextBox{parent=fac_c_6,y=10,height=3,text="如果未使用 4 台反应堆机组，某些模式可能看起来相同。Wiki 中有详细说明。看起来相同的模式功能也相同。",fg_bg=g_lg_fg_bg}
PushButton{parent=fac_c_6,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_7,height=3,text="指定每个储罐的冷却剂类型，仅用于显示。如果一台或多台连接的机组为水冷，则只能选择水。"}
local tank_fluid_list = Div{parent=fac_c_7,y=5,height=8}
function self.draw_fluid_ops()
tank_fluid_list.remove_all()
local tank_list = tmp_cfg.FacilityTankList
local tank_conns = tmp_cfg.FacilityTankConns
local next_f = 1
for i = 1, #tank_list do
local type = tmp_cfg.TankFluidTypes[i]
if type == 0 then type = 1 end
tool_ctl.tank_fluid_opts[i] = nil
if tank_list[i] == 1 then
local row = Div{parent=tank_fluid_list,height=2}
TextBox{parent=row,width=11,text="机组储罐 "..i}
TextBox{parent=row,text="连接至：机组 "..i,fg_bg=cpair(colors.gray,colors.lightGray)}
local tank_fluid = Radio2D{parent=row,x=34,y=1,rows=1,columns=2,default=type,options={"水","钠"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
if tmp_cfg.CoolingConfig[i].BoilerCount == 0 then
tank_fluid.set_value(1)
tank_fluid.disable()
end
tool_ctl.tank_fluid_opts[i] = tank_fluid
elseif tank_list[i] == 2 then
local row = Div{parent=tank_fluid_list,height=2}
TextBox{parent=row,width=15,text="设施储罐 "..next_f}
local conns = ""
local any_bwr = false
for u = 1, #tank_conns do
if tank_conns[u] == i then
conns = conns .. tri(conns == "", "", ", ") .. "机组 " .. u
any_bwr = any_bwr or (tmp_cfg.CoolingConfig[u].BoilerCount == 0)
end
end
TextBox{parent=row,text="连接至："..conns,fg_bg=cpair(colors.gray,colors.lightGray)}
local tank_fluid = Radio2D{parent=row,x=34,y=1,rows=1,columns=2,default=type,options={"水","钠"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
if any_bwr then
tank_fluid.set_value(1)
tank_fluid.disable()
end
tool_ctl.tank_fluid_opts[i] = tank_fluid
next_f = next_f + 1
end
end
end
local function back_from_fluids()
fac_pane.set_value(tri(tmp_cfg.FacilityTankMode == 0, 3, 5))
end
local function submit_tank_fluids()
tmp_cfg.TankFluidTypes = {}
for i = 1, #tmp_cfg.FacilityTankList do
if tool_ctl.tank_fluid_opts[i] ~= nil then
tmp_cfg.TankFluidTypes[i] = tool_ctl.tank_fluid_opts[i].get_value()
else tmp_cfg.TankFluidTypes[i] = 0 end
end
fac_pane.set_value(8)
end
PushButton{parent=fac_c_7,y=14,text="\x1b 返回",callback=back_from_fluids,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_7,x=44,y=14,text="下一步 \x1a",callback=submit_tank_fluids,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_8,height=5,text="可以为机组启用辅助水冷却，以便在涡轮机提升功率期间提供额外的水。对于水冷反应堆，水进入反应堆。对于钠冷反应堆，水进入锅炉。"}
for i = 1, 4 do
local line = Div{parent=fac_c_8,y=7+i,height=1}
TextBox{parent=line,text="机组 "..i.." -",width=8}
local aux_cool = Checkbox{parent=line,x=10,y=1,label="有辅助冷却",default=ini_cfg.AuxiliaryCoolant[i],box_fg_bg=cpair(colors.yellow,colors.black)}
tool_ctl.aux_cool_elems[i] = { line = line, enable = aux_cool }
end
local function back_from_aux_cool()
if self.any_has_tank then fac_pane.set_value(7) else fac_pane.set_value(2) end
end
local function submit_aux_cool()
tmp_cfg.AuxiliaryCoolant = {}
for i = 1, tmp_cfg.UnitCount do
tmp_cfg.AuxiliaryCoolant[i] = tool_ctl.aux_cool_elems[i].enable.get_value()
end
fac_pane.set_value(9)
end
PushButton{parent=fac_c_8,y=14,text="\x1b 返回",callback=back_from_aux_cool,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_8,x=44,y=14,text="下一步 \x1a",callback=submit_aux_cool,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_9,height=6,text="充能水平控制可自动维持感应矩阵的充能水平。为获得更平滑的控制，已启动的反应堆将在短暂时间内以 0.01 mB/t 保持运行，然后才允许关闭。这可以最大限度地减少对充能目标的过冲。"}
TextBox{parent=fac_c_9,y=8,height=3,text="您可以将此延长至整整一分钟，以尽量减少反应堆反复启停，但可能会有更多目标过冲。"}
tool_ctl.ext_idling = Checkbox{parent=fac_c_9,y=12,label="启用延长待机",default=ini_cfg.ExtChargeIdling,box_fg_bg=cpair(colors.yellow,colors.black)}
local function submit_idling()
tmp_cfg.ExtChargeIdling = tool_ctl.ext_idling.get_value()
fac_pane.set_value(10)
end
PushButton{parent=fac_c_9,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(8)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_9,x=44,y=14,text="下一步 \x1a",callback=submit_idling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_10,height=3,text="流量显示和其他数据显示使用已连接的太阳能中子活化器 (SNA) 来指示钋产量值。"}
TextBox{parent=fac_c_10,y=5,height=3,text="如果您未使用 SNA，可以取消选择此选项，让监控端根据当前燃烧速率计算估算值。"}
tool_ctl.sna_stats = Checkbox{parent=fac_c_10,y=9,label="使用 SNA 统计钋产量",default=ini_cfg.UseSNAStatistics,box_fg_bg=cpair(colors.yellow,colors.black)}
TextBox{parent=fac_c_10,x=30,y=9,text="新!",fg_bg=cpair(colors.red,colors._INHERIT)}
TextBox{parent=fac_c_10,y=11,height=3,text="两种模式都取决于 Mekanism 配置部分中的正确废料比率。",fg_bg=g_lg_fg_bg}
local function submit_sna_stats()
tmp_cfg.UseSNAStatistics = tool_ctl.sna_stats.get_value()
fac_pane.set_value(11)
end
PushButton{parent=fac_c_10,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(9)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_10,x=44,y=14,text="下一步 \x1a",callback=submit_sna_stats,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_11,height=3,text="标准设置要求废料处理（SNA 和 PRC）按机组进行，以便统计和单独管理钚备用。"}
TextBox{parent=fac_c_11,y=5,height=3,text="如果您的设置在处理前将多台机组的核废料合并，请在下方选择设施废料合并管理。"}
TextBox{parent=fac_c_11,y=9,text="两种选项都期望使用一个设施合并 SPS。",fg_bg=g_lg_fg_bg}
tool_ctl.com_waste = Checkbox{parent=fac_c_11,y=11,label="设施废料合并",default=ini_cfg.CombinedWaste,box_fg_bg=cpair(colors.yellow,colors.black)}
TextBox{parent=fac_c_11,x=27,y=11,text="新!",fg_bg=cpair(colors.red,colors._INHERIT)}
local function submit_com_waste()
tmp_cfg.CombinedWaste = tool_ctl.com_waste.get_value()
fac_pane.set_value(12)
end
PushButton{parent=fac_c_11,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(10)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_11,x=44,y=14,text="下一步 \x1a",callback=submit_com_waste,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
TextBox{parent=fac_c_12,height=2,text="请选择此设施使用的能量存储系统。"}
TextBox{parent=fac_c_12,y=4,text="能量存储系统 (ESS)"}
TextBox{parent=fac_c_12,x=29,y=4,text="新!",fg_bg=cpair(colors.red,colors._INHERIT)}
tool_ctl.ess_opt = RadioButton{parent=fac_c_12,y=5,default=math.max(1,ini_cfg.EnergyStorageSystem),options={"感应矩阵 (Mekanism)","能量核心 (Draconic Evolution)"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow}
local function submit_ess()
tmp_cfg.EnergyStorageSystem = tool_ctl.ess_opt.get_value()
main_pane.set_value(3)
end
TextBox{parent=fac_c_12,y=9,height=4,text="在大多数界面中，此设备将被称为能量存储系统或 ESS，而不是感应矩阵或能量核心，因此您应了解这些术语。",fg_bg=g_lg_fg_bg}
TextBox{parent=fac_c_12,x=11,y=10,width=21,height=1,text="能量存储系统",fg_bg=cpair(colors.blue,colors._INHERIT)}
TextBox{parent=fac_c_12,x=40,y=10,width=3,height=1,text="ESS",fg_bg=cpair(colors.blue,colors._INHERIT)}
PushButton{parent=fac_c_12,y=14,text="\x1b 返回",callback=function()fac_pane.set_value(11)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
PushButton{parent=fac_c_12,x=44,y=14,text="下一步 \x1a",callback=submit_ess,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
return fac_pane
end
return facility
