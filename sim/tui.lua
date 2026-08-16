--
-- SCADA Simulator TUI (terminal user interface)
--
-- A simple, dependency-free text UI drawn directly with the terminal
-- API. Shows live reactor/facility state and provides keyboard controls
-- (burn rate, SCRAM, start, parameter tweaks, log viewer). Deliberately
-- avoids the graphics library for maximum robustness.
--

local databus = require("sim.databus")

---@class sim_tui
local tui = {}

-- state references set at init
local facility ---@type table|nil
local plc ---@type table|nil
local rtu ---@type table|nil
local control ---@type table|nil

local SIM_VERSION = ""

-- current view tab: 1 = status, 2 = log
local tab = 1

-- set the version string
---@param version string
function tui.set_version(version) SIM_VERSION = version end

-- initialize the TUI
---@param cfg table simulator configuration
---@param fac table facility model
---@param plc_state table PLC session state
---@param rtu_state table RTU session state
---@param ctl table control callbacks
function tui.init(cfg, fac, plc_state, rtu_state, ctl) -- luacheck: ignore cfg
    facility, plc, rtu, control = fac, plc_state, rtu_state, ctl

    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

-- render a simple horizontal bar
---@param fill number 0..1 fill fraction
---@param width integer bar width
---@return string bar
local function bar(fill, width)
    if fill == nil then fill = 0 end
    local filled = math.floor(fill * width)
    if filled < 0 then filled = 0 end
    if filled > width then filled = width end
    return "[" .. string.rep("=", filled) .. string.rep(" ", width - filled) .. "]"
end

-- format a number with thousands separators
---@param n number
---@return string
local function commas(n)
    local s = string.format("%.0f", n or 0)
    local k = ""
    while #s > 3 do
        k = "," .. s:sub(-3) .. k
        s = s:sub(1, -4)
    end
    return s .. k
end

-- format a link state as text
---@param linked boolean
---@return string
local function link_txt(linked)
    if linked then return "LINKED" else return "DOWN" end
end

