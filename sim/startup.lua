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
println("-- SCADA 模拟器 v" .. SIM_VERSION .. " --")
println("SIM> 正在为 SCADA 系统模拟 PLC/RTU 设备")

-- initialize logging so the simulator can leave a trace for diagnostics
log.init("/log.txt", log.MODE.NEW, false)

-- load configuration
local config = sim.load_config()

if config == nil then
    println("SIM> 配置错误，请运行 'configure'")
    return
end

if config._unconfigured then
    println("SIM> 尚未配置，正在运行配置向导...")

    local ok, err = pcall(require, "sim.configure")
    if ok and err then
        local success, config_err = err.configure()
        if not success then
            println("SIM> 配置错误：" .. tostring(config_err))
            return
        end

        -- reload config after configuration
        config = sim.load_config()
        if config == nil then
            println("SIM> 重新加载配置失败")
            return
        end
    else
        println("SIM> 加载配置向导失败：" .. tostring(err))
        return
    end
end

-- run the simulator
local ok, err = pcall(sim.run, config)

if not ok then
    println("SIM> 模拟器崩溃：" .. tostring(err))
end
