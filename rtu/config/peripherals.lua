local ppm         = require("scada-common.ppm")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")
local Radio2D     = require("graphics.elements.controls.Radio2D")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")
local TextField   = require("graphics.elements.form.TextField")

---@class rtu_peri_definition
---@field unit integer|nil
---@field index integer|nil
---@field name string

local tri = util.trinary

local cpair = core.cpair

local ALIGN = core.ALIGN

local self = {
    peri_cfg_editing = false, ---@type integer|false

    p_assign = nil,   ---@type function

    ppm_devs = nil,   ---@type ListBox
    p_name_msg = nil, ---@type TextBox
    p_prompt = nil,   ---@type TextBox
    p_idx = nil,      ---@type NumberField
    p_unit = nil,     ---@type NumberField
    p_desc = nil,     ---@type TextBox
    p_fac_warn = nil, ---@type TextBox
    p_err = nil       ---@type TextBox
}

local peripherals = {}

local RTU_DEV_TYPES = { "solarNeutronActivator", "largeSolarNeutronActivator", "environmentDetector", "environment_detector", "reinforcedInductionPort", "draconic_rf_storage", "boilerValve", "turbineValve", "dynamicValve", "inductionPort", "spsPort" }
local NEEDS_UNIT = { "boilerValve", "turbineValve", "dynamicValve", "solarNeutronActivator", "largeSolarNeutronActivator", "environmentDetector", "environment_detector" }
local UNIT_OR_FACILITY = { "dynamicValve", "solarNeutronActivator", "largeSolarNeutronActivator", "environmentDetector", "environment_detector" }

