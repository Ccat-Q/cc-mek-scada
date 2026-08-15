--
-- SCADA Simulator: Facility Simulation Model
--
-- Simulates a Mekanism fission reactor facility without requiring real
-- Mekanism peripherals. Provides dynamically-evolving values for the reactor,
-- boilers, turbines, ESS (induction matrix), and waste processing chain so
-- that the SCADA supervisor/coordinator see realistic, self-consistent data.
--
-- The model is a simplified first-order physics model (temperature follows
-- burn rate, fuel depletes, waste accumulates, turbines convert steam to
-- power, ESS charges from turbine output). It is NOT intended to be a
-- numerically-exact Mekanism simulation; it exists so alarm/auto-control
-- logic in the supervisor behaves realistically.
--

local types = require("scada-common.types")

local model = {}

local FLUID = types.FLUID
local RPS_TRIP_CAUSE = types.RPS_TRIP_CAUSE

-- simple exponential approach toward a target
---@param current number
---@param target number
---@param rate number approach rate (0..1 per second)
---@param dt number elapsed seconds
---@return number new value
local function _approach(current, target, rate, dt)
    return current + (target - current) * math.min(1.0, rate * dt)
end

--#region Reactor Model

-- create a simulated fission reactor
---@param opts table configuration options
---@return table reactor model object
function model.new_reactor(opts)
    opts = opts or {}

    -- structural / build parameters (static)
    local max_burn = opts.max_burn or 1000.0          -- mB/t max burn rate
    local heat_capacity = opts.heat_capacity or 1400000.0  -- large so full-power temp stays realistic
    local fuel_capacity = opts.fuel_capacity or 1000000.0  -- mB
    local waste_capacity = opts.waste_capacity or 100000.0  -- mB
    local coolant_capacity = opts.coolant_capacity or 100000.0
    local hcoolant_capacity = opts.hcoolant_capacity or 100000.0
    local ccool_type = opts.ccool_type or FLUID.WATER -- "minecraft:water" or "mekanism:sodium"
    local self = {
        -- build
        build = {
            length = 5, width = 5, height = 4,
            min_pos = { x = 0, y = 1, z = 0 },
            max_pos = { x = 4, y = 4, z = 4 },
            heat_capacity = heat_capacity,
            fuel_assemblies = 100,
            fuel_surface_area = 1000,
            fuel_capacity = fuel_capacity,
            waste_capacity = waste_capacity,
            coolant_capacity = coolant_capacity,
            hcoolant_capacity = hcoolant_capacity,
            max_burn_rate = max_burn
        },

        -- dynamic status
        status = {
            active = false,              -- reactor activated (not scrammed)
            burn_rate = 0.0,             -- setpoint
            act_burn_rate = 0.0,         -- actual (lags setpoint)
            temp = 300.0,                -- K (ambient start)
            damage = 0.0,                -- 0-100
            boil_efficiency = 0.8,
            env_loss = 0.05,
            fuel = 800000.0,             -- mB
            fuel_fill = 0.8,
            waste = 0.0,                 -- mB
            waste_fill = 0.0,
            coolant = 80000.0,           -- mB
            coolant_fill = 0.8,
            hcoolant = 10000.0,          -- mB
            hcoolant_fill = 0.1,
            heating_rate = 0.0           -- RF/t equivalent
        },

        -- RPS state
        rps = {
            high_dmg = false, high_temp = false, low_cool = false,
            ex_waste = false, ex_hcool = false, fault = false,
            timeout = false, manual = false, automatic = false,
            sys_fail = false, force_dis = false
        },
        tripped = false,
        trip_cause = RPS_TRIP_CAUSE.OK,

        -- internal state
        temp_target = 300.0,             -- equilibrium temperature target
        _last_update = nil,              ---@type number|nil
        _startup_progress = 0.0          -- 0..1 startup ramp
    }

    --#region helpers

    -- get elapsed seconds since last update
    local function _dt()
        local now = os.epoch("utc") / 1000.0
        if self._last_update == nil then self._last_update = now end
        local dt = now - self._last_update
        self._last_update = now
        return math.min(dt, 2.0) -- clamp to avoid huge jumps after lag
    end

    -- update the reactor simulation
    function self.update()
        local dt = _dt()
        local st = self.status

        if st.active and st.act_burn_rate > 0 then
            -- reactor is running: temperature equilibrium follows burn rate,
            -- matching the supervisor's expected operational temperature
            -- (temp = BASE_BOIL + burn_rate * JOULES_PER_MB / heat_capacity)
            local JOULES_PER_MB = 1000000
            local equilibrium = 373.15 + (st.act_burn_rate * JOULES_PER_MB) / self.build.heat_capacity
            self.temp_target = equilibrium

            -- fuel consumption: burn rate in mB/t * 20 t/s
            local fuel_use = st.act_burn_rate * 20 * dt
            st.fuel = math.max(0, st.fuel - fuel_use)

            -- waste accumulation (roughly 1/10 of fuel by volume)
            local waste_prod = fuel_use * 0.1
            st.waste = math.min(self.build.waste_capacity, st.waste + waste_prod)

            -- waste export: the processing chain (SNA/plutonium) draws waste
            -- out at a rate proportional to burn rate, keeping it from filling
            local waste_export = fuel_use * 0.09
            st.waste = math.max(0, st.waste - waste_export)

            -- heating rate estimate (J/t, matches supervisor expectations)
            st.heating_rate = st.act_burn_rate * JOULES_PER_MB
        else
            -- reactor idle: temperature decays toward ambient
            self.temp_target = 300.0
            st.heating_rate = 0
        end

        -- temperature rises with the heating rate and cools toward ambient.
        -- Equilibrium temp matches the supervisor's expected operational temp:
        -- temp_eq = BASE_BOIL + burn_rate * JOULES_PER_MB / heat_cap.
        -- A proportional heat-out term with coefficient K makes the dynamics
        -- settle at that equilibrium: dT/dt = heat_in - K*(T - 300) with
        -- K = (max_burn * JOULES_PER_MB / heat_cap) / (max_op_temp - 300).
        if st.active and st.act_burn_rate > 0 then
            local JOULES_PER_MB = 1000000
            -- expected equilibrium at full power (~1000K operational)
            local max_op_temp = 373.15 + (self.build.max_burn_rate * JOULES_PER_MB) / self.build.heat_capacity
            local k_out = (self.build.max_burn_rate * JOULES_PER_MB / self.build.heat_capacity) / (max_op_temp - 300.0)
            local heat_in = (st.act_burn_rate * JOULES_PER_MB) / self.build.heat_capacity
            local heat_out = (st.temp - 300.0) * k_out
            st.temp = st.temp + (heat_in - heat_out) * dt
        else
            -- reactor idle: cool toward ambient
            st.temp = st.temp + (300.0 - st.temp) * 0.05 * dt
        end

        -- actual burn rate approaches setpoint (startup ramp)
        if st.active then
            local target = st.burn_rate
            -- warmup ramp: reach 10% immediately then ramp slower
            self._startup_progress = _approach(self._startup_progress, 1.0, 0.05, dt)
            target = target * self._startup_progress
            st.act_burn_rate = _approach(st.act_burn_rate, target, 0.1, dt)
            if st.act_burn_rate < 0.1 then st.act_burn_rate = 0 end
        else
            st.act_burn_rate = _approach(st.act_burn_rate, 0, 0.2, dt)
        end

        -- coolant: coolant level is affected by boiling (moves to boilers)
        -- heat removal: coolant heated by reactor heat, cooled by boiler return
        local coolant_drain = 0
        if st.active and st.act_burn_rate > 0 then
            coolant_drain = st.act_burn_rate * 20 * dt * 0.15
        end
        st.coolant = math.max(0, st.coolant - coolant_drain)
        -- boiler returns coolant (simplified: reactor draws from a loop)
        st.coolant = math.min(self.build.coolant_capacity, st.coolant + coolant_drain * 0.95)

        -- heated coolant builds up, converted in boilers
        st.hcoolant = math.min(self.build.hcoolant_capacity, st.hcoolant + coolant_drain)

        -- recompute fill percentages
        st.fuel_fill = st.fuel / self.build.fuel_capacity
        st.waste_fill = st.waste / self.build.waste_capacity
        st.coolant_fill = st.coolant / self.build.coolant_capacity
        st.hcoolant_fill = st.hcoolant / self.build.hcoolant_capacity

        -- damage from high temperature
        if st.temp >= 1200 then
            st.damage = math.min(100, st.damage + (st.temp - 1200) * 0.01 * dt)
        elseif st.damage > 0 then
            st.damage = math.max(0, st.damage - 0.1 * dt)
        end

        -- RPS state evaluation (mirrors reactor-plc/plc.lua checks)
        local r = self.rps
        r.high_dmg = st.damage >= 90
        r.high_temp = st.temp >= 1200
        r.low_cool = st.coolant_fill < 0.10
        r.ex_waste = st.waste_fill > 0.95
        r.ex_hcool = st.hcoolant_fill > 0.95

        -- trip evaluation
        if not self.tripped then
            if r.sys_fail then
                self.trip_cause = RPS_TRIP_CAUSE.SYS_FAIL
                self.tripped = true
            elseif r.high_dmg then
                self.trip_cause = RPS_TRIP_CAUSE.HIGH_DMG
                self.tripped = true
            elseif r.high_temp then
                self.trip_cause = RPS_TRIP_CAUSE.HIGH_TEMP
                self.tripped = true
            elseif r.low_cool then
                self.trip_cause = RPS_TRIP_CAUSE.LOW_COOLANT
                self.tripped = true
            elseif r.ex_waste then
                self.trip_cause = RPS_TRIP_CAUSE.EX_WASTE
                self.tripped = true
            elseif r.ex_hcool then
                self.trip_cause = RPS_TRIP_CAUSE.EX_HCOOLANT
                self.tripped = true
            end
        end

        -- when tripped, reactor scrammed automatically
        if self.tripped then
            st.active = false
            st.burn_rate = 0
        end
    end

    -- activate the reactor (enable)
    function self.activate()
        self.status.active = true
        self._startup_progress = 0.0
        if self.tripped then
            -- cannot activate a tripped reactor
            self.status.active = false
            return false
        end
        return true
    end

    -- SCRAM the reactor
    function self.scram()
        self.status.active = false
        self.status.burn_rate = 0
        self._startup_progress = 0.0
    end

    -- set the burn rate setpoint
    ---@param rate number mB/t
    ---@return boolean ok
    function self.set_burn_rate(rate)
        if self.tripped then return false end
        if rate < 0 or rate > self.build.max_burn_rate then return false end
        self.status.burn_rate = rate
        return true
    end

    -- reset the RPS trip
    function self.reset_rps()
        if self.tripped and self.trip_cause ~= RPS_TRIP_CAUSE.HIGH_DMG then
            self.tripped = false
            self.trip_cause = RPS_TRIP_CAUSE.OK
            self.status.damage = 0
        end
    end

    -- reset RPS if trip was only timeout/automatic
    function self.auto_reset_rps()
        if self.trip_cause == RPS_TRIP_CAUSE.TIMEOUT or self.trip_cause == RPS_TRIP_CAUSE.AUTOMATIC then
            self.tripped = false
            self.trip_cause = RPS_TRIP_CAUSE.OK
            return true
        end
        return false
    end

    -- get RPS status bits (11 booleans in fixed order)
    ---@return table status
    function self.get_rps_status()
        local r = self.rps
        return {
            r.high_dmg, r.high_temp, r.low_cool, r.ex_waste, r.ex_hcool,
            r.fault, r.timeout, r.manual, r.automatic, r.sys_fail, r.force_dis
        }
    end

    --#region data accessors (match reactor-plc/plc.lua)

    -- 17-element reactor status array
    ---@return table data
    function self.get_status_data()
        local st = self.status
        return {
            st.active,          -- [1] getStatus
            st.burn_rate,       -- [2] getBurnRate (setpoint)
            st.act_burn_rate,   -- [3] getActualBurnRate
            st.temp,            -- [4] getTemperature
            st.damage,          -- [5] getDamagePercent
            st.boil_efficiency, -- [6] getBoilEfficiency
            st.env_loss,        -- [7] getEnvironmentalLoss
            st.fuel,            -- [8] fuel amount
            st.fuel_fill,       -- [9] getFuelFilledPercentage
            st.waste,           -- [10] waste amount
            st.waste_fill,      -- [11] getWasteFilledPercentage
            ccool_type,         -- [12] coolant name
            st.coolant,         -- [13] coolant amount
            st.coolant_fill,    -- [14] getCoolantFilledPercentage
            FLUID.SUPERHEATED_SODIUM, -- [15] heated coolant name
            st.hcoolant,        -- [16] heated coolant amount
            st.hcoolant_fill    -- [17] getHeatedCoolantFilledPercentage
        }
    end

    -- 13-element structure array
    ---@return table data
    function self.get_struct_data()
        local b = self.build
        return {
            b.length, b.width, b.height,
            b.min_pos, b.max_pos,
            b.heat_capacity, b.fuel_assemblies, b.fuel_surface_area,
            b.fuel_capacity, b.waste_capacity,
            b.coolant_capacity, b.hcoolant_capacity,
            b.max_burn_rate
        }
    end

    --#endregion

    return self
