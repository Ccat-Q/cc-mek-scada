
local log = require("scada-common.log")
local type     = type
local insert   = table.insert
local TYPE_NUM = "number"
local TYPE_STR = "string"
local TYPE_TBL = "table"
local COMPUTER_ID = os.getComputerID()
local max_distance = nil
local comms = {}
comms.version = "3.4.0"
comms.api_version = "0.1.4"
local PROTOCOL = {
MODBUS_TCP = 0,      -- the "MODBUS TCP"-esque protocol
RPLC = 1,
SCADA_MGMT = 2,
SCADA_CRDN = 3
}
local RPLC_TYPE = {
STATUS = 0,
MEK_STRUCT = 1,
MEK_BURN_RATE = 2,
RPS_ENABLE = 3,
RPS_DISABLE = 4,
RPS_SCRAM = 5,
RPS_ASCRAM = 6,
RPS_STATUS = 7,
RPS_ALARM = 8,
RPS_RESET = 9,
RPS_AUTO_RESET = 10,
AUTO_BURN_RATE = 11
}
local MGMT_TYPE = {
ESTABLISH = 0,
KEEP_ALIVE = 1,
CLOSE = 2,
SWITCH_NET = 3,
RTU_ADVERT = 4,
RTU_DEV_REMOUNT = 5,
RTU_TONE_ALARM = 6,
DIAG_TONE_GET = 7,
DIAG_TONE_SET = 8,
DIAG_ALARM_SET = 9,
INFO_LIST_CMP = 10
}
local CRDN_TYPE = {
INITIAL_BUILDS = 0,
PROCESS_READY = 1,
FAC_BUILDS = 2,
FAC_STATUS = 3,
FAC_CMD = 4,
UNIT_BUILDS = 5,
UNIT_STATUSES = 6,
UNIT_CMD = 7,
API_GET_FAC = 8,
API_GET_FAC_DTL = 9,
API_GET_UNIT = 10,
API_GET_CTRL = 11,
API_GET_PROC = 12,
API_GET_WASTE = 13,
API_GET_RAD = 14
}
local ESTABLISH_ACK = {
ALLOW = 0,
DENY = 1,
COLLISION = 2,
BAD_VERSION = 3,
BAD_API_VERSION = 4
}
local DEVICE_TYPE = { PLC = 0, RTU = 1, SVR = 2, CRD = 3, PKT = 4 }
local PLC_AUTO_ACK = {
FAIL = 0,
DIRECT_SET_OK = 1,
RAMP_SET_OK = 2,
ZERO_DIS_OK = 3
}
local FAC_COMMAND = {
SCRAM_ALL = 0,
STOP = 1,
START = 2,
ACK_ALL_ALARMS = 3,
SET_WASTE_MODE = 4,
SET_PU_FB = 5,
SET_SPS_LP = 6
}
local UNIT_COMMAND = {
SCRAM = 0,
START = 1,
RESET_RPS = 2,
SET_BURN = 3,
SET_WASTE = 4,
ACK_ALL_ALARMS = 5,
ACK_ALARM = 6,
RESET_ALARM = 7,
SET_GROUP = 8
}
comms.PROTOCOL = PROTOCOL
comms.RPLC_TYPE = RPLC_TYPE
comms.MGMT_TYPE = MGMT_TYPE
comms.CRDN_TYPE = CRDN_TYPE
comms.ESTABLISH_ACK = ESTABLISH_ACK
comms.DEVICE_TYPE = DEVICE_TYPE
comms.PLC_AUTO_ACK = PLC_AUTO_ACK
comms.UNIT_COMMAND = UNIT_COMMAND
comms.FAC_COMMAND = FAC_COMMAND
comms.BROADCAST = -1
comms.CONN_TEST_FWV = "CONN_TEST"
function comms.set_trusted_range(distance)
if distance == 0 then max_distance = nil else max_distance = distance end
end
function comms.lld_frame()
local self = {
modem_frame = nil,
valid = false,
raw = {},
src_addr  = nil,
dest_addr = nil,
ack       = false
}
local public = {}
function public.make(dest_addr, ack)
self.valid = true
self.src_addr  = COMPUTER_ID
self.dest_addr = dest_addr
self.ack       = ack
self.raw = { COMPUTER_ID, dest_addr, ack }
end
function public.receive(side, sender, reply_to, message, distance)
self.modem_frame = {
iface = side, s_chan = sender, r_chan = reply_to, dist = distance, data = message
}
self.valid = false
self.raw   = self.modem_frame.data
if (type(max_distance) == TYPE_NUM) and (type(distance) == TYPE_NUM) and (distance > max_distance) then
elseif type(self.raw) == TYPE_TBL then
self.src_addr  = self.raw[1]
self.dest_addr = self.raw[2]
self.ack       = self.raw[3] == true
if (self.dest_addr == COMPUTER_ID) or (self.dest_addr == comms.BROADCAST) then
self.valid = type(self.src_addr) == TYPE_NUM and type(self.dest_addr) == TYPE_NUM
end
end
return self.valid
end
function public.modem_event() return self.modem_frame end
function public.raw_frame() return self.raw end
function public.interface() return self.modem_frame.iface end
function public.local_channel() return self.modem_frame.s_chan end
function public.remote_channel() return self.modem_frame.r_chan end
function public.is_valid() return self.valid end
function public.src_addr() return self.src_addr or comms.BROADCAST end
function public.dest_addr() return self.dest_addr or comms.BROADCAST end
function public.is_ack() return self.ack end
return public
end
function comms.scada_frame()
local self = {
modem_frame = nil,
valid         = false,
authenticated = false,
raw = {},
src_addr  = nil,
dest_addr = nil,
seq_num   = nil,
protocol  = nil,
length    = 0,
payload   = {}
}
local public = {}
function public.make(dest_addr, seq_num, protocol, payload)
self.valid = true
self.src_addr  = COMPUTER_ID
self.dest_addr = dest_addr
self.seq_num   = seq_num
self.protocol  = protocol
self.length    = #payload
self.payload   = payload
self.raw = { COMPUTER_ID, dest_addr, seq_num, protocol, payload }
end
function public.receive(side, sender, reply_to, message, distance)
self.modem_frame = {
iface = side, s_chan = sender, r_chan = reply_to, dist = distance, data = message
}
self.valid = false
self.raw   = self.modem_frame.data
if (type(max_distance) == TYPE_NUM) and (type(distance) == TYPE_NUM) and (distance > max_distance) then
elseif type(self.raw) == TYPE_TBL then
self.src_addr  = self.raw[1]
self.dest_addr = self.raw[2]
if ((self.dest_addr == COMPUTER_ID) or (self.dest_addr == comms.BROADCAST)) and (type(self.raw[5]) == TYPE_TBL) then
self.seq_num  = self.raw[3]
self.protocol = self.raw[4]
self.length   = #self.raw[5]
self.payload  = self.raw[5]
self.valid = type(self.src_addr) == TYPE_NUM and type(self.dest_addr) == TYPE_NUM and
type(self.seq_num) == TYPE_NUM and type(self.protocol) == TYPE_NUM
end
end
return self.valid
end
function public.stamp_authenticated() self.authenticated = true end
function public.modem_event() return self.modem_frame end
function public.raw_header() return { self.src_addr, self.dest_addr, self.seq_num, self.protocol } end
function public.raw_frame() return self.raw end
function public.interface() return self.modem_frame.iface end
function public.local_channel() return self.modem_frame.s_chan end
function public.remote_channel() return self.modem_frame.r_chan end
function public.is_valid() return self.valid end
function public.is_authenticated() return self.authenticated end
function public.src_addr() return self.src_addr or comms.BROADCAST end
function public.dest_addr() return self.dest_addr or comms.BROADCAST end
function public.seq_num() return self.seq_num or -1 end
function public.protocol() return self.protocol or PROTOCOL.SCADA_MGMT end
function public.length() return self.length or 0 end
function public.data() return self.payload or {} end
return public
end
function comms.authd_frame()
local self = {
modem_frame = nil,
valid = false,
raw = {},
src_addr  = nil,
dest_addr = nil,
mac       = "",
payload   = {}
}
local public = {}
function public.make(s_frame, mac)
self.valid = true
self.src_addr  = s_frame.src_addr()
self.dest_addr = s_frame.dest_addr()
self.mac       = mac(textutils.serialize(s_frame.raw_header(), { allow_repetitions = true, compact = true }))
self.raw = { self.src_addr, self.dest_addr, self.mac, s_frame.raw_frame() }
end
function public.receive(side, sender, reply_to, message, distance)
self.modem_frame = {
iface = side, s_chan = sender, r_chan = reply_to, data = message, dist = distance
}
self.valid = false
self.raw   = self.modem_frame.data
if (type(max_distance) == TYPE_NUM) and ((type(distance) ~= TYPE_NUM) or (distance > max_distance)) then
elseif type(self.raw) == TYPE_TBL then
self.src_addr  = self.raw[1]
self.dest_addr = self.raw[2]
if (self.dest_addr == COMPUTER_ID) or (self.dest_addr == comms.BROADCAST) then
self.mac     = self.raw[3]
self.payload = self.raw[4]
self.valid = type(self.src_addr) == TYPE_NUM and type(self.dest_addr) == TYPE_NUM and
type(self.mac) == TYPE_STR and type(self.payload) == TYPE_TBL
end
end
return self.valid
end
function public.modem_event() return self.modem_frame end
function public.raw_frame() return self.raw end
function public.local_channel() return self.modem_frame.s_chan end
function public.remote_channel() return self.modem_frame.r_chan end
function public.is_valid() return self.valid end
function public.src_addr() return self.src_addr or comms.BROADCAST end
function public.dest_addr() return self.dest_addr or comms.BROADCAST end
function public.mac() return self.mac or "" end
function public.data() return self.payload or {} end
return public
end
function comms.modbus_container()
local self = {
frame = nil,
raw = {},
txn_id    = -1,
length    = 0,
unit_id   = -1,
func_code = 0x80,
data      = {}
}
local public = {}
function public.make(txn_id, unit_id, func_code, data)
if type(data) == TYPE_TBL then
self.txn_id    = txn_id
self.length    = #data
self.unit_id   = unit_id
self.func_code = func_code
self.data      = data
self.raw = { self.txn_id, self.unit_id, self.func_code }
for i = 1, self.length do insert(self.raw, data[i]) end
return true
end
log.error("COMMS: [modbus_make] data not a table")
return false
end
function public.decode(frame)
if frame then
local data = frame.data()
self.frame = frame
self.raw   = data
if frame.protocol() == PROTOCOL.MODBUS_TCP then
self.txn_id    = data[1]
self.unit_id   = data[2]
self.func_code = data[3]
self.data      = { table.unpack(data, 4, #data) }
self.length    = #self.data
if type(self.txn_id) == TYPE_NUM and type(self.unit_id) == TYPE_NUM and type(self.func_code) == TYPE_NUM then
return public.get()
end
else log.debug("COMMS: [modbus_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
else log.debug("COMMS: [modbus_decode] discarding nil frame", true) end
return nil
end
function public.raw_packet() return self.raw end
function public.get()
local adu = {
scada_frame = self.frame,
txn_id = self.txn_id,
length = self.length,
unit_id = self.unit_id,
func_code = self.func_code,
data = self.data
}
return adu
end
return public
end
function comms.rplc_container()
local self = {
frame = nil,
raw   = {},
id     = 0,
type   = 0,
length = 0,
data   = {}
}
local public = {}
function public.make(id, packet_type, data)
if type(data) == TYPE_TBL then
self.id     = id
self.type   = packet_type
self.length = #data
self.data   = data
self.raw = { self.id, self.type }
for i = 1, #data do insert(self.raw, data[i]) end
return true
end
log.error("COMMS: [rplc_make] data not a table")
return false
end
function public.decode(frame)
if frame then
local data = frame.data()
self.frame = frame
self.raw   = data
if frame.protocol() == PROTOCOL.RPLC then
self.id     = data[1]
self.type   = data[2]
self.data   = { table.unpack(data, 3, #data) }
self.length = #self.data
if type(self.id) == TYPE_NUM and type(self.type) == TYPE_NUM then
return public.get()
end
else log.debug("COMMS: [rplc_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
else log.debug("COMMS: [rplc_decode] nil frame encountered", true) end
return nil
end
function public.raw_packet() return self.raw end
function public.get()
local packet = {
scada_frame = self.frame,
id = self.id,
type = self.type,
length = self.length,
data = self.data
}
return packet
end
return public
end
function comms.mgmt_container()
local self = {
frame = nil,
raw = {},
type   = 0,
length = 0,
data   = {}
}
local public = {}
function public.make(packet_type, data)
if type(data) == TYPE_TBL then
self.type   = packet_type
self.length = #data
self.data   = data
self.raw = { self.type }
for i = 1, #data do insert(self.raw, data[i]) end
return true
end
log.error("COMMS: [mgmt_make] data not a table")
return false
end
function public.decode(frame)
if frame then
local data = frame.data()
self.frame = frame
self.raw   = data
if frame.protocol() == PROTOCOL.SCADA_MGMT then
self.type   = data[1]
self.data   = { table.unpack(data, 2, #data) }
self.length = #self.data
if type(self.type) == TYPE_NUM then
return public.get()
end
else log.debug("COMMS: [mgmt_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
else log.debug("COMMS: [mgmt_decode] nil frame encountered", true) end
return nil
end
function public.raw_packet() return self.raw end
function public.get()
local packet = {
scada_frame = self.frame,
type = self.type,
length = self.length,
data = self.data
}
return packet
end
return public
end
function comms.crdn_container()
local self = {
frame = nil,
raw = {},
type   = 0,
length = 0,
data   = {}
}
local public = {}
function public.make(packet_type, data)
if type(data) == TYPE_TBL then
self.type   = packet_type
self.length = #data
self.data   = data
self.raw = { self.type }
for i = 1, #data do insert(self.raw, data[i]) end
return true
end
log.error("COMMS: [crdn_make] data not a table")
return false
end
function public.decode(frame)
if frame then
local data = frame.data()
self.frame = frame
self.raw   = data
if frame.protocol() == PROTOCOL.SCADA_CRDN then
self.type   = data[1]
self.data   = { table.unpack(data, 2, #data) }
self.length = #self.data
if type(self.type) == TYPE_NUM then
return public.get()
end
else log.debug("COMMS: [crdn_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
else log.debug("COMMS: [crdn_decode] nil frame encountered", true) end
return nil
end
function public.raw_packet() return self.raw end
function public.get()
local packet = {
scada_frame = self.frame,
type = self.type,
length = self.length,
data = self.data
}
return packet
end
return public
end
return comms
