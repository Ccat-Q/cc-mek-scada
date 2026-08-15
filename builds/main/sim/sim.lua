
local comms    = require("scada-common.comms")
local log      = require("scada-common.log")
local network  = require("scada-common.network")
local ppm      = require("scada-common.ppm")
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
function sim.load_config()
local loaded = settings.load("/sim.settings")
local config = {
SVR_Channel = settings.get("SVR_Channel") or 16240,
PLC_Channel = settings.get("PLC_Channel") or 16241,
RTU_Channel = settings.get("RTU_Channel") or 16242,
AuthKey = settings.get("AuthKey") or "",
TrustedRange = settings.get("TrustedRange") or 0,
SimulatePLC = settings.get("SimulatePLC") ~= false,
SimulateRTU = settings.get("SimulateRTU") ~= false,
UnitCount = settings.get("UnitCount") or 1,
BoilersPerUnit = settings.get("BoilersPerUnit") or 1,
TurbinesPerUnit = settings.get("TurbinesPerUnit") or 1,
ModemSide = settings.get("ModemSide") or nil,
PLCFirmware = settings.get("PLCFirmware") or ("sim-plc-" .. SIM_VERSION),
RTUFirmware = settings.get("RTUFirmware") or ("sim-rtu-" .. SIM_VERSION)
}
if not loaded then
config._unconfigured = true
end
if config.UnitCount < 1 or config.UnitCount > 4 then
log.error("SIM: invalid UnitCount " .. config.UnitCount .. " (must be 1-4)")
return nil
end
return config
end
function sim.run(config)
local log_tag = "sim: "
ppm.mount_all()
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
if config.AuthKey and #config.AuthKey > 0 then
log.info(log_tag .. "initializing message authentication")
network.init_mac(config.AuthKey)
end
if config.TrustedRange and config.TrustedRange > 0 then
comms.set_trusted_range(config.TrustedRange)
end
local nic = network.nic(modem, config.SVR_Channel)
nic.closeAll()
if config.SimulatePLC then nic.open(config.PLC_Channel) end
if config.SimulateRTU then nic.open(config.RTU_Channel) end
log.info(util.c(log_tag, "modem [", modem_iface, "] opened, SVR=", config.SVR_Channel,
" PLC=", config.PLC_Channel, " RTU=", config.RTU_Channel))
local facility = model.new_facility({
num_units = config.UnitCount,
boilers_per_unit = { config.BoilersPerUnit },
turbines_per_unit = { config.TurbinesPerUnit }
})
local plc = {
enabled = config.SimulatePLC,
linked = false,
sv_addr = comms.BROADCAST,
seq_num = util.time_ms() * 10,
r_seq_num = nil,
reactor_id = 1,
auto_ack_token = 0,
reportable_max_burn = false,
last_status_send = 0,
last_keepalive_send = 0,
resend_build = true
}
local rtu = {
enabled = config.SimulateRTU,
linked = false,
sv_addr = comms.BROADCAST,
seq_num = util.time_ms() * 10,
r_seq_num = nil,
txn_id = 0,
last_keepalive_send = 0
}
local function build_advertisement()
local advert = {}
local unit_count = config.UnitCount
for u = 1, unit_count do
for b = 1, config.BoilersPerUnit do
table.insert(advert, { RTU_UNIT_TYPE.BOILER_VALVE, b, u, nil })
end
for t = 1, config.TurbinesPerUnit do
table.insert(advert, { RTU_UNIT_TYPE.TURBINE_VALVE, t, u, nil })
end
end
table.insert(advert, { RTU_UNIT_TYPE.IMATRIX, 1, 0, nil })
return advert
end
local function boiler_registers(unit)
local boiler = unit.boilers[1]
return {
di = { function() return boiler.formed end },
ir = {
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
function() return boiler.state.temperature end,
function() return boiler.state.boil_rate end,
function() return boiler.state.env_loss end,
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
function() return turbine.state.flow_rate end,
function() return turbine.state.prod_rate end,
function() return turbine.state.steam_input_rate end,
function() return turbine.state.dumping_mode end,
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
local function matrix_registers(fac)
local matrix = fac.ess
return {
di = { function() return matrix.formed end },
ir = {
function() return matrix.build.length end,
function() return matrix.build.width end,
function() return matrix.build.height end,
function() return matrix.build.min_pos end,
function() return matrix.build.max_pos end,
function() return matrix.build.max_energy end,
function() return matrix.build.transfer_cap end,
function() return matrix.build.cells end,
function() return matrix.build.providers end,
function() return matrix.state.last_input end,
function() return matrix.state.last_output end,
function() return matrix.tanks.energy end,
function() return math.max(0, matrix.build.max_energy - matrix.tanks.energy) end,
function() return matrix.tanks.energy_fill end
}
}
end
local function get_registers(advert_index)
local count_boilers = config.BoilersPerUnit
local count_turbines = config.TurbinesPerUnit
local idx = advert_index
if idx <= config.UnitCount * count_boilers then
local unit_num = math.ceil(idx / count_boilers)
return boiler_registers(facility.units[unit_num])
else
idx = idx - config.UnitCount * count_boilers
if idx <= config.UnitCount * count_turbines then
local unit_num = math.ceil(idx / count_turbines)
return turbine_registers(facility.units[unit_num])
else
return matrix_registers(facility)
end
end
end
local function _send(role_channel, frame)
nic.transmit(config.SVR_Channel, role_channel, frame)
end
local function plc_send(packet_type, data)
local rplc = comms.rplc_container()
rplc.make(plc.reactor_id, packet_type, data)
local frame = comms.scada_frame()
frame.make(plc.sv_addr, plc.seq_num, PROTOCOL.RPLC, rplc.raw_packet())
_send(config.PLC_Channel, frame)
plc.seq_num = plc.seq_num + 1
end
local function plc_send_mgmt(msg_type, data)
local mgmt = comms.mgmt_container()
mgmt.make(msg_type, data)
local frame = comms.scada_frame()
frame.make(plc.sv_addr, plc.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
_send(config.PLC_Channel, frame)
plc.seq_num = plc.seq_num + 1
end
local function rtu_send_mgmt(msg_type, data)
local mgmt = comms.mgmt_container()
mgmt.make(msg_type, data)
local frame = comms.scada_frame()
frame.make(rtu.sv_addr, rtu.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
_send(config.RTU_Channel, frame)
rtu.seq_num = rtu.seq_num + 1
end
local function rtu_send_modbus(m_cnt)
local frame = comms.scada_frame()
frame.make(rtu.sv_addr, rtu.seq_num, PROTOCOL.MODBUS_TCP, m_cnt.raw_packet())
_send(config.RTU_Channel, frame)
rtu.seq_num = rtu.seq_num + 1
end
local function plc_send_status()
local unit = facility.units[plc.reactor_id]
local reactor = unit.reactor
local data = reactor.get_status_data()
local sys_status = {
util.time(),
data[1] and not reactor.tripped,
false,
true,
plc.auto_ack_token,
plc.reportable_max_burn,
reactor.status.heating_rate,
data
}
plc_send(RPLC_TYPE.STATUS, sys_status)
end
local function plc_send_struct()
local unit = facility.units[plc.reactor_id]
local reactor = unit.reactor
plc_send(RPLC_TYPE.MEK_STRUCT, reactor.get_struct_data())
plc.resend_build = false
end
local function plc_send_rps_status()
local unit = facility.units[plc.reactor_id]
local reactor = unit.reactor
local status = { reactor.tripped, reactor.trip_cause }
for _, state_bit in ipairs(reactor.get_rps_status()) do
table.insert(status, state_bit)
end
plc_send(RPLC_TYPE.RPS_STATUS, status)
end
local function modbus_read(regs, txn_id, unit_id, func_code, start, count)
local readings = {}
local list = nil
if func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
list = regs.di
elseif func_code == MODBUS_FCODE.READ_INPUT_REGS then
list = regs.ir
elseif func_code == MODBUS_FCODE.READ_COILS then
list = regs.coils_read
elseif func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
list = regs.hr
end
if list then
for i = start, start + count - 1 do
if list[i] then
table.insert(readings, list[i]())
else
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
local reply = comms.modbus_container()
reply.make(txn_id, unit_id, bit.bor(func_code, MODBUS_FCODE.ERROR_FLAG), { MODBUS_EXCODE.ILLEGAL_FUNCTION })
rtu_send_modbus(reply)
end
end
local function modbus_write(regs, txn_id, unit_id, func_code, start, values)
local ok = true
if func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
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
local reply = comms.modbus_container()
reply.make(txn_id, unit_id, func_code, {})
rtu_send_modbus(reply)
else
local reply = comms.modbus_container()
reply.make(txn_id, unit_id, bit.bor(func_code, MODBUS_FCODE.ERROR_FLAG), { MODBUS_EXCODE.ILLEGAL_DATA_ADDR })
rtu_send_modbus(reply)
end
end
local function handle_plc_packet(packet)
local protocol = packet.scada_frame.protocol()
if protocol == PROTOCOL.RPLC then
if packet.type == RPLC_TYPE.STATUS then
plc_send_status()
elseif packet.type == RPLC_TYPE.MEK_STRUCT then
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
if packet.type == MGMT_TYPE.ESTABLISH then
if packet.length >= 1 then
local est_ack = packet.data[1]
if est_ack == ESTABLISH_ACK.ALLOW then
if not plc.linked then
plc.linked = true
plc.sv_addr = packet.scada_frame.src_addr()
plc.r_seq_num = packet.scada_frame.seq_num() + 1
log.info(log_tag .. "PLC session established with supervisor @" .. plc.sv_addr)
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
end
end
end
local function handle_rtu_packet(packet)
local protocol = packet.scada_frame.protocol()
if protocol == PROTOCOL.MODBUS_TCP then
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
local values = {}
for i = 3, #packet.data do table.insert(values, packet.data[i]) end
modbus_write(regs, packet.txn_id, packet.unit_id, packet.func_code, start, values)
end
else
local reply = comms.modbus_container()
reply.make(packet.txn_id, packet.unit_id, bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG), { MODBUS_EXCODE.GATEWAY_PATH_UNAVAILABLE })
rtu_send_modbus(reply)
end
end
elseif protocol == PROTOCOL.SCADA_MGMT then
if packet.type == MGMT_TYPE.ESTABLISH then
if packet.length >= 1 then
local est_ack = packet.data[1]
if est_ack == ESTABLISH_ACK.ALLOW then
if not rtu.linked then
rtu.linked = true
rtu.sv_addr = packet.scada_frame.src_addr()
rtu.r_seq_num = packet.scada_frame.seq_num() + 1
log.info(log_tag .. "RTU session established with supervisor @" .. rtu.sv_addr)
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
elseif packet.type == MGMT_TYPE.RTU_ADVERT then
rtu_send_mgmt(MGMT_TYPE.RTU_ADVERT, build_advertisement())
end
end
end
local last_est = { plc = 0, rtu = 0 }
local ESTABLISH_RETRY_S = 2.0
local function try_establish()
local now = util.time()
if plc.enabled and not plc.linked and nic.is_network_up() and (now - last_est.plc) >= ESTABLISH_RETRY_S then
last_est.plc = now
log.info(log_tag .. "PLC ESTABLISH -> " .. plc.reactor_id)
plc_send_mgmt(MGMT_TYPE.ESTABLISH, { comms.version, config.PLCFirmware, DEVICE_TYPE.PLC, plc.reactor_id })
plc.seq_num = plc.seq_num - 1
end
if rtu.enabled and not rtu.linked and nic.is_network_up() and (now - last_est.rtu) >= ESTABLISH_RETRY_S then
last_est.rtu = now
log.info(log_tag .. "RTU ESTABLISH (advert)")
rtu_send_mgmt(MGMT_TYPE.ESTABLISH, { comms.version, config.RTUFirmware, DEVICE_TYPE.RTU, build_advertisement() })
rtu.seq_num = rtu.seq_num - 1
end
end
local function periodic_sends()
local now = util.time()
if plc.enabled and plc.linked and (now - plc.last_status_send) >= 1 then
plc.last_status_send = now
plc_send_status()
plc_send_rps_status()
if plc.resend_build then plc_send_struct() end
end
end
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
facility.update()
nic.periodic()
try_establish()
periodic_sends()
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
if not plc.linked then
handle_plc_packet(pkt)
elseif plc.r_seq_num == nil then
plc.r_seq_num = frame.seq_num() + 1
handle_plc_packet(pkt)
elseif plc.r_seq_num ~= frame.seq_num() then
log.warning(util.c(log_tag, "PLC seq out-of-order: next=", plc.r_seq_num, ", got=", frame.seq_num()))
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
elseif event == "terminate" then
break
end
end
end
return sim
