
local log  = require("scada-common.log")
local util = require("scada-common.util")
local pgi = {}
local data = {
pkt_list = nil,
pkt_entry = nil,
s_entries = {
pkt = {}
}
}
function pgi.link_elements(pkt_list, pkt_entry)
data.pkt_list = pkt_list
data.pkt_entry = pkt_entry
end
function pgi.unlink()
data.pkt_list = nil
data.pkt_entry = nil
end
function pgi.create_pkt_entry(session_id)
if data.pkt_list ~= nil and data.pkt_entry ~= nil then
local success, result = pcall(data.pkt_entry, data.pkt_list, session_id)
if success then
data.s_entries.pkt[session_id] = result
else
log.error(util.c("PGI: failed to create PKT entry (", result, ")"), true)
end
end
end
function pgi.delete_pkt_entry(session_id)
if data.s_entries.pkt[session_id] ~= nil then
local success, result = pcall(data.s_entries.pkt[session_id].delete)
data.s_entries.pkt[session_id] = nil
if not success then
log.error(util.c("PGI: failed to delete PKT entry (", result, ")"), true)
end
else
log.debug(util.c("PGI: tried to delete unknown PKT entry ", session_id))
end
end
return pgi