end

--#endregion

--#region Boiler Model

-- create a simulated boiler
---@return table boiler model object
function model.new_boiler()
    local build = {
        length = 3, width = 3, height = 18,
        min_pos = { x = 0, y = 1, z = 0 }, max_pos = { x = 2, y = 18, z = 2 },
        boil_cap = 50000.0, steam_cap = 200000.0,
        water_cap = 200000.0, hcoolant_cap = 100000.0, ccoolant_cap = 100000.0,
        superheaters = 16, max_boil_rate = 50000.0
    }

    local self = {
        build = build,
        formed = true,
        state = {
            temperature = 300.0,
            boil_rate = 0.0,
            env_loss = 0.05
        },
        tanks = {
            steam = 10000.0, steam_fill = 0.05,
            water = 180000.0, water_fill = 0.9,
            hcool = 10000.0, hcool_fill = 0.1,
            ccool = 90000.0, ccool_fill = 0.9
        }
    }

    -- update boiler based on reactor state
    function self.update(reactor, dt)
        -- boiler temperature follows reactor temperature
        self.state.temperature = _approach(self.state.temperature, reactor.status.temp, 0.1, dt)

        if reactor.status.active and reactor.status.act_burn_rate > 0 then
            -- boiling rate scales with reactor heat
            local max_rate = build.max_boil_rate
            local rate = (reactor.status.act_burn_rate / reactor.build.max_burn_rate) * max_rate
            self.state.boil_rate = rate

            -- steam produced, water consumed
            local steam_prod = rate * dt * 0.01
            self.tanks.steam = math.min(build.steam_cap, self.tanks.steam + steam_prod)
            self.tanks.water = math.max(0, self.tanks.water - steam_prod * 0.9)
            -- water replenished (simplified: water input)
            self.tanks.water = math.min(build.water_cap, self.tanks.water + steam_prod * 0.8)

            -- heat exchange: draws heated coolant from the reactor, converts
            -- to cooled coolant; keeps the reactor's hcoolant from filling up
            local exchange = steam_prod * 0.05
            reactor.status.hcoolant = math.max(0, reactor.status.hcoolant - exchange)
            self.tanks.hcool = math.min(build.hcoolant_cap, self.tanks.hcool + exchange)
            self.tanks.ccool = math.min(build.ccoolant_cap, self.tanks.ccool + exchange * 0.9)
            -- cooled coolant returns to the reactor as coolant
            reactor.status.coolant = math.min(reactor.build.coolant_capacity,
                reactor.status.coolant + exchange * 0.85)
        else
            -- boiler idle: boil rate falls off
            self.state.boil_rate = _approach(self.state.boil_rate, 0, 0.1, dt)
        end

        -- recompute fills
        self.tanks.steam_fill = self.tanks.steam / build.steam_cap
        self.tanks.water_fill = self.tanks.water / build.water_cap
        self.tanks.hcool_fill = self.tanks.hcool / build.hcoolant_cap
        self.tanks.ccool_fill = self.tanks.ccool / build.ccoolant_cap
    end

    return self
