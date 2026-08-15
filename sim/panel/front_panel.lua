--
-- SCADA Simulator Front Panel GUI
--
-- Three-tab panel: STATUS (live reactor/boiler/turbine/ESS/SPS data),
-- CONTROL (burn rate setpoint, SCRAM/start, parameter tweaks), and LOG
-- (rolling log viewer). Uses the same graphics library as all other SCADA
-- applications.
--

local util = require("scada-common.util")

local databus = require("sim.databus")

local style = require("sim.panel.style")

local core = require("graphics.core")

local Div = require("graphics.elements.Div")
local Rectangle = require("graphics.elements.Rectangle")
local TextBox = require("graphics.elements.TextBox")
local MultiPane = require("graphics.elements.MultiPane")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local LED = require("graphics.elements.indicators.LED")
local RGBLED = require("graphics.elements.indicators.RGBLED")
local HorizontalBar = require("graphics.elements.indicators.HorizontalBar")

local PushButton = require("graphics.elements.controls.PushButton")
local TabBar = require("graphics.elements.controls.TabBar")

local ALIGN = core.ALIGN

local border = core.border

local PANEL_LINK_STATE = require("scada-common.types").PANEL_LINK_STATE

local ind_grn = style.ind_grn

-- create the front panel view
---@param panel DisplayBox main displaybox
---@param config sim_config simulator configuration
---@param control table control callbacks { set_burn, scram, activate, set_param }
local function init(panel, config, control) -- luacheck: ignore config
    local theme = style.theme
    local fp = style.fp

    local term_w, term_h = term.getSize()

    -- header
    TextBox{parent=panel,y=1,text="SCADA SIMULATOR",alignment=ALIGN.CENTER,fg_bg=theme.header}

    --
    -- tab bar + multi-pane
    --

    -- forward-declare the multi-pane so the tab bar callback can reference it
    local pane ---@type MultiPane

    local tabs = {
        { name = "STATUS", color = theme.highlight_box },
        { name = "CONTROL", color = theme.highlight_box },
        { name = "LOG", color = theme.highlight_box }
    }

    local tab_bar = TabBar{parent=panel,y=2,tabs=tabs,width=term_w-4,x=2,fg_bg=theme.highlight_box,
        callback=function (tab) pane.set_value(tab) end}

    pane = MultiPane{parent=panel,y=4,width=term_w-2,x=1,height=term_h-6,panes={}}

    --#region STATUS Pane

    local status_pane = Div{parent=pane,width=term_w-2,height=term_h-6}

    local reactor_box = Rectangle{parent=status_pane,x=1,y=1,width=math.floor((term_w-4)/2),height=9,border=border(1,theme.highlight_box.bkg,true),even_inner=true}

    local r_active = LED{parent=reactor_box,label="ACTIVE",colors=ind_grn}
    local r_trip = RGBLED{parent=reactor_box,label="TRIP",colors={colors.green,colors.red,colors.yellow}}
    reactor_box.line_break()

    r_active.register(databus.ps, "reactor_active", r_active.update)
    r_trip.register(databus.ps, "reactor_tripped", function (trip) r_trip.update(util.trinary(trip, 2, 1)) end)

    local r_burn = DataIndicator{parent=reactor_box,label="BURN",format="%.1f",unit="mB/t",value=0,width=12,fg_bg=theme.field_box}
    local r_aburn = DataIndicator{parent=reactor_box,label="ACT BURN",format="%.1f",unit="mB/t",value=0,width=14,fg_bg=theme.field_box}
    local r_temp = DataIndicator{parent=reactor_box,label="TEMP",format="%.1f",unit="K",value=0,width=10,fg_bg=theme.field_box}
    local r_heat = DataIndicator{parent=reactor_box,label="HEAT",format="%.0f",value=0,width=10,fg_bg=theme.field_box}

    r_burn.register(databus.ps, "burn_rate", r_burn.update)
    r_aburn.register(databus.ps, "act_burn_rate", r_aburn.update)
    r_temp.register(databus.ps, "temp", r_temp.update)
    r_heat.register(databus.ps, "heating_rate", r_heat.update)

    -- fill bars
    local r_fuel = HorizontalBar{parent=reactor_box,label="FUEL",value=0,width=24,fg_bg=theme.field_box}
    local r_waste = HorizontalBar{parent=reactor_box,label="WASTE",value=0,width=24,fg_bg=theme.field_box}
    local r_cool = HorizontalBar{parent=reactor_box,label="COOL",value=0,width=24,fg_bg=theme.field_box}
    local r_hcool = HorizontalBar{parent=reactor_box,label="HCOOL",value=0,width=24,fg_bg=theme.field_box}

    r_fuel.register(databus.ps, "fuel_fill", r_fuel.update)
    r_waste.register(databus.ps, "waste_fill", r_waste.update)
    r_cool.register(databus.ps, "coolant_fill", r_cool.update)
    r_hcool.register(databus.ps, "hcoolant_fill", r_hcool.update)

    -- boiler box
    local boiler_box = Rectangle{parent=status_pane,x=math.floor((term_w-4)/2)+3,y=1,width=math.floor((term_w-4)/2),height=9,border=border(1,theme.highlight_box.bkg,true),even_inner=true}

    TextBox{parent=boiler_box,text="BOILER",fg_bg=theme.highlight_box}

    local b_temp = DataIndicator{parent=boiler_box,label="TEMP",format="%.1f",unit="K",value=0,width=10,fg_bg=theme.field_box}
    local b_boil = DataIndicator{parent=boiler_box,label="BOIL",format="%.1f",value=0,width=10,fg_bg=theme.field_box}
    local b_steam = HorizontalBar{parent=boiler_box,label="STEAM",value=0,width=22,fg_bg=theme.field_box}
    local b_water = HorizontalBar{parent=boiler_box,label="WATER",value=0,width=22,fg_bg=theme.field_box}

    b_temp.register(databus.ps, "boiler_1_temp", b_temp.update)
    b_boil.register(databus.ps, "boiler_1_boil_rate", b_boil.update)
    b_steam.register(databus.ps, "boiler_1_steam_fill", b_steam.update)
    b_water.register(databus.ps, "boiler_1_water_fill", b_water.update)

    -- turbine box
    local turb_box = Rectangle{parent=status_pane,x=1,y=12,width=math.floor((term_w-4)/2),height=8,border=border(1,theme.highlight_box.bkg,true),even_inner=true}

    TextBox{parent=turb_box,text="TURBINE",fg_bg=theme.highlight_box}

    local t_flow = DataIndicator{parent=turb_box,label="FLOW",format="%.1f",value=0,width=10,fg_bg=theme.field_box}
    local t_prod = DataIndicator{parent=turb_box,label="PROD",format="%.1f",unit="RF/t",value=0,width=12,fg_bg=theme.field_box}
    local t_steam = HorizontalBar{parent=turb_box,label="STEAM",value=0,width=22,fg_bg=theme.field_box}
    local t_energy = HorizontalBar{parent=turb_box,label="ENERGY",value=0,width=22,fg_bg=theme.field_box}

    t_flow.register(databus.ps, "turbine_1_flow", t_flow.update)
    t_prod.register(databus.ps, "turbine_1_prod", t_prod.update)
    t_steam.register(databus.ps, "turbine_1_steam_fill", t_steam.update)
    t_energy.register(databus.ps, "turbine_1_energy_fill", t_energy.update)

    -- facility box (ESS + SPS)
    local fac_box = Rectangle{parent=status_pane,x=math.floor((term_w-4)/2)+3,y=12,width=math.floor((term_w-4)/2),height=8,border=border(1,theme.highlight_box.bkg,true),even_inner=true}

    TextBox{parent=fac_box,text="FACILITY (ESS/SPS)",fg_bg=theme.highlight_box}

    local ess_fill = HorizontalBar{parent=fac_box,label="ESS",value=0,width=22,fg_bg=theme.field_box}
    local ess_in = DataIndicator{parent=fac_box,label="ESS IN",format="%.0f",value=0,width=10,fg_bg=theme.field_box}
    local sps_proc = DataIndicator{parent=fac_box,label="SPS PROC",format="%.1f",value=0,width=10,fg_bg=theme.field_box}
    local sps_in = HorizontalBar{parent=fac_box,label="SPS IN",value=0,width=20,fg_bg=theme.field_box}

    ess_fill.register(databus.ps, "ess_fill", ess_fill.update)
    ess_in.register(databus.ps, "ess_input", ess_in.update)
    sps_proc.register(databus.ps, "sps_process", sps_proc.update)
    sps_in.register(databus.ps, "sps_input_fill", sps_in.update)

    --#endregion

    --#region CONTROL Pane

    local control_pane = Div{parent=pane,width=term_w-2,height=term_h-6}

    local burn_box = Rectangle{parent=control_pane,x=2,y=1,width=term_w-6,height=7,border=border(1,theme.highlight_box.bkg,true),even_inner=true}

    TextBox{parent=burn_box,text="REACTOR CONTROL",fg_bg=theme.highlight_box}

    TextBox{parent=burn_box,y=2,text="Burn rate (mB/t):",width=18,fg_bg=fp.text_fg}
    local burn_field = require("graphics.elements.form.NumberField"){parent=burn_box,x=21,y=2,label="",width=8,default=0,min=0,max=1000,fg_bg=theme.field_box}

    PushButton{parent=burn_box,x=31,y=2,text="APPLY",callback=function () control.set_burn(tonumber(burn_field.value)) end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}

    PushButton{parent=burn_box,y=4,x=2,text="SCRAM",min_width=10,callback=function () control.scram() end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}
    PushButton{parent=burn_box,y=4,x=16,text="START",min_width=10,callback=function () control.activate() end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}
    PushButton{parent=burn_box,y=4,x=30,text="BURN +100",min_width=12,callback=function () control.nudge_burn(100) end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}
    PushButton{parent=burn_box,y=4,x=44,text="BURN -100",min_width=12,callback=function () control.nudge_burn(-100) end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}

    -- parameter tweaks box
    local param_box = Rectangle{parent=control_pane,x=2,y=10,width=term_w-6,height=term_h-14,border=border(1,theme.highlight_box.bkg,true),even_inner=true}

    TextBox{parent=param_box,text="SIMULATION PARAMETERS",fg_bg=theme.highlight_box}

    -- link status
    local plc_link = RGBLED{parent=param_box,y=2,label="PLC LINK",colors={colors.red,colors.yellow,colors.green}}
    local rtu_link = RGBLED{parent=param_box,y=2,label="RTU LINK",colors={colors.red,colors.yellow,colors.green}}

    plc_link.register(databus.ps, "plc_link", function (state)
        plc_link.update(util.trinary(state == PANEL_LINK_STATE.LINKED, 3, util.trinary(state == PANEL_LINK_STATE.DISCONNECTED, 1, 2)))
    end)
    rtu_link.register(databus.ps, "rtu_link", function (state)
        rtu_link.update(util.trinary(state == PANEL_LINK_STATE.LINKED, 3, util.trinary(state == PANEL_LINK_STATE.DISCONNECTED, 1, 2)))
    end)

    -- quick param adjustments
    TextBox{parent=param_box,y=4,text="Heating responsiveness:",width=24,fg_bg=fp.text_fg}
    PushButton{parent=param_box,x=26,y=4,text="+",min_width=3,callback=function () control.nudge_heat(0.05) end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}
    PushButton{parent=param_box,x=31,y=4,text="-",min_width=3,callback=function () control.nudge_heat(-0.05) end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}

    TextBox{parent=param_box,y=5,text="Fuel multiplier:",width=24,fg_bg=fp.text_fg}
    PushButton{parent=param_box,x=26,y=5,text="+",min_width=3,callback=function () control.nudge_fuel(0.1) end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}
    PushButton{parent=param_box,x=31,y=5,text="-",min_width=3,callback=function () control.nudge_fuel(-0.1) end,fg_bg=theme.highlight_box,active_fg_bg=theme.field_box}

    --#endregion

    --#region LOG Pane

    local log_pane = Div{parent=pane,width=term_w-2,height=term_h-6}

    local log_box = require("graphics.elements.ListBox"){parent=log_pane,x=1,y=1,width=term_w-4,height=term_h-8,fg_bg=fp.root}

    -- subscribe to new log lines and refresh the list
    local newest_shown = 0

    local function refresh_log()
        local lines = databus.get_log(newest_shown + 1, 30)
        if #lines > 0 then
            for _, line in ipairs(lines) do
                TextBox{parent=log_box,text=line.text,fg_bg=fp.root}
                newest_shown = line.idx
            end
        end
    end

    -- register a callback on each published log line
    databus.ps.subscribe("log_line", function () refresh_log() end)

    --#endregion

    -- define panes
    pane.value = 1
    pane.panes = { status_pane, control_pane, log_pane }

    return tab_bar
end

return init
