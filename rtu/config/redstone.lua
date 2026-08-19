local constants   = require("scada-common.constants")
local ppm         = require("scada-common.ppm")
local rsio        = require("scada-common.rsio")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local Radio2D     = require("graphics.elements.controls.Radio2D")

local NumberField = require("graphics.elements.form.NumberField")

---@class rtu_rs_definition
---@field unit integer|nil
---@field port IO_PORT
---@field relay string|nil
---@field side side
---@field color color|nil
---@field invert true|nil

local tri = util.trinary

local cpair = core.cpair

local IO = rsio.IO
local IO_LVL = rsio.IO_LVL
local IO_MODE = rsio.IO_MODE

local LEFT = core.ALIGN.LEFT

local self = {
    cur_phy = false,    ---@type string|nil|false
    cur_port = 1,       ---@type IO_PORT
    editing = false,    ---@type integer|false

    r_selection = nil,  ---@type TextBox
    r_unit_l = nil,     ---@type TextBox
    r_unit = nil,       ---@type NumberField
    r_side_l = nil,     ---@type TextBox
    r_bundled = nil,    ---@type Checkbox
    r_color = nil,      ---@type Radio2D
    r_inverted = nil,   ---@type Checkbox
    r_shortcut = nil,   ---@type TextBox
    r_advanced = nil,   ---@type PushButton

    r_whats_that = nil  ---@type PushButton
}

-- rsio port descriptions
local PORT_DESC_MAP = {
    { IO.F_SCRAM, "设施急停" },
    { IO.F_ACK, "设施确认" },
    { IO.U_ACK, "机组确认" },
    { IO.R_SCRAM, "反应堆急停" },
    { IO.R_RESET, "反应堆 RPS 复位" },
    { IO.R_ENABLE, "反应堆启用" },
    { IO.F_ALARM, "设施报警（高优先级）" },
    { IO.F_ALARM_ANY, "设施报警（任意）" },
    { IO.F_CHARGE_LOW, "能量存储 < " .. (100 * constants.RS_THRESHOLDS.ENERGY_CHARGE_LOW) .. "%" },
    { IO.F_CHARGE_HIGH, "能量存储 > " .. (100 * constants.RS_THRESHOLDS.ENERGY_CHARGE_HIGH) .. "%" },
    { IO.F_ENERGY_CHG, "能量存储充能百分比" },
    { IO.F_WASTE_PU, "组合废料 Pu 阀" },
    { IO.F_WASTE_PO, "组合废料 Po 阀" },
    { IO.F_WASTE_POPL, "组合废料 Po 颗粒阀" },
    { IO.F_WASTE_AM, "组合废料反物质阀" },
    { IO.U_ALARM, "机组报警" },
    { IO.U_EMER_COOL, "机组应急冷却阀" },
    { IO.U_AUX_COOL, "机组辅助冷却阀" },
    { IO.U_WASTE_PU, "机组废料钚阀" },
    { IO.U_WASTE_PO, "机组废料钋阀" },
    { IO.U_WASTE_POPL, "机组废料 Po 颗粒阀" },
    { IO.U_WASTE_AM, "机组废料反物质阀" },
    { IO.R_ACTIVE, "反应堆运行中" },
    { IO.R_AUTO_CTRL, "反应堆自动控制中" },
    { IO.R_SCRAMMED, "RPS 已跳闸" },
    { IO.R_AUTO_SCRAM, "RPS 自动急停" },
    { IO.R_HIGH_DMG, "RPS 高损坏" },
    { IO.R_HIGH_TEMP, "RPS 高温" },
    { IO.R_LOW_COOLANT, "RPS 冷却剂不足" },
    { IO.R_EXCESS_HC, "RPS 加热冷却剂过多" },
    { IO.R_EXCESS_WS, "RPS 废料过多" },
    { IO.R_INSUFF_FUEL, "RPS 燃料不足" },
    { IO.R_PLC_FAULT, "RPS PLC 故障" },
    { IO.R_PLC_TIMEOUT, "RPS 监管端超时" }
}