end

--#endregion

--#region Turbine Model

-- create a simulated turbine
---@return table turbine model object
function model.new_turbine()
    local build = {
        length = 5, width = 5, height = 8,
        min_pos = { x = 0, y = 1, z = 0 }, max_pos = { x = 4, y = 8, z = 4 },
        blades = 2, coils = 4, vents = 12, dispersers = 20, condensers = 40,
        steam_cap = 200000.0, max_energy = 100000000.0,
        max_flow_rate = 100000.0, max_production = 500000.0, max_water_output = 100000.0
    }

    local dumping = { IDLE = "IDLE", DUMPING = "DUMPING", DUMPING_EXCESS = "DUMPING_EXCESS" }

    local self = {
        build = build,
        formed = true,
        state = {
            flow_rate = 0.0,
            prod_rate = 0.0,
            steam_input_rate = 0.0,
            dumping_mode = dumping.IDLE
        },
        tanks = {
            steam = 10000.0, steam_fill = 0.05,
            energy = 0.0, energy_fill = 0.0
        },
        dumping = dumping
    }

    -- update turbine based on reactor/boiler state
    function self.update(reactor, boiler_steam_input, dt)
        if reactor.status.active and reactor.status.act_burn_rate > 0 then
            -- steam input from boiler (or direct reactor heating if no boilers)
            self.state.steam_input_rate = boiler_steam_input

            -- flow follows steam input
            self.state.flow_rate = _approach(self.state.flow_rate, boiler_steam_input, 0.1, dt)
            self.state.flow_rate = math.min(self.state.flow_rate, build.max_flow_rate)

            -- power production from flow
            local prod = (self.state.flow_rate / build.max_flow_rate) * build.max_production
            self.state.prod_rate = prod

            -- steam consumed, energy produced
            local steam_use = self.state.flow_rate * dt * 0.01
            self.tanks.steam = math.max(0, self.tanks.steam - steam_use)
            self.tanks.energy = math.min(build.max_energy, self.tanks.energy + prod * dt * 20)

            -- if dumping, vent steam
            if self.state.dumping_mode ~= dumping.IDLE then
                self.tanks.steam = math.max(0, self.tanks.steam - steam_use * 0.5)
            end
        else
            self.state.flow_rate = _approach(self.state.flow_rate, 0, 0.1, dt)
            self.state.prod_rate = _approach(self.state.prod_rate, 0, 0.1, dt)
            self.state.steam_input_rate = 0
        end

        self.tanks.steam_fill = self.tanks.steam / build.steam_cap
        self.tanks.energy_fill = self.tanks.energy / build.max_energy
    end

    return self
