
local util = require("scada-common.util")
local rsio = {}
local IO_LVL = {
DISCONNECT = -1,
LOW = 0,
HIGH = 1,
FLOATING = 2
}
local IO_DIR = {
IN = 0,
OUT = 1
}
local IO_MODE = {
DIGITAL_IN = 0,
DIGITAL_OUT = 1,
ANALOG_IN = 2,
ANALOG_OUT = 3
}
local IO_PORT = {
F_SCRAM       = 1,
F_ACK         = 2,
R_SCRAM       = 3,
R_RESET       = 4,
R_ENABLE      = 5,
U_ACK         = 6,
F_ALARM       = 7,
F_ALARM_ANY   = 8,
F_CHARGE_LOW  = 27,
F_CHARGE_HIGH = 28,
F_WASTE_PU    = 31,
F_WASTE_PO    = 32,
F_WASTE_POPL  = 33,
F_WASTE_AM    = 34,
U_ALARM       = 25,
U_EMER_COOL   = 26,
U_AUX_COOL    = 30,
U_WASTE_PU    = 9,
U_WASTE_PO    = 10,
U_WASTE_POPL  = 11,
U_WASTE_AM    = 12,
R_ACTIVE      = 13,
R_AUTO_CTRL   = 14,
R_SCRAMMED    = 15,
R_AUTO_SCRAM  = 16,
R_HIGH_DMG    = 17,
R_HIGH_TEMP   = 18,
R_LOW_COOLANT = 19,
R_EXCESS_HC   = 20,
R_EXCESS_WS   = 21,
R_INSUFF_FUEL = 22,
R_PLC_FAULT   = 23,
R_PLC_TIMEOUT = 24,
F_ENERGY_CHG  = 29
}
rsio.IO_LVL = IO_LVL
rsio.IO_DIR = IO_DIR
rsio.IO_MODE = IO_MODE
rsio.IO = IO_PORT
rsio.NUM_PORTS = 34
rsio.NUM_DIG_PORTS = 33
rsio.NUM_ANA_PORTS = 1
assert(rsio.NUM_PORTS == (rsio.NUM_DIG_PORTS + rsio.NUM_ANA_PORTS), "port counts inconsistent")
local dup_chk = {}
for _, v in pairs(IO_PORT) do
assert(dup_chk[v] ~= true, "duplicate in port list")
dup_chk[v] = true
end
assert(#dup_chk == rsio.NUM_PORTS, "port list malformed")
local IO = IO_PORT
local PORT_NAMES = {}
for k, v in pairs(IO) do PORT_NAMES[v] = k end
local MODES = {
[IO.F_SCRAM]       = IO_MODE.DIGITAL_IN,
[IO.F_ACK]         = IO_MODE.DIGITAL_IN,
[IO.R_SCRAM]       = IO_MODE.DIGITAL_IN,
[IO.R_RESET]       = IO_MODE.DIGITAL_IN,
[IO.R_ENABLE]      = IO_MODE.DIGITAL_IN,
[IO.U_ACK]         = IO_MODE.DIGITAL_IN,
[IO.F_ALARM]       = IO_MODE.DIGITAL_OUT,
[IO.F_ALARM_ANY]   = IO_MODE.DIGITAL_OUT,
[IO.F_CHARGE_LOW]  = IO_MODE.DIGITAL_OUT,
[IO.F_CHARGE_HIGH] = IO_MODE.DIGITAL_OUT,
[IO.F_WASTE_PU]    = IO_MODE.DIGITAL_OUT,
[IO.F_WASTE_PO]    = IO_MODE.DIGITAL_OUT,
[IO.F_WASTE_POPL]  = IO_MODE.DIGITAL_OUT,
[IO.F_WASTE_AM]    = IO_MODE.DIGITAL_OUT,
[IO.U_ALARM]       = IO_MODE.DIGITAL_OUT,
[IO.U_EMER_COOL]   = IO_MODE.DIGITAL_OUT,
[IO.U_AUX_COOL]    = IO_MODE.DIGITAL_OUT,
[IO.U_WASTE_PU]    = IO_MODE.DIGITAL_OUT,
[IO.U_WASTE_PO]    = IO_MODE.DIGITAL_OUT,
[IO.U_WASTE_POPL]  = IO_MODE.DIGITAL_OUT,
[IO.U_WASTE_AM]    = IO_MODE.DIGITAL_OUT,
[IO.R_ACTIVE]      = IO_MODE.DIGITAL_OUT,
[IO.R_AUTO_CTRL]   = IO_MODE.DIGITAL_OUT,
[IO.R_SCRAMMED]    = IO_MODE.DIGITAL_OUT,
[IO.R_AUTO_SCRAM]  = IO_MODE.DIGITAL_OUT,
[IO.R_HIGH_DMG]    = IO_MODE.DIGITAL_OUT,
[IO.R_HIGH_TEMP]   = IO_MODE.DIGITAL_OUT,
[IO.R_LOW_COOLANT] = IO_MODE.DIGITAL_OUT,
[IO.R_EXCESS_HC]   = IO_MODE.DIGITAL_OUT,
[IO.R_EXCESS_WS]   = IO_MODE.DIGITAL_OUT,
[IO.R_INSUFF_FUEL] = IO_MODE.DIGITAL_OUT,
[IO.R_PLC_FAULT]   = IO_MODE.DIGITAL_OUT,
[IO.R_PLC_TIMEOUT] = IO_MODE.DIGITAL_OUT,
[IO.F_ENERGY_CHG]  = IO_MODE.ANALOG_OUT
}
assert(rsio.NUM_PORTS == #PORT_NAMES, "port names length incorrect")
assert(rsio.NUM_PORTS == #MODES, "modes length incorrect")
function rsio.to_string(port)
if util.is_int(port) and port > 0 and port <= #PORT_NAMES then
return PORT_NAMES[port]
else return "UNKNOWN" end
end
local _B_AND = bit.band
local function _I_ACTIVE_HIGH(level) return level == IO_LVL.HIGH end
local function _I_ACTIVE_LOW(level) return level == IO_LVL.LOW end
local function _O_ACTIVE_HIGH(active) if active then return IO_LVL.HIGH else return IO_LVL.LOW end end
local function _O_ACTIVE_LOW(active) if active then return IO_LVL.LOW else return IO_LVL.HIGH end end
local RS_DIO_MAP = {
[IO.F_SCRAM]       = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.IN  },
[IO.F_ACK]         = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },
[IO.R_SCRAM]       = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.IN  },
[IO.R_RESET]       = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },
[IO.R_ENABLE]      = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },
[IO.U_ACK]         = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },
[IO.F_ALARM]       = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.F_ALARM_ANY]   = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.F_CHARGE_LOW]  = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.F_CHARGE_HIGH] = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.F_WASTE_PU]    = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.F_WASTE_PO]    = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.F_WASTE_POPL]  = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.F_WASTE_AM]    = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.U_ALARM]       = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.U_EMER_COOL]   = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.U_AUX_COOL]    = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.U_WASTE_PU]    = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.U_WASTE_PO]    = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.U_WASTE_POPL]  = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.U_WASTE_AM]    = { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
[IO.R_ACTIVE]      = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_AUTO_CTRL]   = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_SCRAMMED]    = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_AUTO_SCRAM]  = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_HIGH_DMG]    = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_HIGH_TEMP]   = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_LOW_COOLANT] = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_EXCESS_HC]   = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_EXCESS_WS]   = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_INSUFF_FUEL] = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_PLC_FAULT]   = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
[IO.R_PLC_TIMEOUT] = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT }
}
assert(rsio.NUM_DIG_PORTS == util.table_len(RS_DIO_MAP), "RS_DIO_MAP length incorrect")
function rsio.get_io_dir(port)
if rsio.is_valid_port(port) then
return util.trinary(MODES[port] == IO_MODE.DIGITAL_OUT or MODES[port] == IO_MODE.ANALOG_OUT, IO_DIR.OUT, IO_DIR.IN)
else return IO_DIR.IN end
end
function rsio.get_io_mode(port)
if rsio.is_valid_port(port) then return MODES[port]
else return IO_MODE.ANALOG_IN end
end
local RS_SIDES = rs.getSides()
function rsio.is_valid_port(port)
return util.is_int(port) and port > 0 and port <= rsio.NUM_PORTS
end
function rsio.is_valid_side(side)
if side ~= nil then
for i = 0, #RS_SIDES do
if RS_SIDES[i] == side then return true end
end
end
return false
end
function rsio.is_color(color)
return util.is_int(color) and (color > 0) and (_B_AND(color, (color - 1)) == 0)
end
function rsio.color_name(color)
local color_name_map = { [colors.red] = "red", [colors.orange] = "orange", [colors.yellow] = "yellow", [colors.lime] = "lime", [colors.green] = "green", [colors.cyan] = "cyan", [colors.lightBlue] = "lightBlue", [colors.blue] = "blue", [colors.purple] = "purple", [colors.magenta] = "magenta", [colors.pink] = "pink", [colors.white] = "white", [colors.lightGray] = "lightGray", [colors.gray] = "gray", [colors.black] = "black", [colors.brown] = "brown" }
if rsio.is_color(color) then
return color_name_map[color]
else return "unknown" end
end
function rsio.is_digital(port)
return rsio.is_valid_port(port) and (MODES[port] == IO_MODE.DIGITAL_IN or MODES[port] == IO_MODE.DIGITAL_OUT)
end
function rsio.digital_read(rs_value)
if rs_value then return IO_LVL.HIGH else return IO_LVL.LOW end
end
function rsio.digital_write(level) return level == IO_LVL.HIGH end
function rsio.digital_write_active(port, active)
if not rsio.is_digital(port) then
return false
else
return RS_DIO_MAP[port]._out(active)
end
end
function rsio.digital_is_active(port, level)
if (not rsio.is_digital(port)) or level == IO_LVL.FLOATING or level == IO_LVL.DISCONNECT then
return nil
else
return RS_DIO_MAP[port]._in(level)
end
end
function rsio.is_analog(port)
return rsio.is_valid_port(port) and (MODES[port] == IO_MODE.ANALOG_IN or MODES[port] == IO_MODE.ANALOG_OUT)
end
function rsio.analog_read(rs_value, min, max)
local value = rs_value / 15
return (value * (max - min)) + min
end
function rsio.analog_write(value, min, max)
local scaled_value = (value - min) / (max - min)
return math.floor(scaled_value * 15)
end
return rsio
