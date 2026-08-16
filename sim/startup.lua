--
-- SCADA Simulator Startup
--
-- Boots the simulator: loads configuration (or runs the configurator),
-- then runs the simulated PLC/RTU communications against the real SCADA
-- supervisor. No existing SCADA code is modified.
--

require("/initenv").init_env()

local log   = require("scada-common.log")
local util  = require("scada-common.util")

local sim = require("sim.sim")

local SIM_VERSION = "1.0.15"

local println = util.println

-- boot header
println("-- SCADA Simulator v" .. SIM_VERSION .. " --")
println("SIM> simulating PLC/RTU devices for the SCADA system")

-- initialize logging so the simulator can leave a trace for diagnostics
log.init("/log.txt", log.MODE.NEW, false)

-- load configuration
local config = sim.load_config()

if config == nil then
    println("SIM> configuration error, run 'configure'")
    return
end

if config._unconfigured then
    println("SIM> not configured, running configurator...")

    local ok, err = pcall(require, "sim.configure")
    if ok and err then
        local success, config_err = err.configure()
        if not success then
            println("SIM> configuration error: " .. tostring(config_err))
            return
        end

        -- reload config after configuration
        config = sim.load_config()
        if config == nil then
            println("SIM> failed to reload configuration")
            return
        end
    else
        println("SIM> failed to load configurator: " .. tostring(err))
        return
    end
end

-- run the simulator
local ok, err = pcall(sim.run, config)

if not ok then
    println("SIM> simulator crashed: " .. tostring(err))
end