end

--#endregion

--#region ESS (Induction Matrix) Model

-- create a simulated induction matrix (energy storage system)
---@return table matrix model object
function model.new_matrix()
    local build = {
        length = 3, width = 3, height = 3,
        min_pos = { x = 0, y = 1, z = 0 }, max_pos = { x = 2, y = 3, z = 2 },
        max_energy = 1000000000.0,      -- J
        transfer_cap = 10000000.0,       -- J/t
        cells = 8, providers = 8
    }

    local self = {
        build = build,
        formed = true,
        state = {
            last_input = 0.0,
            last_output = 0.0
        },
        tanks = {
            energy = 500000000.0,  -- J
            energy_fill = 0.5
        }
    }

    -- update ESS from turbine power
    function self.update(turbines, dt)
        local total_power = 0
        for _, turbine in ipairs(turbines) do
            total_power = total_power + turbine.state.prod_rate
        end

        -- input from turbines (J/t), output to a load
        local input_j = total_power * 20  -- convert RF/t to J/t equivalent
        local output_j = build.transfer_cap * 0.3  -- constant load

        self.state.last_input = input_j
        self.state.last_output = output_j

        local net = (input_j - output_j) * dt
        self.tanks.energy = math.max(0, math.min(build.max_energy, self.tanks.energy + net))
        self.tanks.energy_fill = self.tanks.energy / build.max_energy
    end

    return self