-- draw the status view
local function draw_status()
    local w, h = term.getSize()
    local lines = {}
    local ln = 1

    -- header
    lines[ln] = "=== SCADA SIMULATOR v" .. SIM_VERSION .. " ==="; ln = ln + 1
    lines[ln] = "PLC [" .. link_txt(plc.linked) .. "]   RTU [" .. link_txt(rtu.linked) .. "]"
    ln = ln + 2

    local unit = facility.units[plc.reactor_id]
    if unit then
        local r = unit.reactor
        local st = r.status

        -- reactor
        local act = st.active and "ACTIVE" or "STOPPED"
        local trip = r.tripped and ("  TRIP:" .. r.trip_cause) or ""
        lines[ln] = "REACTOR  " .. act .. "  TEMP " .. string.format("%.1f", st.temp) .. "K" ..
                    "  HEAT " .. commas(st.heating_rate) .. trip
        ln = ln + 1
        lines[ln] = "BURN " .. string.format("%.1f", st.burn_rate) .. "/" ..
                    string.format("%.1f", st.act_burn_rate) .. " mB/t   DMG " ..
                    string.format("%.1f", st.damage) .. "%"
        ln = ln + 1

        local bw = math.max(10, w - 22)
        lines[ln] = "FUEL  " .. bar(st.fuel_fill, bw) .. string.format(" %3.0f%%", st.fuel_fill * 100); ln = ln + 1
        lines[ln] = "WASTE " .. bar(st.waste_fill, bw) .. string.format(" %3.0f%%", st.waste_fill * 100); ln = ln + 1
        lines[ln] = "COOL  " .. bar(st.coolant_fill, bw) .. string.format(" %3.0f%%", st.coolant_fill * 100); ln = ln + 1
        lines[ln] = "HCOOL " .. bar(st.hcoolant_fill, bw) .. string.format(" %3.0f%%", st.hcoolant_fill * 100); ln = ln + 2

        -- boiler
        if #unit.boilers > 0 then
            local b = unit.boilers[1]
            lines[ln] = "BOILER  TEMP " .. string.format("%.1f", b.state.temperature) .. "K" ..
                        "  BOIL " .. string.format("%.0f", b.state.boil_rate)
            ln = ln + 1
            lines[ln] = "STEAM " .. bar(b.tanks.steam_fill, bw) .. string.format(" %3.0f%%", b.tanks.steam_fill * 100) ..
                        "  WATER " .. bar(b.tanks.water_fill, bw) .. string.format(" %3.0f%%", b.tanks.water_fill * 100)
            ln = ln + 2
        end

        -- turbine
        if #unit.turbines > 0 then
            local t = unit.turbines[1]
            lines[ln] = "TURBINE  FLOW " .. string.format("%.0f", t.state.flow_rate) ..
                        "  PROD " .. commas(t.state.prod_rate) .. " RF/t"
            ln = ln + 1
            lines[ln] = "STEAM " .. bar(t.tanks.steam_fill, bw) .. string.format(" %3.0f%%", t.tanks.steam_fill * 100) ..
                        "  ENERGY " .. bar(t.tanks.energy_fill, bw) .. string.format(" %3.0f%%", t.tanks.energy_fill * 100)
            ln = ln + 2
        end

        -- facility
        local ess = facility.ess
        lines[ln] = "ESS  " .. bar(ess.tanks.energy_fill, bw) .. string.format(" %3.0f%%", ess.tanks.energy_fill * 100) ..
                    "  IN " .. commas(ess.state.last_input) .. "  OUT " .. commas(ess.state.last_output)
        ln = ln + 1

        local sps = facility.sps
        lines[ln] = "SPS  PROC " .. string.format("%.1f", sps.state.process_rate) ..
                    "  IN " .. bar(sps.tanks.input_fill, bw) .. string.format(" %3.0f%%", sps.tanks.input_fill * 100)
        ln = ln + 2
    end

    -- control hint line
    lines[ln] = "[1]status [2]log  [b]burn [s]scram [a]start [+]-burn [-]-burn [h]heat [f]fuel [q]quit"
    ln = ln + 1

    -- render within terminal bounds
    term.clear()
    for i = 1, math.min(ln - 1, h) do
        term.setCursorPos(1, i)
        local line = lines[i] or ""
        term.write(line:sub(1, w))
    end
end

-- draw the log view
local function draw_log()
    local w, h = term.getSize()
    local lines = {}

    lines[1] = "=== SCADA SIMULATOR LOG ==="
    lines[2] = ""

    local logs = databus.get_log(nil, h - 4)
    local i = 3
    for _, entry in ipairs(logs) do
        if i <= h then
            lines[i] = entry.text
            i = i + 1
        end
    end

    lines[math.min(i, h)] = "[1]status [2]log  [q]quit"

    term.clear()
    for row = 1, math.min(#lines, h) do
        term.setCursorPos(1, row)
        term.write((lines[row] or ""):sub(1, w))
    end
end

-- draw the current view
function tui.draw()
    if tab == 2 then
        draw_log()
    else
        draw_status()
    end
end

-- handle a key press
---@param key integer key code
---@return boolean handled
function tui.handle_key(key)
    if key == keys.num1 then
        tab = 1
        tui.draw()
        return true
    elseif key == keys.num2 then
        tab = 2
        tui.draw()
        return true
    elseif key == keys.q then
        return false -- allow quit
    elseif key == keys.b then
        -- prompt for a burn rate (blocking read)
        local _, h = term.getSize()
        term.setCursorPos(1, h)
        term.clearLine()
        write("Burn rate (mB/t): ") -- luacheck: ignore write
        local value = tonumber(read())
        term.clearLine()
        if value then control.set_burn(value) end
        tui.draw()
        return true
    end

    -- non-input shortcuts
    if key == keys.s then control.scram() return true end
    if key == keys.a then control.activate() return true end

    -- burn nudges / param tweaks (distinct keys, no shift ambiguity)
    if key == keys.plus then control.nudge_burn(100) return true end
    if key == keys.minus then control.nudge_burn(-100) return true end
    if key == keys.h then control.nudge_heat(0.05) return true end
    if key == keys.f then control.nudge_fuel(0.1) return true end

    return false
end

return tui
