local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")

local tri = util.trinary

local cpair = core.cpair

local mekanism = {}

mekanism.ordered_keys = {
    { "energyPerFissionFuel", "fission_reactor", "energyPerFissionFuel" },
    { "turbineDisperserChemicalFlow", "turbine", "disperserChemicalFlow" },
    { "turbineVentChemicalFlow", "turbine", "ventChemicalFlow" },
    { "turbineChemicalPerTank", "turbine", "chemicalPerTank" }
}

mekanism.profiles = {
    {
        name = "Default",
        ---@class mekanism_configs
        fields = {
            energyPerFissionFuel         = 1000000,
            turbineDisperserChemicalFlow = 1280,
            turbineVentChemicalFlow      = 32000,
            turbineChemicalPerTank       = 64000
        }
    },
    {
        name = "ATM10",
        ---@type mekanism_configs
        fields = {
            energyPerFissionFuel         = 250000,
            turbineDisperserChemicalFlow = 1280,
            turbineVentChemicalFlow      = 43478.262,
            turbineChemicalPerTank       = 6400
        }
    },
    {
        name = "ATM10 To The Sky",
        ---@type mekanism_configs
        fields = {
            energyPerFissionFuel         = 2800000,
            turbineDisperserChemicalFlow = 1280,
            turbineVentChemicalFlow      = 43478.262,
            turbineChemicalPerTank       = 64000
        }
    }
}

local profile_names = {}

for _, p in ipairs(mekanism.profiles) do
    table.insert(profile_names, p.name)
end

table.insert(profile_names, "Custom")