end

--#endregion

--#region SPS Model

-- create a simulated SPS (supercritical phase shifter)
---@return table sps model object
function model.new_sps()
    local build = {
        length = 3, width = 3, height = 5,
        min_pos = { x = 0, y = 1, z = 0 }, max_pos = { x = 2, y = 5, z = 2 },
        coils = 8, input_cap = 100000.0, output_cap = 100000.0,
        max_energy = 100000000.0
    }

    local self = {
        build = build,
        formed = true,
        state = {
            process_rate = 0.0
        },
        tanks = {
            input = 50000.0, input_fill = 0.5,
            output = 50000.0, output_fill = 0.5,
            energy = 50000000.0, energy_fill = 0.5
        }
    }

    -- update SPS (processes polonium from SNA into antimatter)
    function self.update(reactor, dt)
        if reactor.status.active and reactor.status.act_burn_rate > 0 then
            -- process rate follows reactor burn rate
            self.state.process_rate = (reactor.status.act_burn_rate / reactor.build.max_burn_rate) * 100

            -- input consumed, output produced
            local proc = self.state.process_rate * dt * 0.01
            self.tanks.input = math.max(0, self.tanks.input - proc)
            self.tanks.output = math.min(build.output_cap, self.tanks.output + proc * 0.5)
            -- input replenished by the SNA chain
            self.tanks.input = math.min(build.input_cap, self.tanks.input + proc * 0.4)
        else
            self.state.process_rate = _approach(self.state.process_rate, 0, 0.1, dt)
        end

        self.tanks.input_fill = self.tanks.input / build.input_cap
        self.tanks.output_fill = self.tanks.output / build.output_cap
    end

    return self
