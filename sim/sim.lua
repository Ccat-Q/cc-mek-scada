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
local types    = require("scada-common.types")
local util     = require("scada-common.util")

local model    = require("sim.model")

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
        UnitCount = settings.get("UnitCount") or 1,          -- luacheck: ignore settings
        BoilersPerUnit = settings.get("BoilersPerUnit") or 1, -- luacheck: ignore settings
        TurbinesPerUnit = settings.get("TurbinesPerUnit") or 1, -- luacheck: ignore settings
        -- modem
        ModemSide = settings.get("ModemSide") or nil,        -- luacheck: ignore settings
        -- firmware IDs for establish
        PLCFirmware = settings.get("PLCFirmware") or ("sim-plc-" .. SIM_VERSION), -- luacheck: ignore settings
        RTUFirmware = settings.get("RTUFirmware") or ("sim-rtu-" .. SIM_VERSION) -- luacheck: ignore settings
    }

    -- validate
    local valid = true
    if config.SimulatePLC and not (config.SimulateRTU) then valid = true end

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

    -- find the modem
    local modem, modem_iface
    if config.ModemSide then
        if peripheral.isPresent(config.ModemSide) then
            modem = peripheral.wrap(config.ModemSide)
            modem_iface = config.ModemSide
        end
    end
    if not modem then
        modem, modem_iface = peripheral.find("modem")
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

    --#region Session State

    -- PLC session state
    local plc = {
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
    local rtu = {
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
                function() return types.new_tank_fluid("mekanism:energy", turbine.tanks.energy) end,
                function() return math.max(0, turbine.build.max_energy - turbine.tanks.energy) end,
                function() return turbine.tanks.energy_fill end
            },
            hr = {
                { read = function() return turbine.state.dumping_mode end,
                  write = function(v) turbine.state.dumping_mode = v end }
            }
        }
    end

    local function matrix_registers(facility)
        local matrix = facility.ess
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

    -- map an advert entry to its register map
    local function get_registers(advert_index)
        -- advert order: per-unit boilers, per-unit turbines, facility matrix
        local count_boilers = config.BoilersPerUnit
        local count_turbines = config.TurbinesPerUnit
        local per_unit = count_boilers + count_turbines

        local idx = advert_index

        if idx <= config.UnitCount * count_boilers then
            -- boiler: unit = ceil(idx / boilers_per_unit)
            local unit_num = math.ceil(idx / count_boilers)
            return boiler_registers(facility.units[unit_num])
        else
            idx = idx - config.UnitCount * count_boilers
            if idx <= config.UnitCount * count_turbines then
                local unit_num = math.ceil(idx / count_turbines)
                return turbine_registers(facility.units[unit_num])
            else
                -- facility matrix (last)
                return matrix_registers(facility)
            end
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
    local function modbus_read(adu, regs, txn_id, unit_id, func_code, start, count)
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
    local function modbus_write(adu, regs, txn_id, unit_id, func_code, start, values)
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
                        plc.linked = true
                        plc.sv_addr = packet.scada_frame.src_addr()
                        plc.r_seq_num = packet.scada_frame.seq_num() + 1
                        log.info(log_tag .. "PLC session established with supervisor @" .. plc.sv_addr)

                        -- send initial status/struct/rps to get supervisor out of retry
                        plc_send_status()
                        plc_send_struct()
                        plc_send_rps_status()
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
                        modbus_read(packet, regs, packet.txn_id, packet.unit_id, packet.func_code, start, packet.data[2])
                    else
                        -- write request: data = {start, values...}
                        local values = {}
                        for i = 3, #packet.data do table.insert(values, packet.data[i]) end
                        modbus_write(packet, regs, packet.txn_id, packet.unit_id, packet.func_code, start, values)
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
                        rtu.linked = true
                        rtu.sv_addr = packet.scada_frame.src_addr()
                        rtu.r_seq_num = packet.scada_frame.seq_num() + 1
                        log.info(log_tag .. "RTU session established with supervisor @" .. rtu.sv_addr)
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
            elseif packet.type == MGMT_TYPE.RTU_ADVERT then
                -- supervisor requests capabilities again
                rtu_send_mgmt(MGMT_TYPE.RTU_ADVERT, build_advertisement())
            end
        end
    end

    --#endregion

    --#region Main Loop

    -- periodic link attempts
    local function try_establish()
        if plc.enabled and not plc.linked and nic.is_network_up() then
            plc_send_mgmt(MGMT_TYPE.ESTABLISH, { comms.version, config.PLCFirmware, DEVICE_TYPE.PLC, plc.reactor_id })
        end

        if rtu.enabled and not rtu.linked and nic.is_network_up() then
            rtu_send_mgmt(MGMT_TYPE.ESTABLISH, { comms.version, config.RTUFirmware, DEVICE_TYPE.RTU, build_advertisement() })
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

    -- main loop
    local last_loop = 0
    while true do
        -- process events
        local event_data = { os.pullEvent() }
        local event = event_data[1]

        -- periodics (throttled to ~10Hz)
        local now = util.time()
        if (now - last_loop) >= 0.1 then
            last_loop = now

            -- update the facility model
            facility.update()

            -- NIC link-layer discovery
            nic.periodic()

            -- attempt establishes if not linked
            try_establish()

            -- periodic pushes
            periodic_sends()
        end

        -- handle events
        if event == "modem_message" then
            local side, sender, reply_to, message, distance =
                event_data[2], event_data[3], event_data[4], event_data[5], event_data[6]

            local frame = nic.receive(side, sender, reply_to, message, distance)

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
                        -- check sequence number for PLC session
                        if plc.r_seq_num == nil then
                            plc.r_seq_num = frame.seq_num() + 1
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
                        -- check sequence number for RTU session
                        if rtu.r_seq_num == nil then
                            rtu.r_seq_num = frame.seq_num() + 1
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
            local iface = event_data[2]
            if iface == modem_iface then
                log.info(log_tag .. "modem reattached")
                modem = peripheral.wrap(iface)
                nic.connect(modem)
                nic.closeAll()
                if plc.enabled then nic.open(config.PLC_Channel) end
                if rtu.enabled then nic.open(config.RTU_Channel) end
            end
        elseif event == "peripheral_detach" then
            local iface = event_data[2]
            if iface == modem_iface then
                log.warning(log_tag .. "modem detached")
                nic.disconnect()
            end
        elseif event == "terminate" then
            break
        end
    end

    --#endregion
end

return sim