-- create the mekanism configuration view
---@param tool_ctl _svr_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ svr_config, svr_config, svr_config, table, function ]
---@param mek_cfg Div
---@param style { [string]: cpair }
---@return MultiPane fac_pane
function mekanism.create(tool_ctl, main_pane, cfg_sys, mek_cfg, style)
    local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg

    --#region Mekanism Configuration

    local mek_c_1 = Div{parent=mek_cfg,x=2,y=4,width=49}
    local mek_c_2 = Div{parent=mek_cfg,x=2,y=4,width=49}
    local mek_c_3 = Div{parent=mek_cfg,x=2,y=4,width=49}

    local mek_pane = MultiPane{parent=mek_cfg,y=4,panes={mek_c_1,mek_c_2,mek_c_3}}

    TextBox{parent=mek_cfg,y=2,text=" Mekanism 配置",fg_bg=cpair(colors.white,colors.brown)}

    TextBox{parent=mek_c_1,y=1,height=3,text="为确保计算和行为正确，请选择您的 Mekanism 配置。在大多数情况下，您应使用默认配置。"}
    TextBox{parent=mek_c_1,y=5,height=3,text="如果您的整合包在列表中，请选择它。如果您或您的整合包作者手动更改了 Mekanism 设置，请选择自定义。"}

    local initial = #profile_names

    for i = 1, #profile_names do
        if profile_names[i] == ini_cfg.MekanismProfile then
            initial = i
            break
        end
    end

    TextBox{parent=mek_c_1,x=33,y=7,text="新!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    local profile = RadioButton{parent=mek_c_1,y=9,default=initial,options=profile_names,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.brown}

    local function submit_profile()
        tmp_cfg.MekanismProfile = profile_names[profile.get_value()] or "Custom"

        -- apply if not custom, otherwise go to the custom config page
        if profile.get_value() < #profile_names then
            tmp_cfg.MekanismConfig = mekanism.profiles[profile.get_value()].fields

            local is_atm10 = tmp_cfg.MekanismProfile == "ATM10"

            tmp_cfg.MekanismWasteToPu[1] = tri(is_atm10, 5, 10)
            tmp_cfg.MekanismWasteToPu[2] = 1
            tmp_cfg.MekanismWasteToPo[1] = tri(is_atm10, 5, 10)
            tmp_cfg.MekanismWasteToPo[2] = 1

            main_pane.set_value(4)
        else mek_pane.set_value(2) end
    end

    tool_ctl.mek_profile = profile

    PushButton{parent=mek_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_1,x=44,y=14,text="下一步 \x1a",callback=submit_profile,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=mek_c_2,y=1,height=4,text="对于自定义，请在您的服务器/世界中检查 config/Mekanism/generators.toml 并填写以下字段。此路径或配置名称可能因 Mekanism 版本而异（例如 gas 而非 chemical）。"}

    local last_section = ""

    for _, key in ipairs(mekanism.ordered_keys) do
        if key[2] ~= last_section then
            last_section = key[2]

            mek_c_2.line_break()
            TextBox{parent=mek_c_2,height=1,text="["..key[2].."]"}
        end

        local field = TextBox{parent=mek_c_2,height=1,text="  "..key[3].." ="}

        tool_ctl.custom_configs[key[1]] = NumberField{parent=mek_c_2,y=field.get_y(),x=string.len(key[3])+6,width=10,default=ini_cfg.MekanismConfig[key[1]],allow_decimal=true,fg_bg=bw_fg_bg}
        TextBox{parent=mek_c_2,x=string.len(key[3])+17,y=field.get_y(),text="新!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    end

    local cfg_err = TextBox{parent=mek_c_2,x=8,y=14,width=35,text="请填写所有字段。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_custom_profile()
        for _, key in ipairs(mekanism.ordered_keys) do
            local val = tonumber(tool_ctl.custom_configs[key[1]].get_value())

            if val ~= nil then
                tmp_cfg.MekanismConfig[key[1]] = val
            else
                cfg_err.show()
                return
            end
        end

        cfg_err.hide()
        mek_pane.set_value(3)
    end

    PushButton{parent=mek_c_2,y=14,text="\x1b 返回",callback=function()mek_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_2,x=44,y=14,text="下一步 \x1a",callback=submit_custom_profile,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=mek_c_3,y=1,height=3,text="某些整合包还会更改核废料与产品的比率。这些通常是 10:1，即 10mB 废料可制成 1mB 钚或钋。"}

    TextBox{parent=mek_c_3,y=5,text="核废料转钚        :"}
    tool_ctl.waste_ratios[1] = NumberField{parent=mek_c_3,y=5,x=28,width=4,default=ini_cfg.MekanismWasteToPu[1],min=1,max=99,allow_decimal=false,align_right=true,fg_bg=bw_fg_bg}
    tool_ctl.waste_ratios[2] = NumberField{parent=mek_c_3,y=5,x=33,width=4,default=ini_cfg.MekanismWasteToPu[2],min=1,max=99,allow_decimal=false,fg_bg=bw_fg_bg}
    TextBox{parent=mek_c_3,x=38,y=5,text="新!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    TextBox{parent=mek_c_3,y=6,text="核废料转钋        :"}
    tool_ctl.waste_ratios[3] = NumberField{parent=mek_c_3,y=6,x=28,width=4,default=ini_cfg.MekanismWasteToPo[1],min=1,max=99,allow_decimal=false,align_right=true,fg_bg=bw_fg_bg}
    tool_ctl.waste_ratios[4] = NumberField{parent=mek_c_3,y=6,x=33,width=4,default=ini_cfg.MekanismWasteToPo[2],min=1,max=99,allow_decimal=false,fg_bg=bw_fg_bg}
    TextBox{parent=mek_c_3,x=38,y=6,text="新!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    TextBox{parent=mek_c_3,y=8,height=2,text="提示：检查这些值最简单的方法是在 JEI 中查看它们的配方。",fg_bg=g_lg_fg_bg}

    local ratio_err = TextBox{parent=mek_c_3,x=8,y=14,width=35,text="请填写所有字段。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_waste_ratios()
        local values = {}

        for i = 1, #tool_ctl.waste_ratios do
            values[i] = tonumber(tool_ctl.waste_ratios[i].get_value())

            if values[i] == nil then
                ratio_err.show()
                return
            end
        end

        tmp_cfg.MekanismWasteToPu[1] = values[1]
        tmp_cfg.MekanismWasteToPu[2] = values[2]
        tmp_cfg.MekanismWasteToPo[1] = values[3]
        tmp_cfg.MekanismWasteToPo[2] = values[4]

        ratio_err.hide()
        main_pane.set_value(4)
    end

    PushButton{parent=mek_c_3,y=14,text="\x1b 返回",callback=function()mek_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_3,x=44,y=14,text="下一步 \x1a",callback=submit_waste_ratios,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    return mek_pane
end

return mekanism
