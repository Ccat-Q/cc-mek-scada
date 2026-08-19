--
-- Fission Reactor Programmable Logic Controller
--

require("/initenv").init_env()

local comms     = require("scada-common.comms")
local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local util      = require("scada-common.util")

local backplane = require("reactor-plc.backplane")
local configure = require("reactor-plc.configure")
local databus   = require("reactor-plc.databus")
local plc       = require("reactor-plc.plc")
local renderer  = require("reactor-plc.renderer")
local threads   = require("reactor-plc.threads")

local R_PLC_VERSION = "1.12.17"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- get configuration
----------------------------------------

if not plc.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not plc.load_config() then
            println("无法加载有效配置，请重新配置")
            return
        end
    else
        println("配置错误： " .. error)
        return
    end
end

local config = plc.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("正在启动 reactor-plc.startup v" .. R_PLC_VERSION)
log.info("========================================")
println(">> 裂变反应堆 PLC v" .. R_PLC_VERSION .. " <<")

crash.set_env("reactor-plc", R_PLC_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- startup
    ----------------------------------------

    -- report versions and ID
    databus.tx_versions(R_PLC_VERSION, comms.version)
    databus.tx_id(config.UnitID)

    -- mount connected devices
    ppm.mount_all()

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    -- shared memory across threads
    ---@class plc_shared_memory
    local __shared_memory = {
        -- networked setting
        networked = config.Networked,

        -- PLC system state flags
        ---@class plc_state
        plc_state = {
            fp_ok = false,
            shutdown = false,
            degraded = true,
            no_reactor = true,
            reactor_formed = true,
            auto_ctl = false,
            limit_force_ramp = false,
            wd_modem = true,
            wl_modem = true
        },

        -- control setpoints
        ---@class plc_setpoints
        setpoints = {
            burn_rate_en = false,
            burn_rate = 0.0
        },

        -- control limits/constraints
        ---@class plc_limits
        limits = {
            -- uses false rather than math.huge for transmission
            reportable_max_burn = false, ---@type number|false
            -- maximum burn rate to prevent loss of fuel fill
            fuel_max_burn = math.huge
        },

        -- global PLC devices, still initialized by the backplane
        ---@class plc_dev
        plc_dev = {
            reactor = nil       ---@type FissionReactor
        },

        -- system objects
        ---@class plc_sys
        plc_sys = {
            rps = nil,          ---@type rps
            plc_comms = nil,    ---@type plc_comms
            conn_watchdog = nil ---@type watchdog
        },

        -- message queues
        q = {
            mq_rps = mqueue.new(),
            mq_comms_tx = mqueue.new(),
            mq_comms_rx = mqueue.new()
        },

        -- message queue message types
        q_types = {
            MQ__RPS_CMD = {
                SCRAM = 1,
                DEGRADED_SCRAM = 2,
                TRIP_TIMEOUT = 3,
                RESET_REATTACH = 4
            },
            MQ__COMM_CMD = {
                SEND_STATUS = 1
            }
        }
    }

    local smem_dev = __shared_memory.plc_dev
    local smem_sys = __shared_memory.plc_sys

    local plc_state = __shared_memory.plc_state

    -- reactor and modem initialization
    backplane.init(config, __shared_memory)

    -- scram on boot if networked, otherwise leave the reactor be
    if __shared_memory.networked and (not plc_state.no_reactor) and plc_state.reactor_formed and smem_dev.reactor.getStatus() then
        log.debug("startup> 上电 SCRAM")
        smem_dev.reactor.scram()
    end

    -- setup front panel
    local message
    plc_state.fp_ok, message = renderer.try_start_ui(config)

    -- ...or not
    if not plc_state.fp_ok then
        println_ts(util.c("UI 错误： ", message))
        println("startup> 在没有前面板的情况下运行")
        log.error(util.c("前面板 GUI 渲染失败，错误： ", message))
        log.info("startup> 以无头模式运行，无前面板")
    end

    -- print a log message to the terminal as long as the UI isn't running
    local function _println_no_fp(msg) if not plc_state.fp_ok then println(msg) end end

    ----------------------------------------
    -- initialize PLC
    ----------------------------------------

    -- init reactor protection system
    smem_sys.rps = plc.rps_init(smem_dev.reactor, plc_state)
    log.debug("startup> RPS 初始化")

    -- notify user of emergency coolant configuration status
    if config.EmerCoolEnable then
        _println_no_fp("startup> 紧急冷却控制就绪")
        log.info("startup> 紧急冷却控制可用")
    end

    -- conditionally init comms
    if __shared_memory.networked then
        -- comms watchdog
        smem_sys.conn_watchdog = util.new_watchdog(config.ConnTimeout)
        log.debug("startup> 连接看门狗已启动")

        -- create network interface then setup comms
        smem_sys.plc_comms = plc.comms(R_PLC_VERSION, backplane.active_nic(), __shared_memory)
        log.debug("startup> 通信初始化")
    else
        _println_no_fp("startup> 以非联网模式启动")
        log.info("startup> 无网络启动")
    end

    databus.tx_hw_status(plc_state)

    _println_no_fp("startup> 完成")
    log.info("startup> 完成")

    -- init threads
    local main_thread = threads.thread__main(__shared_memory)
    local rps_thread  = threads.thread__rps(__shared_memory)

    if __shared_memory.networked then
        -- init comms threads
        local comms_thread_tx = threads.thread__comms_tx(__shared_memory)
        local comms_thread_rx = threads.thread__comms_rx(__shared_memory)

        -- setpoint control only needed when networked
        local sp_ctrl_thread = threads.thread__setpoint_control(__shared_memory)

        -- run threads
        parallel.waitForAll(main_thread.p_exec, rps_thread.p_exec, comms_thread_tx.p_exec, comms_thread_rx.p_exec, sp_ctrl_thread.p_exec)

        -- send status one last time after RPS shutdown
        smem_sys.plc_comms.send_status(plc_state.no_reactor, plc_state.reactor_formed)
        smem_sys.plc_comms.send_rps_status()

        -- close connection
        smem_sys.plc_comms.close()
    else
        -- run threads, excluding comms
        parallel.waitForAll(main_thread.p_exec, rps_thread.p_exec)
    end

    renderer.close_ui()

    println_ts("已退出")
    log.info("已退出")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    crash.exit()
else
    log.close()
end