-- create the peripherals configuration view
---@param tool_ctl _rtu_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ rtu_config, rtu_config, rtu_config, table, function ]
---@param peri_cfg Div
---@param style { [string]: cpair }
---@return MultiPane peri_pane, string[] NEEDS_UNIT
function peripherals.create(tool_ctl, main_pane, cfg_sys, peri_cfg, style)
    local settings_cfg, ini_cfg, tmp_cfg, _, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Peripherals

    local peri_c_1 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_2 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_3 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_4 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_5 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_6 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_7 = Div{parent=peri_cfg,x=2,y=4,width=49}

    local peri_pane = MultiPane{parent=peri_cfg,y=4,panes={peri_c_1,peri_c_2,peri_c_3,peri_c_4,peri_c_5,peri_c_6,peri_c_7}}

    TextBox{parent=peri_cfg,y=2,text=" 外设连接",fg_bg=cpair(colors.black,colors.purple)}

    local peri_list = ListBox{parent=peri_c_1,y=1,height=12,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function peri_revert()
        tmp_cfg.Peripherals = tool_ctl.deep_copy_peri(ini_cfg.Peripherals)
        tool_ctl.gen_peri_summary()
    end

    local function peri_apply()
        settings.set("Peripherals", tmp_cfg.Peripherals)

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)
            peri_pane.set_value(5)

            -- for return to list from saved screen
            tmp_cfg.Peripherals = tool_ctl.deep_copy_peri(ini_cfg.Peripherals)
            tool_ctl.gen_peri_summary()
        else
            peri_pane.set_value(6)
        end
    end

    PushButton{parent=peri_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    local peri_revert_btn = PushButton{parent=peri_c_1,x=8,y=14,min_width=16,text="还原更改",callback=peri_revert,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=peri_c_1,x=35,y=14,min_width=7,text="添加 +",callback=function()peri_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    local peri_apply_btn = PushButton{parent=peri_c_1,x=43,y=14,min_width=7,text="应用",callback=peri_apply,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    TextBox{parent=peri_c_2,y=1,text="请从下方选择一个要使用的设备。"}

    self.ppm_devs = ListBox{parent=peri_c_2,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=peri_c_2,y=14,text="\x1b 返回",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_2,x=8,y=14,min_width=10,text="手动 +",callback=function()peri_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_2,x=26,y=14,min_width=24,text="没有找到我的设备！",callback=function()peri_pane.set_value(7)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_7,y=1,height=10,text="请确保您的设备与 RTU 直接接触，或通过有线调制解调器连接。RTU 的一侧应装有有线调制解调器，设备上也应装有一个，二者用线缆相连。设备上的调制解调器需要右键点击以进行连接（其边框会变为红色），此时外设名称会显示在聊天栏中。"}
    TextBox{parent=peri_c_7,y=9,height=4,text="如果仍未显示，则可能不受支持。目前仅支持锅炉、涡轮机、动态储罐、SNA、SPS、感应矩阵和环境探测器。"}
    PushButton{parent=peri_c_7,y=14,text="\x1b 返回",callback=function()peri_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local new_peri_attrs = { "", "" }
    local function new_peri(name, type)
        new_peri_attrs = { name, type }
        self.peri_cfg_editing = false

        self.p_err.hide(true)
        self.p_name_msg.set_value("正在配置外设 '" .. name .. "':")

        self.p_fac_warn.hide(true)

        local function reposition(prompt, idx_x, idx_max, unit_x, unit_y, desc_y)
            self.p_prompt.set_value(prompt)

            self.p_idx.reposition(idx_x, 4)
            self.p_idx.enable()
            self.p_idx.set_max(idx_max)
            self.p_idx.show()

            self.p_unit.reposition(unit_x, unit_y)
            self.p_unit.enable()
            self.p_unit.show()

            self.p_desc.hide(true)
            self.p_desc.reposition(1, desc_y)
            self.p_desc.show()
        end

        if type == "boilerValve" then
            reposition("这是反应堆机组 #                 的 #    锅炉。", 31, 2, 23, 4, 7)
            self.p_assign_btn.hide(true)
            self.p_desc.set_value("每个机组最多可有 2 台锅炉。锅炉 #1 会先显示在主界面上，锅炉 #2 显示在其下方。编号按机组计算（若机组 1 和机组 2 各有一台锅炉，则它们都叫锅炉 #1），并且可以分散到多个 RTU（一个用 #1，另一个用 #2）。")
        elseif type == "turbineValve" then
            reposition("这是反应堆机组 #                 的 #    涡轮机。", 31, 3, 23, 4, 7)
            self.p_assign_btn.hide(true)
            self.p_desc.set_value("每个机组最多可有 3 台涡轮机。涡轮机 #1 会先显示在主界面上，#2 和 #3 依次显示在其下方。编号按机组计算（若机组 1 和机组 2 各有一台涡轮机，则它们都叫涡轮机 #1），并且可以分散到多个 RTU（一个用 #1，另一个用 #2）。")
        elseif type == "solarNeutronActivator" or type == "largeSolarNeutronActivator" then
            reposition("此 SNA 用于以下系统。", 1, 1, 17, 6, 8)
            self.p_idx.hide(true)

            self.p_assign_btn.show()
            self.p_assign_btn.redraw()

            if self.p_assign_btn.get_value() == 1 then
                self.p_fac_warn.show()
            else self.p_fac_warn.hide(true) end

            self.p_desc.set_value("设备过多（例如 SNA 过多）会导致卡顿。晴朗天气下，流量监视器上的 \"\x1aMAX\" 速率显示 SNA 可处理的最大废料量。提供该机组最大燃烧速率 2 至 3 倍的 SNA 数量，应足以在夜晚或阴天后赶上进度。")
        elseif type == "dynamicValve" then
            reposition("这是以下系统的 #                    动态储罐。", 29, 4, 17, 6, 8)
            self.p_assign_btn.show()
            self.p_assign_btn.redraw()

            if self.p_assign_btn.get_value() == 1 then
                self.p_idx.enable()
                self.p_unit.disable()
            else
                self.p_idx.set_value(1)
                self.p_idx.disable()
                self.p_unit.enable()
            end

            self.p_desc.set_value("每个反应堆机组最多可有 1 个储罐，设施最多可有 4 个。每个设施储罐必须有唯一的编号 1 至 4，无论连接在哪里。流量监视器上总共只能显示 4 个储罐。")
        elseif type == "environmentDetector" or type == "environment_detector" then
            reposition("这是以下系统的 #                    环境探测器。", 29, 99, 17, 6, 8)
            self.p_assign_btn.show()
            self.p_assign_btn.redraw()
            if self.p_assign_btn.get_value() == 1 then self.p_unit.disable() else self.p_unit.enable() end
            self.p_desc.set_value("您可以为特定机组或设施连接多个环境探测器。在这种情况下，分配给该机组或设施的探测器中的最大辐射读数将用于报警和显示。")
        elseif type == "inductionPort" or type == "reinforcedInductionPort" or type == "spsPort" or type == "draconic_rf_storage" then
            self.p_idx.hide(true)
            self.p_unit.hide(true)
            self.p_assign_btn.hide(true)

            self.p_desc.hide(true)
            self.p_desc.reposition(1, 7)
            self.p_desc.show()

            if type == "spsPort" then
                self.p_prompt.set_value("这是用于设施的 SPS。")
                self.p_desc.set_value("每个 SCADA 网络只能有一个 SPS，因此它将被指定为设施的唯一个 SPS。您所有的 RTU 中只能有一个 SPS。")
            else
                self.p_prompt.set_value(tri(type == "draconic_rf_storage", "这是用于设施的能源核心。", "这是用于设施的感应矩阵。"))
                self.p_desc.set_value("每个 SCADA 网络只能有一个能量存储系统，因此它将被指定为设施的唯一个。您所有的 RTU 中只能有一个感应矩阵或一个能源核心。")
            end
        else
            assert(false, "invalid peripheral type after type validation")
        end

        peri_pane.set_value(4)
    end

    -- update peripherals list
    function tool_ctl.update_peri_list()
        local alternate = true
        local mounts = ppm.list_mounts()

        -- filter out in-use peripherals
        for _, v in ipairs(tmp_cfg.Peripherals) do mounts[v.name] = nil end

        self.ppm_devs.remove_all()
        for name, entry in pairs(mounts) do
            if util.table_contains(RTU_DEV_TYPES, entry.type) then
                local bkg = tri(alternate, colors.white, colors.lightGray)

                ---@cast entry ppm_entry
                local line = Div{parent=self.ppm_devs,height=2,fg_bg=cpair(colors.black,bkg)}
                PushButton{parent=line,y=1,min_width=9,alignment=ALIGN.LEFT,height=1,text="> 选择",callback=function()new_peri(name,entry.type)end,fg_bg=cpair(colors.black,colors.purple),active_fg_bg=cpair(colors.white,colors.black)}
                TextBox{parent=line,x=11,y=1,text=name,fg_bg=cpair(colors.black,bkg)}
                TextBox{parent=line,x=11,y=2,text=entry.type,fg_bg=cpair(colors.gray,bkg)}

                alternate = not alternate
            end
        end
    end

    tool_ctl.update_peri_list()

    TextBox{parent=peri_c_3,y=1,height=2,text="此选项面向高级用户。如果未找到您的设备，请点击“没有找到我的设备！”。"}
    TextBox{parent=peri_c_3,y=4,height=4,text="外设名称"}
    local p_name = TextField{parent=peri_c_3,y=5,width=49,height=1,max_len=128,fg_bg=bw_fg_bg}
    local p_type = Radio2D{parent=peri_c_3,y=7,rows=6,columns=2,default=1,options=RTU_DEV_TYPES,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.purple}
    local man_p_err = TextBox{parent=peri_c_3,x=8,y=14,width=35,text="请输入外设名称。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    man_p_err.hide(true)

    local function submit_manual_peri()
        local name = p_name.get_value()
        if string.len(name) > 0 then
            tool_ctl.entering_manual = true
            man_p_err.hide(true)
            new_peri(name, RTU_DEV_TYPES[p_type.get_value()])
        else man_p_err.show() end
    end

    PushButton{parent=peri_c_3,y=14,text="\x1b 返回",callback=function()peri_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_3,x=44,y=14,text="下一步 \x1a",callback=submit_manual_peri,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    self.p_name_msg = TextBox{parent=peri_c_4,y=1,height=2,text=""}
    self.p_prompt = TextBox{parent=peri_c_4,y=4,height=2,text=""}
    self.p_idx = NumberField{parent=peri_c_4,x=31,y=4,width=4,max_chars=2,min=1,max=2,default=1,fg_bg=bw_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    self.p_assign_btn = RadioButton{parent=peri_c_4,y=5,default=1,options={"设施","反应堆机组 #"},callback=function(v)self.p_assign(v)end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.purple}
    self.p_fac_warn = TextBox{parent=peri_c_4,y=5,x=22,height=2,alignment=ALIGN.CENTER,text="需要监管端选择“组合设施废料”",fg_bg=cpair(colors.red,colors._INHERIT),hidden=true}

    self.p_unit = NumberField{parent=peri_c_4,x=23,y=4,width=4,max_chars=2,min=1,max=4,default=1,fg_bg=bw_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    self.p_unit.disable()

    function self.p_assign(opt)
        if opt == 1 then
            self.p_unit.disable()
            if new_peri_attrs[2] == "dynamicValve" then
                self.p_idx.enable()
            elseif new_peri_attrs[2] == "solarNeutronActivator" or new_peri_attrs[2] == "largeSolarNeutronActivator" then
                self.p_fac_warn.show()
            end
        else
            self.p_unit.enable()
            if new_peri_attrs[2] == "dynamicValve" then
                self.p_idx.set_value(1)
                self.p_idx.disable()
            elseif new_peri_attrs[2] == "solarNeutronActivator" or new_peri_attrs[2] == "largeSolarNeutronActivator" then
                self.p_fac_warn.hide(true)
            end
        end
    end

    self.p_desc = TextBox{parent=peri_c_4,y=7,height=6,text="",fg_bg=g_lg_fg_bg}

    self.p_err = TextBox{parent=peri_c_4,x=8,y=14,width=32,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    self.p_err.hide(true)

    local function back_from_peri_opts()
        if self.peri_cfg_editing ~= false then
            peri_pane.set_value(1)
        elseif tool_ctl.entering_manual then
            peri_pane.set_value(3)
        else
            peri_pane.set_value(2)
        end

        tool_ctl.entering_manual = false
    end

    local function save_peri_entry()
        local peri_name = new_peri_attrs[1]
        local peri_type = new_peri_attrs[2]

        local unit, index = nil, nil

        local for_facility = self.p_assign_btn.get_value() == 1
        local u = tonumber(self.p_unit.get_value())
        local idx = tonumber(self.p_idx.get_value())

        if util.table_contains(NEEDS_UNIT, peri_type) then
            if util.table_contains(UNIT_OR_FACILITY, peri_type) and for_facility then
                -- skip
            elseif not (util.is_int(u) and u > 0 and u < 5) then
                self.p_err.set_value("机组 ID 必须在 1 到 4 之间。")
                self.p_err.show()
                return
            else unit = u end
        end

        if peri_type == "boilerValve" then
            if not (idx == 1 or idx == 2) then
                self.p_err.set_value("编号必须为 1 或 2。")
                self.p_err.show()
                return
            else index = idx end
        elseif peri_type == "turbineValve" then
            if not (idx == 1 or idx == 2 or idx == 3) then
                self.p_err.set_value("编号必须为 1、2 或 3。")
                self.p_err.show()
                return
            else index = idx end
        elseif peri_type == "dynamicValve" and for_facility then
            if not (util.is_int(idx) and idx > 0 and idx < 5) then
                self.p_err.set_value("编号必须在 1 到 4 之间。")
                self.p_err.show()
                return
            else index = idx end
        elseif peri_type == "dynamicValve" then
            index = 1
        elseif peri_type == "environmentDetector" or peri_type == "environment_detector" then
            if not (util.is_int(idx) and idx > 0) then
                self.p_err.set_value("编号必须大于 0。")
                self.p_err.show()
                return
            else index = idx end
        end

        self.p_err.hide(true)

        ---@type rtu_peri_definition
        local def = { name = peri_name, unit = unit, index = index }

        if self.peri_cfg_editing == false then
            table.insert(tmp_cfg.Peripherals, def)
        else
            def.name = tmp_cfg.Peripherals[self.peri_cfg_editing].name
            tmp_cfg.Peripherals[self.peri_cfg_editing] = def
        end

        peri_pane.set_value(1)
        tool_ctl.gen_peri_summary()
        tool_ctl.update_peri_list()

        self.p_idx.set_value(1)
    end

    PushButton{parent=peri_c_4,y=14,text="\x1b 返回",callback=back_from_peri_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_4,x=41,y=14,min_width=9,text="确定",callback=save_peri_entry,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_5,y=1,text="设置已保存！"}
    PushButton{parent=peri_c_5,y=14,text="\x1b 返回",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_5,x=44,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_6,y=1,height=5,text="保存设置文件失败。\n\n可能是存储空间不足，或服务器文件权限禁止写入。"}
    PushButton{parent=peri_c_6,y=14,text="\x1b 返回",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_6,x=44,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Tool Functions

    ---@param def rtu_peri_definition
    ---@param idx integer
    ---@param type string
    local function edit_peri_entry(idx, def, type)
        -- set inputs BEFORE calling new_peri()
        if def.index ~= nil then self.p_idx.set_value(def.index) end
        if def.unit == nil then
            self.p_assign_btn.set_value(1)
        else
            self.p_unit.set_value(def.unit)
            self.p_assign_btn.set_value(2)
        end

        new_peri(def.name, type)

        -- set editing mode AFTER new_peri()
        self.peri_cfg_editing = idx
    end

    local function delete_peri_entry(idx)
        table.remove(tmp_cfg.Peripherals, idx)
        tool_ctl.gen_peri_summary()
        tool_ctl.update_peri_list()
    end

    -- generate the peripherals summary list
    function tool_ctl.gen_peri_summary()
        peri_list.remove_all()

        local modified = #ini_cfg.Peripherals ~= #tmp_cfg.Peripherals

        for i = 1, #tmp_cfg.Peripherals do
            local def = tmp_cfg.Peripherals[i]

            local t = ppm.get_type(def.name)
            local t_str = "<未连接>（连接后可编辑）"
            local disconnected = t == nil

            if not disconnected then t_str = "[" .. t .. "]" end

            local desc = "  \x1a "

            if type(def.index) == "number" then
                desc = desc .. "#" .. def.index .. " "
            end

            if type(def.unit) == "number" then
                desc = desc .. "用于机组 " .. def.unit
            else
                desc = desc .. "用于设施"
            end

            local entry = Div{parent=peri_list,height=3}
            TextBox{parent=entry,y=1,text="@ "..def.name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=entry,y=2,text="  \x1a "..t_str,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=entry,y=3,text=desc,fg_bg=cpair(colors.gray,colors.white)}
            local edit_btn = PushButton{parent=entry,x=41,y=2,min_width=8,height=1,text="编辑",callback=function()edit_peri_entry(i,def,t or "")end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
            PushButton{parent=entry,x=41,y=3,min_width=8,height=1,text="删除",callback=function()delete_peri_entry(i)end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}

            if disconnected then edit_btn.disable() end

            if not modified then
                local a = ini_cfg.Peripherals[i]
                local b = tmp_cfg.Peripherals[i]

                modified = (a.unit ~= b.unit) or (a.index ~= b.index) or (a.name ~= b.name)
            end
        end

        if modified then
            peri_revert_btn.enable()
            peri_apply_btn.enable()
        else
            peri_revert_btn.disable()
            peri_apply_btn.disable()
        end
    end

    --#endregion

    return peri_pane, NEEDS_UNIT
end

return peripherals
