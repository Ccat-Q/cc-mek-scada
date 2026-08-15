
local log    = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local util   = require("scada-common.util")
local ioctl  = require("coordinator.ioctl")
local pocket = require("coordinator.session.pocket")
local apisessions = {}
local self = {
nic = nil,
config = nil,
next_id = 0,
sessions = {}
}
local function _api_handle_outq(session)
local handle_start = util.time()
while session.out_queue.ready() do
local msg = session.out_queue.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.NETWORK then
self.nic.transmit(self.config.PKT_Channel, self.config.CRD_Channel, msg.message)
end
end
if util.time() - handle_start > 100 then
log.warning("API: out queue handler exceeded 100ms queue process limit")
log.warning(util.c("API: offending session: ", session))
break
end
end
end
local function _shutdown(session)
session.open = false
session.instance.close()
while session.out_queue.ready() do
local msg = session.out_queue.pop()
if msg ~= nil and msg.qtype == mqueue.TYPE.NETWORK then
self.nic.transmit(self.config.PKT_Channel, self.config.CRD_Channel, msg.message)
end
end
log.debug(util.c("API: closed session ", session))
end
function apisessions.init(nic, config)
self.nic = nic
self.config = config
end
function apisessions.find_session(source_addr)
for i = 1, #self.sessions do
if self.sessions[i].s_addr == source_addr then return self.sessions[i] end
end
return nil
end
function apisessions.establish_session(source_addr, i_seq_num, version)
local pkt_s = {
open = true,
version = version,
s_addr = source_addr,
in_queue = mqueue.new(),
out_queue = mqueue.new(),
instance = nil
}
local id = self.next_id
pkt_s.instance = pocket.new_session(id, source_addr, i_seq_num, pkt_s.in_queue, pkt_s.out_queue, self.config.API_Timeout)
table.insert(self.sessions, pkt_s)
local mt = {
__tostring = function (s)  return util.c("PKT [", id, "] (@", s.s_addr, ")") end
}
setmetatable(pkt_s, mt)
ioctl.fp_pkt_connected(id, version, source_addr)
log.debug(util.c("API: established new session: ", pkt_s))
self.next_id = id + 1
return pkt_s.instance.get_id()
end
function apisessions.check_all_watchdogs(timer_event)
for i = 1, #self.sessions do
local session = self.sessions[i]
if session.open then
local triggered = session.instance.check_wd(timer_event)
if triggered then
log.debug(util.c("API: watchdog closing session ", session, "..."))
_shutdown(session)
return true
end
end
end
return false
end
function apisessions.iterate_all()
for i = 1, #self.sessions do
local session = self.sessions[i]
if session.open and session.instance.iterate() then
_api_handle_outq(session)
else
session.open = false
end
end
end
function apisessions.free_all_closed()
local f = function (session) return session.open end
local on_delete = function (session)
log.debug(util.c("API: free'ing closed session ", session))
end
util.filter_table(self.sessions, f, on_delete)
end
function apisessions.close_all()
for i = 1, #self.sessions do
local session = self.sessions[i]
if session.open then _shutdown(session) end
end
apisessions.free_all_closed()
end
return apisessions