-- designation (0 = facility, 1 = unit)
local PORT_DSGN = { [-2] = 0, [-1] = 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0 }

assert(#PORT_DESC_MAP == rsio.NUM_PORTS)
assert(#PORT_DSGN == rsio.NUM_PORTS)

local side_options = { "顶部", "底部", "左侧", "右侧", "前侧", "后侧" }
local side_options_map = { "top", "bottom", "left", "right", "front", "back" }
local color_options = { "红色", "橙色", "黄色", "黄绿色", "绿色", "青色", "浅蓝色", "蓝色", "紫色", "品红色", "粉红色", "白色", "浅灰色", "灰色", "黑色", "棕色" }
local color_options_map = { colors.red, colors.orange, colors.yellow, colors.lime, colors.green, colors.cyan, colors.lightBlue, colors.blue, colors.purple, colors.magenta, colors.pink, colors.white, colors.lightGray, colors.gray, colors.black, colors.brown }

-- convert text representation to index
---@param side string
local function side_to_idx(side)
    for k, v in ipairs(side_options_map) do
        if v == side then return k end
    end
end

-- convert color to index
---@param color color
local function color_to_idx(color)
    for k, v in ipairs(color_options_map) do
        if v == color then return k end
    end
end

-- select the subset of redstone entries assigned to the given phy
---@param cfg rtu_rs_definition[] the full redstone entry list
---@param phy string|nil which phy to get redstone entries for
---@param invert boolean? true to get all except this phy
---@return rtu_rs_definition[]
local function redstone_subset(cfg, phy, invert)
    local subset = {}

    for i = 1, #cfg do
        if ((not invert) and cfg[i].relay == phy) or (invert and cfg[i].relay ~= phy) then
            table.insert(subset, cfg[i])
        end
    end

    return subset
end

local redstone = {}

-- validate a redstone entry
---@param def rtu_rs_definition
function redstone.validate(def)
    return tri(PORT_DSGN[def.port] == 1, util.is_int(def.unit) and def.unit > 0 and def.unit <= 4, def.unit == nil) and
           rsio.is_valid_port(def.port) and
           rsio.is_valid_side(def.side) and
           (def.color == nil or (rsio.is_digital(def.port) and rsio.is_color(def.color)))
end

-- create the redstone configuration view
---@param tool_ctl _rtu_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ rtu_config, rtu_config, rtu_config, table, function ]
---@param rs_cfg Div
---@param style { [string]: cpair }
---@return MultiPane rs_pane
function redstone.create(tool_ctl, main_pane, cfg_sys, rs_cfg, style)
    local settings_cfg, ini_cfg, tmp_cfg, _, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Redstone

    local rs_c_1  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_2  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_3  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_4  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_5  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_6  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_7  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_8  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_9  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_10 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_11 = Div{parent=rs_cfg,x=2,y=4,width=49}

    local rs_pane = MultiPane{parent=rs_cfg,y=4,panes={rs_c_1,rs_c_2,rs_c_3,rs_c_4,rs_c_5,rs_c_6,rs_c_7,rs_c_8,rs_c_9,rs_c_10,rs_c_11}}

    local header = TextBox{parent=rs_cfg,y=2,text=" Redstone Connections",fg_bg=cpair(colors.black,colors.red)}

    --#region Interface Selection

    TextBox{parent=rs_c_1,y=1,text="配置此计算机或红石继电器。"}
    local iface_list = ListBox{parent=rs_c_1,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    -- update relay interface list
    function tool_ctl.update_relay_list()
        local mounts = ppm.list_mounts()

        iface_list.remove_all()

        -- assemble list of configured relays
        local relays = {}
        for i = 1, #tmp_cfg.Redstone do
            local def = tmp_cfg.Redstone[i]
            if def.relay and not util.table_contains(relays, def.relay) then
                table.insert(relays, def.relay)
            end
        end

        -- add unconfigured connected relays
        for name, entry in pairs(mounts) do
            if entry.type == "redstone_relay" and not util.table_contains(relays, name) then
                table.insert(relays, name)
            end
        end

        local function config_rs(name)
            header.set_value(" 红石连接（" .. name .. "）")

            self.cur_phy = tri(name == "local", nil, name)

            tool_ctl.gen_rs_summary()
            rs_pane.set_value(2)
        end

        local line = Div{parent=iface_list,height=2,fg_bg=cpair(colors.black,colors.white)}
        TextBox{parent=line,y=1,text="@ local",fg_bg=cpair(colors.black,colors.white)}
        TextBox{parent=line,x=3,y=2,text="此计算机",fg_bg=cpair(colors.gray,colors.white)}
        local count = #redstone_subset(ini_cfg.Redstone, nil)
        TextBox{parent=line,x=33,y=2,width=16,alignment=core.ALIGN.RIGHT,text=count.." 条连接",fg_bg=cpair(colors.gray,colors.white)}

        PushButton{parent=line,x=41,y=1,min_width=8,height=1,text="配置",callback=function()config_rs("local")end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

        for i = 1, #relays do
            local name = relays[i]

            line = Div{parent=iface_list,height=2,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=line,y=1,text="@ "..name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=line,x=3,y=2,text="红石继电器",fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=line,x=18,y=2,text=tri(mounts[name],"在线","离线"),fg_bg=cpair(tri(mounts[name],colors.green,colors.red),colors.white)}
            count = #redstone_subset(ini_cfg.Redstone, name)
            TextBox{parent=line,x=33,y=2,width=16,alignment=core.ALIGN.RIGHT,text=count.." 条连接",fg_bg=cpair(colors.gray,colors.white)}

            PushButton{parent=line,x=41,y=1,min_width=8,height=1,text="配置",callback=function()config_rs(name)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
        end
    end

    tool_ctl.update_relay_list()

    PushButton{parent=rs_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=27,y=14,min_width=23,text="没有找到我的继电器！",callback=function()rs_pane.set_value(10)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Configuration List

    TextBox{parent=rs_c_2,y=1,text=" 端口           方向/颜色       机组/设施",fg_bg=g_lg_fg_bg}
    local rs_list = ListBox{parent=rs_c_2,y=2,height=11,width=49,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function rs_revert()
        tmp_cfg.Redstone = tool_ctl.deep_copy_rs(ini_cfg.Redstone)
        tool_ctl.gen_rs_summary()
    end

    local function rs_apply()
        -- add the changed data to the existing saved data
        local new_data = redstone_subset(tmp_cfg.Redstone, self.cur_phy)
        local new_save = redstone_subset(ini_cfg.Redstone, self.cur_phy, true)
        for i = 1, #new_data do table.insert(new_save, new_data[i]) end

        settings.set("Redstone", new_save)

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)
            rs_pane.set_value(5)

            -- for return to list from saved screen
            -- this will delete unsaved changes for other phy's, which is acceptable
            tmp_cfg.Redstone = tool_ctl.deep_copy_rs(ini_cfg.Redstone)
            tool_ctl.gen_rs_summary()
            tool_ctl.update_relay_list()
        else
            rs_pane.set_value(6)
        end
    end

    local function rs_back()
        self.cur_phy = false
        rs_pane.set_value(1)
        header.set_value(" Redstone Connections")
    end

    PushButton{parent=rs_c_2,y=14,text="\x1b 返回",callback=rs_back,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    local rs_revert_btn = PushButton{parent=rs_c_2,x=8,y=14,min_width=16,text="还原更改",callback=rs_revert,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=rs_c_2,x=35,y=14,min_width=7,text="新建 +",callback=function()rs_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    local rs_apply_btn = PushButton{parent=rs_c_2,x=43,y=14,min_width=7,text="应用",callback=rs_apply,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    --#endregion
    --#region Port Selection

    TextBox{parent=rs_c_3,y=1,text="请从下方选择一个要使用的端口。"}

    local rs_ports = ListBox{parent=rs_c_3,y=3,height=10,width=49,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function new_rs(port)
        self.editing = false

        local text

        if port == -1 or port == -2 then
            self.r_whats_that.hide(true)

            self.r_color.hide(true)
            self.r_shortcut.show()
            self.r_side_l.set_value("输出方向")
            self.r_bundled.enable()
            self.r_advanced.disable()

            text = "您选择了 ALL_" .. tri(port == -1, "U", "F") .. "_WASTE 快捷方式。"
        else
            self.r_whats_that.show()

            self.r_shortcut.hide(true)
            self.r_side_l.set_value(tri(rsio.get_io_dir(port) == rsio.IO_DIR.IN, "输入方向", "输出方向"))
            self.r_color.show()

            local io_type = "模拟输入 "
            local io_mode = rsio.get_io_mode(port)
            local inv = tri(rsio.digital_is_active(port, IO_LVL.LOW) == true, "反向 ", "")

            if rsio.is_analog(port) then
                self.r_bundled.set_value(false)
                self.r_bundled.disable()
                self.r_color.disable()
                self.r_inverted.set_value(false)
                self.r_advanced.disable()
            else
                self.r_bundled.enable()
                if self.r_bundled.get_value() then self.r_color.enable() else self.r_color.disable() end
                self.r_inverted.set_value(false)
                self.r_advanced.enable()
            end

            if io_mode == IO_MODE.DIGITAL_IN then
                io_type = inv .. "数字输入 "
            elseif io_mode == IO_MODE.DIGITAL_OUT then
                io_type = inv .. "数字输出 "
            elseif io_mode == IO_MODE.ANALOG_OUT then
                io_type = "模拟输出 "
            end

            text = "您选择了 " .. io_type .. rsio.to_string(port) .. "（用于" .. tri(PORT_DSGN[port] == 1, "机组）。", "设施）。")
        end

        if PORT_DSGN[port] == 1 then
            self.r_unit_l.show()
            self.r_unit.show()
        else
            self.r_unit_l.hide(true)
            self.r_unit.hide(true)
        end

        self.r_selection.set_value(text)
        self.cur_port = port
        rs_pane.set_value(4)
    end

    -- add entries to redstone option list
    local all_u_w_macro = Div{parent=rs_ports,height=1}
    PushButton{parent=all_u_w_macro,y=1,min_width=13,alignment=LEFT,height=1,text="ALL_U_WASTE",callback=function()new_rs(-1)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.black)}
    TextBox{parent=all_u_w_macro,x=15,y=1,width=5,text="n/a",fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=all_u_w_macro,x=19,y=1,text="全部 4 条机组废料条目",fg_bg=cpair(colors.gray,colors.white)}

    local all_f_w_macro = Div{parent=rs_ports,height=1}
    PushButton{parent=all_f_w_macro,y=1,min_width=13,alignment=LEFT,height=1,text="ALL_F_WASTE",callback=function()new_rs(-2)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.black)}
    TextBox{parent=all_f_w_macro,x=15,y=1,width=5,text="n/a",fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=all_f_w_macro,x=19,y=1,text="全部 4 条组合废料条目",fg_bg=cpair(colors.gray,colors.white)}

    for i = 1, rsio.NUM_PORTS do
        local p = PORT_DESC_MAP[i][1]
        local name = rsio.to_string(p)
        local io_dir = tri(rsio.get_io_dir(p) == rsio.IO_DIR.IN, "入", "出")
        local btn_color = tri(rsio.get_io_dir(p) == rsio.IO_DIR.IN, colors.yellow, colors.lightBlue)

        local entry = Div{parent=rs_ports,height=1}
        PushButton{parent=entry,y=1,min_width=13,alignment=LEFT,height=1,text=name,callback=function()new_rs(p)end,fg_bg=cpair(colors.black,btn_color),active_fg_bg=cpair(colors.white,colors.black)}
        TextBox{parent=entry,x=15,y=1,width=3,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
        TextBox{parent=entry,x=19,y=1,text=PORT_DESC_MAP[i][2],fg_bg=cpair(colors.gray,colors.white)}
    end

    PushButton{parent=rs_c_3,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_3,x=30,y=14,min_width=20,text="U_WASTE 与 F_WASTE",callback=function()rs_pane.set_value(11)end,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Port Configuration

    self.r_selection = TextBox{parent=rs_c_4,y=1,height=2,text=""}

    self.r_whats_that = PushButton{parent=rs_c_4,x=36,y=3,text="这是什么？",min_width=14,callback=function()rs_pane.set_value(8)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    self.r_side_l = TextBox{parent=rs_c_4,y=4,width=11,text="输出方向"}
    local side = Radio2D{parent=rs_c_4,y=5,rows=1,columns=6,default=1,options=side_options,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.red}

    self.r_unit_l = TextBox{parent=rs_c_4,x=25,y=7,width=7,text="机组 ID"}
    self.r_unit = NumberField{parent=rs_c_4,x=33,y=7,width=10,max_chars=2,min=1,max=4,fg_bg=bw_fg_bg}

    local function set_bundled(bundled)
        if bundled then self.r_color.enable() else self.r_color.disable() end
    end

    self.r_shortcut = TextBox{parent=rs_c_4,y=9,height=4,text="此快捷方式将为 4 个废料输出各添加一条条目。如果选择束线，将向所选方向分配 4 种颜色。否则将使用 4 个默认方向。"}
    self.r_shortcut.hide(true)

    self.r_bundled = Checkbox{parent=rs_c_4,y=7,label="是否束线？",default=false,box_fg_bg=cpair(colors.red,colors.black),callback=set_bundled,disable_fg_bg=g_lg_fg_bg}
    self.r_color = Radio2D{parent=rs_c_4,y=9,rows=4,columns=4,default=1,options=color_options,radio_colors=cpair(colors.lightGray,colors.black),color_map=color_options_map,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    self.r_color.disable()

    local rs_err = TextBox{parent=rs_c_4,x=8,y=14,width=30,text="机组 ID 无效。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    rs_err.hide(true)

    local function back_from_rs_opts()
        rs_err.hide(true)
        if self.editing ~= false then rs_pane.set_value(2) else rs_pane.set_value(3) end
    end

    local function save_rs_entry()
        assert(self.cur_phy ~= false, "tried to save a redstone entry without a phy")

        local port = self.cur_port
        local u = tonumber(self.r_unit.get_value())

        if PORT_DSGN[port] == 0 or (util.is_int(u) and u > 0 and u < 5) then
            rs_err.hide(true)

            if port >= 0 then
                ---@type rtu_rs_definition
                local def = {
                    unit = tri(PORT_DSGN[port] == 1, u, nil),
                    port = port,
                    relay = self.cur_phy,
                    side = side_options_map[side.get_value()],
                    color = tri(self.r_bundled.get_value() and rsio.is_digital(port), color_options_map[self.r_color.get_value()], nil),
                    invert = self.r_inverted.get_value() or nil
                }

                if self.editing == false then
                    -- check for duplicate inputs for this unit/facility
                    if (rsio.get_io_dir(port) == rsio.IO_DIR.IN) then
                        for i = 1, #tmp_cfg.Redstone do
                            if tmp_cfg.Redstone[i].port == port and tmp_cfg.Redstone[i].unit == def.unit then
                                rs_pane.set_value(7)
                                return
                            end
                        end
                    end

                    table.insert(tmp_cfg.Redstone, def)
                else
                    def.port = tmp_cfg.Redstone[self.editing].port
                    tmp_cfg.Redstone[self.editing] = def
                end
            elseif port == -1 or port == -2 then
                local default_sides = { "left", "back", "right", "front" }
                local default_colors = { colors.red, colors.orange, colors.yellow, colors.lime }
                local base_port = tri(port == -1, IO.U_WASTE_PU, IO.F_WASTE_PU)

                for i = 0, 3 do
                    table.insert(tmp_cfg.Redstone, {
                        unit = tri(PORT_DSGN[base_port + i] == 1, u, nil),
                        port = base_port + i,
                        relay = self.cur_phy,
                        side = tri(self.r_bundled.get_value(), side_options_map[side.get_value()], default_sides[i + 1]),
                        color = tri(self.r_bundled.get_value(), default_colors[i + 1], nil)
                    })
                end
            end

            rs_pane.set_value(2)
            tool_ctl.gen_rs_summary()

            side.set_value(1)
            self.r_bundled.set_value(false)
            self.r_color.set_value(1)
            self.r_color.disable()
            self.r_inverted.set_value(false)
            self.r_advanced.disable()
        else rs_err.show() end
    end

    PushButton{parent=rs_c_4,y=14,text="\x1b 返回",callback=back_from_rs_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.r_advanced = PushButton{parent=rs_c_4,x=30,y=14,min_width=10,text="高级",callback=function()rs_pane.set_value(9)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=rs_c_4,x=41,y=14,min_width=9,text="确定",callback=save_rs_entry,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}

    --#endregion

    TextBox{parent=rs_c_5,y=1,text="设置已保存！"}
    PushButton{parent=rs_c_5,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_5,x=44,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_6,y=1,height=5,text="保存设置文件失败。\n\n可能是存储空间不足，或服务器文件权限禁止写入。"}
    PushButton{parent=rs_c_6,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_6,x=44,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_7,y=1,height=6,text="您已为此设施/机组分配配置了该输入。每个机组或设施（对于设施输入）的每个输入只能有一条条目。\n\n请选择其他端口。"}
    PushButton{parent=rs_c_7,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_8,y=1,height=4,text="（正常）数字输入：有红石信号时为开，否则为关\n反向数字输入：无红石信号时为开，否则为关"}
    TextBox{parent=rs_c_8,y=6,height=4,text="（正常）数字输出：有红石信号则“开启”，无信号则“关闭”\n反向数字输出：无红石信号则“开启”，有信号则“关闭”"}
    TextBox{parent=rs_c_8,y=11,height=2,text="模拟输入：0-15 级红石能量输入\n模拟输出：0-15 级缩放红石能量输出"}
    PushButton{parent=rs_c_8,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_9,y=1,height=5,text="高级选项"}
    self.r_inverted = Checkbox{parent=rs_c_9,y=3,label="反转",default=false,box_fg_bg=cpair(colors.red,colors.black),disable_fg_bg=g_lg_fg_bg}
    TextBox{parent=rs_c_9,x=3,y=4,height=4,text="数字输入/输出已根据预期用途决定是否反向。如果您的设置非常规，可使用此选项以避免需要红石反相器。",fg_bg=cpair(colors.gray,colors.lightGray)}
    PushButton{parent=rs_c_9,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_10,y=1,height=10,text="请确保您的继电器与 RTU 网关直接接触，或通过有线调制解调器连接。RTU 网关的一侧应装有有线调制解调器，设备上也应装有一个，二者用线缆相连。设备上的调制解调器需要右键点击以进行连接（其边框会变为红色），此时外设名称会显示在聊天栏中。"}
    PushButton{parent=rs_c_10,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_11,y=1,height=10,text="机组废料（U_WASTE_）和组合设施废料（F_WASTE_）两种红石输出均可用。\n\n如果在监管端选择了组合设施废料，则仅支持 F_WASTE_ 输出。否则，您应只使用 U_WASTE_ 输出。\n\n不匹配的输出将被忽略并显示为未连接。"}
    PushButton{parent=rs_c_11,y=14,text="\x1b 返回",callback=function()rs_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Tool Functions

    local function edit_rs_entry(idx)
        local def = tmp_cfg.Redstone[idx]

        self.r_shortcut.hide(true)
        self.r_color.show()

        self.cur_port = def.port
        self.editing = idx

        local text = "正在编辑 " .. rsio.to_string(def.port) .. "（用于"
        if PORT_DSGN[def.port] == 1 then
            text = text .. "机组）。"
            self.r_unit_l.show()
            self.r_unit.show()
            self.r_unit.set_value(def.unit or 1)
        else
            self.r_unit_l.hide(true)
            self.r_unit.hide(true)
            text = text .. "设施）。"
        end

        if rsio.is_analog(def.port) then
            self.r_bundled.set_value(false)
            self.r_bundled.disable()
            self.r_advanced.disable()
        else
            self.r_bundled.enable()
            self.r_bundled.set_value(def.color ~= nil)
            self.r_advanced.enable()
        end

        local value = 1
        if def.color ~= nil then
            value = color_to_idx(def.color)
            self.r_color.enable()
        else
            self.r_color.disable()
        end

        self.r_selection.set_value(text)
        self.r_side_l.set_value(tri(rsio.get_io_dir(def.port) == rsio.IO_DIR.IN, "输入方向", "输出方向"))
        side.set_value(side_to_idx(def.side))
        self.r_color.set_value(value)
        self.r_inverted.set_value(def.invert or false)
        rs_pane.set_value(4)
    end

    local function delete_rs_entry(idx)
        table.remove(tmp_cfg.Redstone, idx)
        tool_ctl.gen_rs_summary()
    end

    -- generate the redstone summary list
    function tool_ctl.gen_rs_summary()
        assert(self.cur_phy ~= false, "tried to generate a summary without a phy set")

        rs_list.remove_all()

        local ini = redstone_subset(ini_cfg.Redstone, self.cur_phy)
        local tmp = redstone_subset(tmp_cfg.Redstone, self.cur_phy)

        local modified = #ini ~= #tmp

        for i = 1, #tmp_cfg.Redstone do
            local def = tmp_cfg.Redstone[i]

            if def.relay == self.cur_phy then
                local name = rsio.to_string(def.port)
                local io_dir = tri(rsio.get_io_dir(def.port) == rsio.IO_DIR.IN, "\x1a", "\x1b")
                local io_c = tri(rsio.is_digital(def.port), colors.blue, colors.purple)
                local conn = def.side
                local unit = util.strval(def.unit or "F")

                if def.color ~= nil then conn = def.side .. "/" .. rsio.color_name(def.color) end

                local entry = Div{parent=rs_list,height=1}
                TextBox{parent=entry,y=1,width=1,text=io_dir,fg_bg=cpair(tri(def.invert,colors.orange,io_c),colors.white)}
                TextBox{parent=entry,x=2,y=1,width=14,text=name}
                TextBox{parent=entry,x=16,y=1,width=string.len(conn),text=conn,fg_bg=cpair(colors.gray,colors.white)}
                TextBox{parent=entry,x=33,y=1,width=1,text=unit,fg_bg=cpair(colors.gray,colors.white)}
                PushButton{parent=entry,x=35,y=1,min_width=6,height=1,text="编辑",callback=function()edit_rs_entry(i)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
                PushButton{parent=entry,x=41,y=1,min_width=8,height=1,text="删除",callback=function()delete_rs_entry(i)end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}

                if not modified then
                    local a = ini_cfg.Redstone[i]
                    local b = tmp_cfg.Redstone[i]

                    modified = (a.unit ~= b.unit) or (a.port ~= b.port) or (a.relay ~= b.relay) or (a.side ~= b.side) or (a.color ~= b.color) or (a.invert ~= b.invert)
                end
            end
        end

        if modified then
            rs_revert_btn.enable()
            rs_apply_btn.enable()
        else
            rs_revert_btn.disable()
            rs_apply_btn.disable()
        end
    end

    --#endregion

    return rs_pane
end

return redstone