end

--#endregion

--#region Facility Model

-- create a full simulated facility: reactors, boilers, turbines, ESS
---@param config table simulation configuration
---@return table facility model object
function model.new_facility(config)
    local num_units = config.num_units or 1

    local self = {
        num_units = num_units,
        units = {},      ---@type table[]
        ess = nil        ---@type table
    }

    -- create ESS and SPS
    self.ess = model.new_matrix()
    self.sps = model.new_sps()

    -- create units (each: reactor + boilers + turbines)
    for i = 1, num_units do
        local reactor = model.new_reactor(config.reactor_opts)

        local unit = {
            id = i,
            reactor = reactor,
            boilers = {},  ---@type table[]
            turbines = {}  ---@type table[]
        }

        -- default: 1 boiler, 1 turbine per unit (configurable via opts)
        local n_boilers = 1
        local n_turbines = 1
        if config.boilers_per_unit then n_boilers = config.boilers_per_unit[i] or 1 end
        if config.turbines_per_unit then n_turbines = config.turbines_per_unit[i] or 1 end

        for _ = 1, n_boilers do
            table.insert(unit.boilers, model.new_boiler())
        end

        for _ = 1, n_turbines do
            table.insert(unit.turbines, model.new_turbine())
        end

        table.insert(self.units, unit)
    end

    -- update all model components
    function self.update()
        local dt = 0.05 -- nominal step; individual models track their own time

        for _, unit in ipairs(self.units) do
            unit.reactor.update()

            -- boiler steam output drives turbine steam input
            local boiler_steam = 0
            for _, boiler in ipairs(unit.boilers) do
                boiler.update(unit.reactor, dt)
                boiler_steam = boiler_steam + boiler.state.boil_rate
            end

            -- if no boilers, turbine gets steam directly from reactor heating
            if #unit.boilers == 0 then
                boiler_steam = unit.reactor.status.heating_rate * 0.01
            end

            for _, turbine in ipairs(unit.turbines) do
                turbine.update(unit.reactor, boiler_steam, dt)
            end
        end

        -- update ESS from all turbines
        local all_turbines = {}
        for _, unit in ipairs(self.units) do
            for _, turbine in ipairs(unit.turbines) do
                table.insert(all_turbines, turbine)
            end
        end
        self.ess.update(all_turbines, dt)

        -- update SPS from the first reactor
        local first_reactor = self.units[1] and self.units[1].reactor
        if first_reactor then self.sps.update(first_reactor, dt) end
    end

    return self
end

--#endregion

return model
