--
-- SCADA Simulator Data Bus
--
-- Publishes live simulated state and log lines to the front panel UI via
-- a PSIL publish/subscribe bus, mirroring how the other SCADA applications
-- drive their front panels. Also keeps a rolling log buffer for the log tab.
--

local psil = require("scada-common.psil")
local util = require("scada-common.util")

---@class sim_databus
local databus = {}

-- PSIL bus for the front panel
databus.ps = psil.create()

-- rolling log buffer (ring buffer)
local LOG_MAX = 200
local log_buffer = {}
local log_head = 0

-- current link state
local link_state = {
    plc = 1,   -- PANEL_LINK_STATE values (1=disconnected)
    rtu = 1
}

-- publish the reactor status block
---@param unit table reactor unit model
function databus.tx_reactor(unit)
    local r = unit.reactor
    local st = r.status

    databus.ps.publish("reactor_active", st.active)
    databus.ps.publish("reactor_tripped", r.tripped)
    databus.ps.publish("burn_rate", st.burn_rate)
    databus.ps.publish("act_burn_rate", st.act_burn_rate)
    databus.ps.publish("temp", st.temp)
    databus.ps.publish("damage", st.damage)
    databus.ps.publish("heating_rate", st.heating_rate)
    databus.ps.publish("fuel_fill", st.fuel_fill)
    databus.ps.publish("waste_fill", st.waste_fill)
    databus.ps.publish("coolant_fill", st.coolant_fill)
    databus.ps.publish("hcoolant_fill", st.hcoolant_fill)
end

-- publish boiler status
---@param boiler table boiler model
---@param idx integer boiler index
function databus.tx_boiler(boiler, idx)
    local pfx = "boiler_" .. idx .. "_"

    databus.ps.publish(pfx .. "temp", boiler.state.temperature)
    databus.ps.publish(pfx .. "boil_rate", boiler.state.boil_rate)
    databus.ps.publish(pfx .. "steam_fill", boiler.tanks.steam_fill)
    databus.ps.publish(pfx .. "water_fill", boiler.tanks.water_fill)
end

-- publish turbine status
---@param turbine table turbine model
---@param idx integer turbine index
function databus.tx_turbine(turbine, idx)
    local pfx = "turbine_" .. idx .. "_"

    databus.ps.publish(pfx .. "flow", turbine.state.flow_rate)
    databus.ps.publish(pfx .. "prod", turbine.state.prod_rate)
    databus.ps.publish(pfx .. "steam_fill", turbine.tanks.steam_fill)
    databus.ps.publish(pfx .. "energy_fill", turbine.tanks.energy_fill)
end

-- publish ESS status
---@param ess table ESS model
function databus.tx_ess(ess)
    databus.ps.publish("ess_fill", ess.tanks.energy_fill)
    databus.ps.publish("ess_input", ess.state.last_input)
    databus.ps.publish("ess_output", ess.state.last_output)
end

-- publish SPS status
---@param sps table SPS model
function databus.tx_sps(sps)
    databus.ps.publish("sps_process", sps.state.process_rate)
    databus.ps.publish("sps_input_fill", sps.tanks.input_fill)
    databus.ps.publish("sps_output_fill", sps.tanks.output_fill)
end

-- publish link state
---@param device string "plc" or "rtu"
---@param state PANEL_LINK_STATE
function databus.tx_link(device, state)
    link_state[device] = state
    databus.ps.publish(device .. "_link", state)
end

-- get the current link state for a device
---@param device string "plc" or "rtu"
---@return integer state
function databus.get_link(device) return link_state[device] end

-- publish a log line to the UI log buffer
---@param line string log line
function databus.tx_log(line)
    log_head = log_head + 1
    log_buffer[log_head] = line
    if log_head > LOG_MAX then log_buffer[log_head - LOG_MAX] = nil end

    databus.ps.publish("log_line", { idx = log_head, text = line })
end

-- get a range of buffered log lines
---@param start integer first index (1-based in buffer)
---@param count integer max lines
---@return table lines lines as { idx, text } newest first
function databus.get_log(start, count)
    local lines = {}
    local newest = log_head
    local oldest = math.max(1, newest - LOG_MAX + 1)

    if start == nil or start < oldest then start = oldest end

    local idx = newest
    local got = 0
    while idx >= start and got < (count or 20) do
        if log_buffer[idx] then
            table.insert(lines, { idx = idx, text = log_buffer[idx] })
            got = got + 1
        end
        idx = idx - 1
    end

    return lines
end

-- get the newest log index
---@return integer newest
function databus.log_newest() return log_head end

-- get the oldest available log index
---@return integer oldest
function databus.log_oldest() return math.max(1, log_head - LOG_MAX + 1) end

return databus
