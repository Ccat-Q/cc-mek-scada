--
-- SCADA Simulator: Simulated PLC/RTU Communications
--
-- Plays the role of a reactor PLC (RPLC protocol device side) AND an RTU
-- gateway (MODBUS protocol device side) over a CC modem, feeding the real
-- SCADA supervisor as if it were real Mekanism hardware. The simulator does
-- not modify any existing SCADA code; it merely speaks the same protocols
-- from an independent computer.
--
-- Architecture (per protocol review):
--   - Supervisor listens ONLY on SVR_Channel. Routing is by the frame's
--     reply channel (remote_channel): PLC_Channel -> PLC session,
--     RTU_Channel -> RTU session.
--   - This simulator opens BOTH PLC_Channel and RTU_Channel to receive
--     supervisor frames, and transmits to SVR_Channel with the role's own
--     local channel.
--   - Sequence numbers are strictly incrementing per session (start at
--     util.time_ms()*10 like real devices); any skip is fatal to the link.
--   - RTU advertisement must be embedded in the ESTABLISH packet data[4].
--   - RPS_STATUS has no request mechanism: the simulated PLC must push it.
--   - HMAC: if the supervisor has an AuthKey configured and we use a
--     wireless modem, we must network.init_mac() with the SAME passkey
--     BEFORE creating NICs, or all frames are silently dropped.
--

local comms    = require("scada-common.comms")
local log      = require("scada-common.log")
local network  = require("scada-common.network")
local ppm      = require("scada-common.ppm")
local types    = require("scada-common.types")
local util     = require("scada-common.util")

local model    = require("sim.model")
local databus  = require("sim.databus")
local renderer = require("sim.renderer")

local core = require("graphics.core")

local sim = {}

local PROTOCOL     = comms.PROTOCOL
local MGMT_TYPE    = comms.MGMT_TYPE
local RPLC_TYPE    = comms.RPLC_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local DEVICE_TYPE  = comms.DEVICE_TYPE
local PLC_AUTO_ACK = comms.PLC_AUTO_ACK

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE  = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE

local SIM_VERSION = "1.0.0"

--#region Configuration Loading

-- load simulator settings, falling back to defaults
---@return table|nil config settings table, or nil if invalid
function sim.load_config()
    local loaded = settings.load("/sim.settings") -- luacheck: ignore settings

    local config = {
        -- network
        SVR_Channel = settings.get("SVR_Channel") or 16240,  -- luacheck: ignore settings
        PLC_Channel = settings.get("PLC_Channel") or 16241,  -- luacheck: ignore settings
        RTU_Channel = settings.get("RTU_Channel") or 16242,  -- luacheck: ignore settings
        AuthKey = settings.get("AuthKey") or "",             -- luacheck: ignore settings
        TrustedRange = settings.get("TrustedRange") or 0,    -- luacheck: ignore settings
        -- simulation
        SimulatePLC = settings.get("SimulatePLC") ~= false,  -- luacheck: ignore settings
        SimulateRTU = settings.get("SimulateRTU") ~= false,  -- luacheck: ignore settings
        SimulateSPS = settings.get("SimulateSPS") ~= false,  -- luacheck: ignore settings
        ShowUI = settings.get("ShowUI") ~= false,            -- luacheck: ignore settings
        UnitCount = settings.get("UnitCount") or 1,          -- luacheck: ignore settings
        BoilersPerUnit = settings.get("BoilersPerUnit") or 1, -- luacheck: ignore settings
        TurbinesPerUnit = settings.get("TurbinesPerUnit") or 1, -- luacheck: ignore settings
        -- modem
        ModemSide = settings.get("ModemSide") or nil,        -- luacheck: ignore settings
        -- firmware IDs for establish
        PLCFirmware = settings.get("PLCFirmware") or ("sim-plc-" .. SIM_VERSION), -- luacheck: ignore settings
        RTUFirmware = settings.get("RTUFirmware") or ("sim-rtu-" .. SIM_VERSION) -- luacheck: ignore settings
    }

    if not loaded then
        -- no saved settings; return default config but mark as unconfigured
        config._unconfigured = true
    end

    if config.UnitCount < 1 or config.UnitCount > 4 then
        log.error("SIM: invalid UnitCount " .. config.UnitCount .. " (must be 1-4)")
        return nil
    end

    return config
end

--#endregion

--#region Simulator Core

-- create and run the simulator
---@param config table simulator configuration
function sim.run(config)
    local log_tag = "sim: "

    --#region Network Setup

    -- mount all peripherals through PPM so network.nic can resolve the
    -- modem's interface name (nic.connect() calls ppm.get_iface(), which
    -- requires the modem to be registered in the PPM mount table)
    ppm.mount_all()

    -- find the modem
    local modem, modem_iface
    if config.ModemSide then
        if ppm.get_modem(config.ModemSide) then
            modem = ppm.get_modem(config.ModemSide)
            modem_iface = config.ModemSide
        end
    end
    if not modem then
        modem, modem_iface = ppm.get_wireless_modem()
    end
    if not modem then
        -- fall back to any modem
        local devices = ppm.get_all_devices("modem")
        if #devices > 0 then
            modem = devices[1]
            modem_iface = ppm.get_iface(modem)
        end
    end

    if not modem then
        util.println_ts("SIM> no modem found! attach a wired/wireless modem and restart.")
        return
    end

    -- initialize HMAC if an auth key is configured (must be before NIC creation)
    if config.AuthKey and #config.AuthKey > 0 then
        log.info(log_tag .. "initializing message authentication")
        network.init_mac(config.AuthKey)
    end

    -- trusted range
    if config.TrustedRange and config.TrustedRange > 0 then
        comms.set_trusted_range(config.TrustedRange)
    end

    -- create the NIC (listens for link-layer discovery on SVR_Channel)
    local nic = network.nic(modem, config.SVR_Channel)

    nic.closeAll()
    if config.SimulatePLC then nic.open(config.PLC_Channel) end
    if config.SimulateRTU then nic.open(config.RTU_Channel) end

    log.info(util.c(log_tag, "modem [", modem_iface, "] opened, SVR=", config.SVR_Channel,
        " PLC=", config.PLC_Channel, " RTU=", config.RTU_Channel))

    --#endregion

    --#region Facility Model

    local facility = model.new_facility({
        num_units = config.UnitCount,
        boilers_per_unit = { config.BoilersPerUnit },
        turbines_per_unit = { config.TurbinesPerUnit }
    })

    --#endregion

    --#region Control Callbacks (front panel actions)

    -- forward-declare session state so callbacks can reference it
    local plc ---@type table|nil
    local rtu ---@type table|nil

    -- control table passed to the front panel UI
    local control = {}

    -- set the burn rate setpoint
    function control.set_burn(rate)
        rate = tonumber(rate) or 0
        local reactor = facility.units[plc.reactor_id] and facility.units[plc.reactor_id].reactor
        if reactor then
            if reactor.set_burn_rate(rate) then
                log.info(util.c(log_tag, "burn rate set to ", rate, " mB/t"))
                databus.tx_log(util.c("[CTRL] burn rate set to ", rate, " mB/t"))
            else
                log.warning(util.c(log_tag, "invalid burn rate ", rate))
                databus.tx_log(util.c("[CTRL] invalid burn rate ", rate))
            end
        end
    end

    -- SCRAM the reactor
    function control.scram()
        local reactor = facility.units[plc.reactor_id] and facility.units[plc.reactor_id].reactor
        if reactor then
            reactor.scram()
            log.info(log_tag .. "reactor SCRAMMED from front panel")
            databus.tx_log("[CTRL] reactor SCRAMMED")
        end
    end

    -- activate the reactor
    function control.activate()
        local reactor = facility.units[plc.reactor_id] and facility.units[plc.reactor_id].reactor
        if reactor then
            if reactor.activate() then
                log.info(log_tag .. "reactor activated from front panel")
                databus.tx_log("[CTRL] reactor activated")
            else
                log.warning(log_tag .. "cannot activate (reactor tripped)")
                databus.tx_log("[CTRL] activate failed (tripped)")
            end
        end
    end

    -- nudge the burn rate by a delta
    function control.nudge_burn(delta)
        local reactor = facility.units[plc.reactor_id] and facility.units[plc.reactor_id].reactor
        if reactor then
            local new_rate = math.max(0, reactor.status.burn_rate + delta)
            if reactor.set_burn_rate(new_rate) then
                log.info(util.c(log_tag, "burn rate nudged to ", new_rate, " mB/t"))
            end
        end
    end

    -- nudge the temperature heat-out coefficient
    function control.nudge_heat(delta)
        if facility.heat_out_k then
            facility.heat_out_k = math.max(0.01, facility.heat_out_k + delta)
            log.info(util.c(log_tag, "heat responsiveness -> ", string.format("%.3f", facility.heat_out_k)))
        end
    end

    -- nudge the fuel multiplier
    function control.nudge_fuel(delta)
        if facility.fuel_mult then
            facility.fuel_mult = math.max(0.1, facility.fuel_mult + delta)
            log.info(util.c(log_tag, "fuel multiplier -> ", string.format("%.2f", facility.fuel_mult)))
        end
    end

    -- start the front panel UI
    if config.ShowUI ~= false then
        local ui_ok, ui_err = renderer.try_start_ui(config, control)
        if not ui_ok then
            log.warning(util.c(log_tag, "failed to start front panel UI: ", tostring(ui_err)))
        end
    end

    --#endregion

    --#region Session State

    -- PLC session state
    plc = {
        enabled = config.SimulatePLC,
        linked = false,
        sv_addr = comms.BROADCAST,
        seq_num = util.time_ms() * 10,
        r_seq_num = nil,       ---@type nil|integer
        reactor_id = 1,
        auto_ack_token = 0,
        reportable_max_burn = false,
        last_status_send = 0,
        last_keepalive_send = 0,
        resend_build = true
    }

    -- RTU session state
    rtu = {
        enabled = config.SimulateRTU,
        linked = false,
        sv_addr = comms.BROADCAST,
        seq_num = util.time_ms() * 10,
        r_seq_num = nil,       ---@type nil|integer
        txn_id = 0,
        last_keepalive_send = 0
    }

    --#endregion

    --#region Build Advertisements

    -- build the RTU advertisement table (order = MODBUS unit_id!)
    local function build_advertisement()
        local advert = {}
        local unit_count = config.UnitCount

        -- per-unit devices
        for u = 1, unit_count do
            -- boilers
            for b = 1, config.BoilersPerUnit do
                table.insert(advert, { RTU_UNIT_TYPE.BOILER_VALVE, b, u, nil })
            end
            -- turbines
            for t = 1, config.TurbinesPerUnit do
                table.insert(advert, { RTU_UNIT_TYPE.TURBINE_VALVE, t, u, nil })
            end
        end

        -- facility devices
        table.insert(advert, { RTU_UNIT_TYPE.IMATRIX, 1, 0, nil })
        if config.SimulateSPS then
            table.insert(advert, { RTU_UNIT_TYPE.SPS, 1, 0, nil })
        end

        return advert
    end

    --#endregion

    --#region MODBUS Register Maps

    -- register maps per device type, matching rtu/dev/*_rtu.lua connection order

    local function boiler_registers(unit)
        local boiler = unit.boilers[1]
        return {
            di = { function() return boiler.formed end },
            ir = {
                -- build (IR1-12)
                function() return boiler.build.length end,
                function() return boiler.build.width end,
                function() return boiler.build.height end,
                function() return boiler.build.min_pos end,
                function() return boiler.build.max_pos end,
                function() return boiler.build.boil_cap end,
                function() return boiler.build.steam_cap end,
                function() return boiler.build.water_cap end,
                function() return boiler.build.hcoolant_cap end,
                function() return boiler.build.ccoolant_cap end,
                function() return boiler.build.superheaters end,
                function() return boiler.build.max_boil_rate end,
                -- state (IR13-15)
                function() return boiler.state.temperature end,
                function() return boiler.state.boil_rate end,
                function() return boiler.state.env_loss end,
                -- tanks (IR16-27)
                function() return types.new_tank_fluid("mekanism:steam", boiler.tanks.steam) end,
                function() return math.max(0, boiler.build.steam_cap - boiler.tanks.steam) end,
                function() return boiler.tanks.steam_fill end,
                function() return types.new_tank_fluid("minecraft:water", boiler.tanks.water) end,
                function() return math.max(0, boiler.build.water_cap - boiler.tanks.water) end,
                function() return boiler.tanks.water_fill end,
                function() return types.new_tank_fluid("mekanism:superheated_sodium", boiler.tanks.hcool) end,
                function() return math.max(0, boiler.build.hcoolant_cap - boiler.tanks.hcool) end,
                function() return boiler.tanks.hcool_fill end,
                function() return types.new_tank_fluid("mekanism:sodium", boiler.tanks.ccool) end,
                function() return math.max(0, boiler.build.ccoolant_cap - boiler.tanks.ccool) end,
                function() return boiler.tanks.ccool_fill end
            }
        }
    end

    local function turbine_registers(unit)
        local turbine = unit.turbines[1]
        return {
            di = { function() return turbine.formed end },
            coils = {
                function() turbine.state.dumping_mode = "DUMPING_EXCESS" end,
                function() turbine.state.dumping_mode = "IDLE" end
            },
            ir = {
                -- build (IR1-15)
                function() return turbine.build.length end,
                function() return turbine.build.width end,
                function() return turbine.build.height end,
                function() return turbine.build.min_pos end,
                function() return turbine.build.max_pos end,
                function() return turbine.build.blades end,
                function() return turbine.build.coils end,
                function() return turbine.build.vents end,
                function() return turbine.build.dispersers end,
                function() return turbine.build.condensers end,
                function() return turbine.build.steam_cap end,
                function() return turbine.build.max_energy end,
                function() return turbine.build.max_flow_rate end,
                function() return turbine.build.max_production end,
                function() return turbine.build.max_water_output end,
                -- state (IR16-19)
                function() return turbine.state.flow_rate end,
                function() return turbine.state.prod_rate end,
                function() return turbine.state.steam_input_rate end,
                function() return turbine.state.dumping_mode end,
                -- tanks (IR20-25)
                function() return types.new_tank_fluid("mekanism:steam", turbine.tanks.steam) end,
                function() return math.max(0, turbine.build.steam_cap - turbine.tanks.steam) end,
                function() return turbine.tanks.steam_fill end,
                function() return turbine.tanks.energy end,   -- energy is numeric, not a fluid
                function() return math.max(0, turbine.build.max_energy - turbine.tanks.energy) end,
                function() return turbine.tanks.energy_fill end
            },
            hr = {
                { read = function() return turbine.state.dumping_mode end,
                  write = function(v) turbine.state.dumping_mode = v end }
            }
        }
    end

    local function matrix_registers(fac)
        local matrix = fac.ess
        return {
            di = { function() return matrix.formed end },
            ir = {
                -- build (IR1-9)
                function() return matrix.build.length end,
                function() return matrix.build.width end,
                function() return matrix.build.height end,
                function() return matrix.build.min_pos end,
                function() return matrix.build.max_pos end,
                function() return matrix.build.max_energy end,
                function() return matrix.build.transfer_cap end,
                function() return matrix.build.cells end,
                function() return matrix.build.providers end,
                -- state (IR10-11)
                function() return matrix.state.last_input end,
                function() return matrix.state.last_output end,
                -- tanks (IR12-14)
                function() return matrix.tanks.energy end,
                function() return math.max(0, matrix.build.max_energy - matrix.tanks.energy) end,
                function() return matrix.tanks.energy_fill end
            }
        }
    end

    local function sps_registers(fac)
        local sps = fac.sps
        return {
            di = { function() return sps.formed end },
            ir = {
                -- build (IR1-9)
                function() return sps.build.length end,
                function() return sps.build.width end,
                function() return sps.build.height end,
                function() return sps.build.min_pos end,
                function() return sps.build.max_pos end,
                function() return sps.build.coils end,
                function() return sps.build.input_cap end,
                function() return sps.build.output_cap end,
                function() return sps.build.max_energy end,
                -- state (IR10)
                function() return sps.state.process_rate end,
                -- tanks (IR11-19)
                function() return types.new_tank_fluid("mekanism:polonium", sps.tanks.input) end,
                function() return math.max(0, sps.build.input_cap - sps.tanks.input) end,
                function() return sps.tanks.input_fill end,
                function() return types.new_tank_fluid("mekanism:antimatter", sps.tanks.output) end,
                function() return math.max(0, sps.build.output_cap - sps.tanks.output) end,
                function() return sps.tanks.output_fill end,
                function() return sps.tanks.energy end,
                function() return math.max(0, sps.build.max_energy - sps.tanks.energy) end,
                function() return sps.tanks.energy_fill end
            }
        }
    end

    -- map an advert entry to its register map
    local function get_registers(advert_index)
        -- advert order: per-unit boilers, per-unit turbines, facility matrix, facility SPS
        local count_boilers = config.BoilersPerUnit
        local count_turbines = config.TurbinesPerUnit

        local idx = advert_index
        local total_devices = config.UnitCount * (count_boilers + count_turbines)

        if idx <= config.UnitCount * count_boilers then
            -- boiler: unit = ceil(idx / boilers_per_unit)
            local unit_num = math.ceil(idx / count_boilers)
            return boiler_registers(facility.units[unit_num])
        elseif idx <= total_devices then
            idx = idx - config.UnitCount * count_boilers
            local unit_num = math.ceil(idx / count_turbines)
            return turbine_registers(facility.units[unit_num])
        elseif idx == total_devices + 1 then
            -- facility matrix
            return matrix_registers(facility)
        else
            -- facility SPS
            return sps_registers(facility)
        end
    end

    --#endregion

    --#region Frame Sending Helpers

    -- send a frame on the given role channel
    ---@param role_channel integer local channel (PLC_Channel or RTU_Channel)
    ---@param frame scada_frame
    local function _send(role_channel, frame)
        nic.transmit(config.SVR_Channel, role_channel, frame)
    end

    -- send a PLC RPLC packet
    ---@param packet_type RPLC_TYPE
    ---@param data table
    local function plc_send(packet_type, data)
        local rplc = comms.rplc_container()
        rplc.make(plc.reactor_id, packet_type, data)

        local frame = comms.scada_frame()
        frame.make(plc.sv_addr, plc.seq_num, PROTOCOL.RPLC, rplc.raw_packet())
        _send(config.PLC_Channel, frame)
        plc.seq_num = plc.seq_num + 1
    end

    -- send a PLC management packet
    ---@param msg_type MGMT_TYPE
    ---@param data table
    local function plc_send_mgmt(msg_type, data)
        local mgmt = comms.mgmt_container()
        mgmt.make(msg_type, data)

        local frame = comms.scada_frame()
        frame.make(plc.sv_addr, plc.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
        _send(config.PLC_Channel, frame)
        plc.seq_num = plc.seq_num + 1
    end

    -- send an RTU management packet
    ---@param msg_type MGMT_TYPE
    ---@param data table
    local function rtu_send_mgmt(msg_type, data)
        local mgmt = comms.mgmt_container()
        mgmt.make(msg_type, data)

        local frame = comms.scada_frame()
        frame.make(rtu.sv_addr, rtu.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
        _send(config.RTU_Channel, frame)
        rtu.seq_num = rtu.seq_num + 1
    end

    -- send an RTU MODBUS packet
    ---@param m_cnt modbus_container
    local function rtu_send_modbus(m_cnt)
        local frame = comms.scada_frame()
        frame.make(rtu.sv_addr, rtu.seq_num, PROTOCOL.MODBUS_TCP, m_cnt.raw_packet())
        _send(config.RTU_Channel, frame)
        rtu.seq_num = rtu.seq_num + 1
    end

    --#endregion

    --#region PLC Data Generation

    -- send reactor status (8-element plc_status_msg)
    local function plc_send_status()
        local unit = facility.units[plc.reactor_id]
        local reactor = unit.reactor

        -- update the status data
        local data = reactor.get_status_data()

        local sys_status = {
            util.time(),                    -- [1] last_status_update (ms)
            data[1] and not reactor.tripped, -- [2] control_state (not scrammed)
            false,                          -- [3] no_reactor
            true,                           -- [4] formed
            plc.auto_ack_token,             -- [5] auto_ack_token
            plc.reportable_max_burn,        -- [6] reportable_max_burn (number or false)
            reactor.status.heating_rate,    -- [7] heating_rate
            data                            -- [8] mek_data[17]
        }

        plc_send(RPLC_TYPE.STATUS, sys_status)
    end

    -- send the reactor structure (13-element)
    local function plc_send_struct()
        local unit = facility.units[plc.reactor_id]
        local reactor = unit.reactor

        plc_send(RPLC_TYPE.MEK_STRUCT, reactor.get_struct_data())
        plc.resend_build = false
    end

    -- send RPS status (13-element)
    local function plc_send_rps_status()
        local unit = facility.units[plc.reactor_id]
        local reactor = unit.reactor

        local status = { reactor.tripped, reactor.trip_cause }
        for _, state_bit in ipairs(reactor.get_rps_status()) do
            table.insert(status, state_bit)
        end

        plc_send(RPLC_TYPE.RPS_STATUS, status)
    end

    --#endregion

    --#region RTU MODBUS Response

    -- handle a MODBUS read request
    ---@param adu modbus_adu
    ---@param regs table register map
    ---@param txn_id integer
    ---@param unit_id integer
    ---@param func_code MODBUS_FCODE
    ---@param start integer start address (1-based)
    ---@param count integer number of registers
    local function modbus_read(regs, txn_id, unit_id, func_code, start, count)
        local readings = {}
        local list = nil

        if func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
            list = regs.di
        elseif func_code == MODBUS_FCODE.READ_INPUT_REGS then
            list = regs.ir
        elseif func_code == MODBUS_FCODE.READ_COILS then
            -- coils on real RTU devices are write-only; return the last-written state
            list = regs.coils_read
        elseif func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
            list = regs.hr
        end

        if list then
            for i = start, start + count - 1 do
                if list[i] then
                    table.insert(readings, list[i]())
                else
                    -- address out of range
                    local reply = comms.modbus_container()
                    reply.make(txn_id, unit_id, bit.bor(func_code, MODBUS_FCODE.ERROR_FLAG), { MODBUS_EXCODE.ILLEGAL_DATA_ADDR })
                    rtu_send_modbus(reply)
                    return
                end
            end

            local reply = comms.modbus_container()
            reply.make(txn_id, unit_id, func_code, readings)
            rtu_send_modbus(reply)
        else
            -- unsupported function for this device
            local reply = comms.modbus_container()
            reply.make(txn_id, unit_id, bit.bor(func_code, MODBUS_FCODE.ERROR_FLAG), { MODBUS_EXCODE.ILLEGAL_FUNCTION })
            rtu_send_modbus(reply)
        end
    end

    -- handle a MODBUS write request
    ---@param adu modbus_adu
    ---@param regs table register map
    ---@param txn_id integer
    ---@param unit_id integer
    ---@param func_code MODBUS_FCODE
    ---@param start integer start address
    ---@param values table values to write
    local function modbus_write(regs, txn_id, unit_id, func_code, start, values)
        local ok = true

        if func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
            -- data: {start, value}; single coil, 1-based index
            local idx = start
            if regs.coils and regs.coils[idx] then
                regs.coils[idx]()
            else ok = false end
        elseif func_code == MODBUS_FCODE.WRITE_SINGLE_HOLD_REG then
            local idx = start
            if regs.hr and regs.hr[idx] then
                regs.hr[idx].write(values[1])
            else ok = false end
        elseif func_code == MODBUS_FCODE.WRITE_MUL_COILS then
            for i = 1, #values do
                local idx = start + i - 1
                if regs.coils and regs.coils[idx] then
                    regs.coils[idx]()
                else ok = false break end
            end
        elseif func_code == MODBUS_FCODE.WRITE_MUL_HOLD_REGS then
            for i = 1, #values do
                local idx = start + i - 1
                if regs.hr and regs.hr[idx] then
                    regs.hr[idx].write(values[i])
                else ok = false break end
            end
        end

        if ok then
            -- success: echo func code with empty data
            local reply = comms.modbus_container()
            reply.make(txn_id, unit_id, func_code, {})
            rtu_send_modbus(reply)
        else
            local reply = comms.modbus_container()
            reply.make(txn_id, unit_id, bit.bor(func_code, MODBUS_FCODE.ERROR_FLAG), { MODBUS_EXCODE.ILLEGAL_DATA_ADDR })
            rtu_send_modbus(reply)
        end
    end

    --#endregion

    --#region Packet Handling

    -- handle an incoming PLC-channel packet
    ---@param packet rplc_packet|mgmt_packet
    local function handle_plc_packet(packet)
        local protocol = packet.scada_frame.protocol()

        if protocol == PROTOCOL.RPLC then
            ---@cast packet rplc_packet
            if packet.type == RPLC_TYPE.STATUS then
                -- request to resend status
                plc_send_status()
            elseif packet.type == RPLC_TYPE.MEK_STRUCT then
                -- request to resend structure
                plc_send_struct()
            elseif packet.type == RPLC_TYPE.MEK_BURN_RATE then
                local unit = facility.units[plc.reactor_id]
                local reactor = unit.reactor
                local ok = false
                if packet.length >= 1 and type(packet.data[1]) == "number" then
                    ok = reactor.set_burn_rate(packet.data[1])
                    if ok then
                        reactor.activate()
                        plc.reportable_max_burn = reactor.build.max_burn_rate
                    end
                end
                plc_send(RPLC_TYPE.MEK_BURN_RATE, { ok })
            elseif packet.type == RPLC_TYPE.RPS_ENABLE then
                local unit = facility.units[plc.reactor_id]
                local reactor = unit.reactor
                local ok = reactor.activate()
                plc_send(RPLC_TYPE.RPS_ENABLE, { ok })
            elseif packet.type == RPLC_TYPE.RPS_DISABLE then
                local unit = facility.units[plc.reactor_id]
                unit.reactor.scram()
                plc_send(RPLC_TYPE.RPS_DISABLE, { true })
            elseif packet.type == RPLC_TYPE.RPS_SCRAM then
                local unit = facility.units[plc.reactor_id]
                unit.reactor.scram()
                plc_send(RPLC_TYPE.RPS_SCRAM, { true })
            elseif packet.type == RPLC_TYPE.RPS_ASCRAM then
                local unit = facility.units[plc.reactor_id]
                unit.reactor.scram()
                plc_send(RPLC_TYPE.RPS_ASCRAM, { true })
            elseif packet.type == RPLC_TYPE.RPS_RESET then
                local unit = facility.units[plc.reactor_id]
                unit.reactor.reset_rps()
                plc_send(RPLC_TYPE.RPS_RESET, { true })
            elseif packet.type == RPLC_TYPE.RPS_AUTO_RESET then
                local unit = facility.units[plc.reactor_id]
                local ok = unit.reactor.auto_reset_rps()
                plc_send(RPLC_TYPE.RPS_AUTO_RESET, { ok })
            elseif packet.type == RPLC_TYPE.AUTO_BURN_RATE then
                local unit = facility.units[plc.reactor_id]
                local reactor = unit.reactor
                local ack = PLC_AUTO_ACK.FAIL
                if packet.length >= 3 and type(packet.data[1]) == "number" then
                    local rate = packet.data[1]
                    local ramp = packet.data[2]
                    local token = packet.data[3]

                    if rate <= 0 then
                        -- disable reactor
                        reactor.scram()
                        plc.auto_ack_token = token
                        ack = PLC_AUTO_ACK.ZERO_DIS_OK
                    elseif reactor.set_burn_rate(rate) then
                        reactor.activate()
                        plc.auto_ack_token = token
                        plc.reportable_max_burn = reactor.build.max_burn_rate
                        ack = util.trinary(ramp, PLC_AUTO_ACK.RAMP_SET_OK, PLC_AUTO_ACK.DIRECT_SET_OK)
                    end
                end
                plc_send(RPLC_TYPE.AUTO_BURN_RATE, { ack })
            end
        elseif protocol == PROTOCOL.SCADA_MGMT then
            ---@cast packet mgmt_packet
            if packet.type == MGMT_TYPE.ESTABLISH then
                if packet.length >= 1 then
                    local est_ack = packet.data[1]
                    if est_ack == ESTABLISH_ACK.ALLOW then
                        if not plc.linked then
                            plc.linked = true
                            plc.sv_addr = packet.scada_frame.src_addr()
                            plc.r_seq_num = packet.scada_frame.seq_num() + 1
                            log.info(log_tag .. "PLC session established with supervisor @" .. plc.sv_addr)
                            databus.tx_link("plc", types.PANEL_LINK_STATE.LINKED)

                            -- send initial status/struct/rps to get supervisor out of retry
                            plc_send_status()
                            plc_send_struct()
                            plc_send_rps_status()
                        end
                    else
                        log.warning(util.c(log_tag, "PLC establish denied (ack=", est_ack, "), retrying..."))
                        plc.linked = false
                        plc.sv_addr = comms.BROADCAST
                    end
                end
            elseif packet.type == MGMT_TYPE.KEEP_ALIVE then
                if packet.length == 1 and type(packet.data[1]) == "number" then
                    plc_send_mgmt(MGMT_TYPE.KEEP_ALIVE, { packet.data[1], util.time() })
                end
            elseif packet.type == MGMT_TYPE.CLOSE then
                plc.linked = false
                plc.sv_addr = comms.BROADCAST
                log.info(log_tag .. "PLC session closed by supervisor")
                databus.tx_link("plc", types.PANEL_LINK_STATE.DISCONNECTED)
            end
        end
    end

    -- handle an incoming RTU-channel packet
    ---@param packet modbus_adu|mgmt_packet
    local function handle_rtu_packet(packet)
        local protocol = packet.scada_frame.protocol()

        if protocol == PROTOCOL.MODBUS_TCP then
            ---@cast packet modbus_adu
            if rtu.linked then
                local regs = get_registers(packet.unit_id)
                if regs then
                    local start = packet.data[1]
                    if packet.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS or
                       packet.func_code == MODBUS_FCODE.READ_INPUT_REGS or
                       packet.func_code == MODBUS_FCODE.READ_COILS or
                       packet.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
                        modbus_read(regs, packet.txn_id, packet.unit_id, packet.func_code, start, packet.data[2])
                    else
                        -- write request: data = {start, values...}
                        local values = {}
                        for i = 3, #packet.data do table.insert(values, packet.data[i]) end
                        modbus_write(regs, packet.txn_id, packet.unit_id, packet.func_code, start, values)
                    end
                else
                    -- unknown unit
                    local reply = comms.modbus_container()
                    reply.make(packet.txn_id, packet.unit_id, bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG), { MODBUS_EXCODE.GATEWAY_PATH_UNAVAILABLE })
                    rtu_send_modbus(reply)
                end
            end
        elseif protocol == PROTOCOL.SCADA_MGMT then
            ---@cast packet mgmt_packet
            if packet.type == MGMT_TYPE.ESTABLISH then
                if packet.length >= 1 then
                    local est_ack = packet.data[1]
                    if est_ack == ESTABLISH_ACK.ALLOW then
                        if not rtu.linked then
                            rtu.linked = true
                            rtu.sv_addr = packet.scada_frame.src_addr()
                            rtu.r_seq_num = packet.scada_frame.seq_num() + 1
                            log.info(log_tag .. "RTU session established with supervisor @" .. rtu.sv_addr)
                            databus.tx_link("rtu", types.PANEL_LINK_STATE.LINKED)
                        end
                    else
                        log.warning(util.c(log_tag, "RTU establish denied (ack=", est_ack, "), retrying..."))
                        rtu.linked = false
                        rtu.sv_addr = comms.BROADCAST
                    end
                end
            elseif packet.type == MGMT_TYPE.KEEP_ALIVE then
                if packet.length == 1 and type(packet.data[1]) == "number" then
                    rtu_send_mgmt(MGMT_TYPE.KEEP_ALIVE, { packet.data[1], util.time() })
                end
            elseif packet.type == MGMT_TYPE.CLOSE then
                rtu.linked = false
                rtu.sv_addr = comms.BROADCAST
                log.info(log_tag .. "RTU session closed by supervisor")
                databus.tx_link("rtu", types.PANEL_LINK_STATE.DISCONNECTED)
            elseif packet.type == MGMT_TYPE.RTU_ADVERT then
                -- supervisor requests capabilities again
                rtu_send_mgmt(MGMT_TYPE.RTU_ADVERT, build_advertisement())
            end
        end
    end

    --#endregion

    --#region Main Loop

    -- periodic link attempts (throttled to avoid re-establish storms that
    -- the supervisor treats as session-terminating). NOTE: the ESTABLISH
    -- handshake must NOT advance the session seq_num - the supervisor
    -- locks its expected inbound sequence to (ESTABLISH seq + 1). If we
    -- retried ESTABLISH with an incrementing seq, the post-link frames
    -- would be out of order and the supervisor would drop the session.
    local last_est = { plc = 0, rtu = 0 }
    local ESTABLISH_RETRY_S = 2.0

    local function try_establish()
        local now = util.time()

        if plc.enabled and not plc.linked and nic.is_network_up() and (now - last_est.plc) >= ESTABLISH_RETRY_S then
            last_est.plc = now
            log.info(log_tag .. "PLC ESTABLISH -> " .. plc.reactor_id)
            plc_send_mgmt(MGMT_TYPE.ESTABLISH, { comms.version, config.PLCFirmware, DEVICE_TYPE.PLC, plc.reactor_id })
            plc.seq_num = plc.seq_num - 1   -- do not advance seq on establish retries
        end

        if rtu.enabled and not rtu.linked and nic.is_network_up() and (now - last_est.rtu) >= ESTABLISH_RETRY_S then
            last_est.rtu = now
            log.info(log_tag .. "RTU ESTABLISH (advert)")
            rtu_send_mgmt(MGMT_TYPE.ESTABLISH, { comms.version, config.RTUFirmware, DEVICE_TYPE.RTU, build_advertisement() })
            rtu.seq_num = rtu.seq_num - 1   -- do not advance seq on establish retries
        end
    end

    -- periodic sends
    local function periodic_sends()
        local now = util.time()

        -- PLC status push every ~1 second
        if plc.enabled and plc.linked and (now - plc.last_status_send) >= 1 then
            plc.last_status_send = now
            plc_send_status()
            plc_send_rps_status()
            if plc.resend_build then plc_send_struct() end
        end
    end

    -- publish live state to the front panel UI
    local function ui_update()
        local unit = facility.units[plc.reactor_id]
        if unit then
            databus.tx_reactor(unit)
            for i, boiler in ipairs(unit.boilers) do databus.tx_boiler(boiler, i) end
            for i, turbine in ipairs(unit.turbines) do databus.tx_turbine(turbine, i) end
        end
        databus.tx_ess(facility.ess)
        databus.tx_sps(facility.sps)
    end

    -- main loop (timer-driven, matching real RTU/PLC device loops)
    local loop_clock = util.new_clock(0.5)

    loop_clock.start()
    log.info(log_tag .. "main loop started, waiting for timers")

    local ticks = 0
    while true do
        local event, param1, param2, param3, param4, param5 = util.pull_event()

        if event == "timer" then
            if loop_clock.is_clock(param1) then
                ticks = ticks + 1
                if ticks == 1 or ticks % 20 == 0 then
                    log.info(util.c(log_tag, "tick ", ticks, " (net_up=", tostring(nic.is_network_up()),
                        " plc_linked=", tostring(plc.linked), " rtu_linked=", tostring(rtu.linked), ")"))
                end

                -- periodic tick: model update, link discovery, establish retry, data pushes
                facility.update()
                nic.periodic()
                try_establish()
                periodic_sends()
                ui_update()

                -- schedule next tick
                loop_clock.start()
            end
        elseif event == "modem_message" then
            local frame = nic.receive(param1, param2, param3, param4, param5)

            if frame then
                local l_chan = frame.local_channel()

                if l_chan == config.PLC_Channel then
                    local pkt = nil
                    if frame.protocol() == PROTOCOL.RPLC then
                        pkt = comms.rplc_container().decode(frame)
                    elseif frame.protocol() == PROTOCOL.SCADA_MGMT then
                        pkt = comms.mgmt_container().decode(frame)
                    end

                    if pkt then
                        -- while not linked, skip strict seq checking: the
                        -- supervisor ACKs every ESTABLISH retry (each with a
                        -- fresh seq), so out-of-order ACKs are normal during
                        -- the handshake. Only enforce seq once linked.
                        if not plc.linked then
                            handle_plc_packet(pkt)
                        elseif plc.r_seq_num == nil then
                            plc.r_seq_num = frame.seq_num() + 1
                            handle_plc_packet(pkt)
                        elseif plc.r_seq_num ~= frame.seq_num() then
                            log.warning(util.c(log_tag, "PLC seq out-of-order: next=", plc.r_seq_num, ", got=", frame.seq_num()))
                            -- sequence desync: close and re-establish
                            plc.linked = false
                            plc.r_seq_num = nil
                            plc.sv_addr = comms.BROADCAST
                        else
                            plc.r_seq_num = frame.seq_num() + 1
                            handle_plc_packet(pkt)
                        end
                    end
                elseif l_chan == config.RTU_Channel then
                    local pkt = nil
                    if frame.protocol() == PROTOCOL.MODBUS_TCP then
                        pkt = comms.modbus_container().decode(frame)
                    elseif frame.protocol() == PROTOCOL.SCADA_MGMT then
                        pkt = comms.mgmt_container().decode(frame)
                    end

                    if pkt then
                        -- while not linked, skip strict seq checking: the
                        -- supervisor ACKs every ESTABLISH retry (each with a
                        -- fresh seq), so out-of-order ACKs are normal during
                        -- the handshake. Only enforce seq once linked.
                        if not rtu.linked then
                            handle_rtu_packet(pkt)
                        elseif rtu.r_seq_num == nil then
                            rtu.r_seq_num = frame.seq_num() + 1
                            handle_rtu_packet(pkt)
                        elseif rtu.r_seq_num ~= frame.seq_num() then
                            log.warning(util.c(log_tag, "RTU seq out-of-order: next=", rtu.r_seq_num, ", got=", frame.seq_num()))
                            rtu.linked = false
                            rtu.r_seq_num = nil
                            rtu.sv_addr = comms.BROADCAST
                        else
                            rtu.r_seq_num = frame.seq_num() + 1
                            handle_rtu_packet(pkt)
                        end
                    end
                end
            end
        elseif event == "peripheral" then
            -- modem hot-plug: reconnect
            if param1 == modem_iface then
                log.info(log_tag .. "modem reattached")
                local _, dev = ppm.remount(param1)
                modem = dev
                nic.connect(modem)
                nic.closeAll()
                if plc.enabled then nic.open(config.PLC_Channel) end
                if rtu.enabled then nic.open(config.RTU_Channel) end
            end
        elseif event == "peripheral_detach" then
            if param1 == modem_iface then
                log.warning(log_tag .. "modem detached")
                nic.disconnect()
                ppm.handle_unmount(param1)
            end
        elseif event == "monitor_touch" or event == "mouse_click" or event == "mouse_up" or
               event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
            -- handle a mouse event for the front panel UI
            renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
        elseif event == "key" then
            -- keyboard events handled by the UI element tree
            renderer.handle_key(core.events.new_key_event(event, param1, param2))
        elseif event == "terminate" then
            break
        end
    end

    --#endregion
end

return sim
