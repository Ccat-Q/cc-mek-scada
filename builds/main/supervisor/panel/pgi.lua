
local log  = require("scada-common.log")
local util = require("scada-common.util")
local pgi = {}
local data = {
rtu_list = nil,
pdg_list = nil,
chk_list = nil,
rtu_entry = nil,
pdg_entry = nil,
chk_entry = nil,
entries = {
rtu = {},
pdg = {},
chk = {},
missing = {}
}
}
function pgi.link_elements(rtu_list, rtu_entry, pdg_list, pdg_entry, chk_list, chk_entry)
data.rtu_list = rtu_list
data.pdg_list = pdg_list
data.chk_list = chk_list
data.rtu_entry = rtu_entry
data.pdg_entry = pdg_entry
data.chk_entry = chk_entry
end
function pgi.unlink()
data.rtu_list = nil
data.pdg_list = nil
data.chk_list = nil
data.rtu_entry = nil
data.pdg_entry = nil
data.chk_entry = nil
end
function pgi.create_rtu_entry(session_id)
if data.rtu_list ~= nil and data.rtu_entry ~= nil then
local success, result = pcall(data.rtu_entry, data.rtu_list, session_id)
if success then
data.entries.rtu[session_id] = result
log.debug(util.c("PGI: 已创建 RTU 条目 (", session_id, ")"))
else
log.error(util.c("PGI: 创建 RTU 条目失败 (", result, ")"), true)
end
end
end
function pgi.delete_rtu_entry(session_id)
if data.entries.rtu[session_id] ~= nil then
local success, result = pcall(data.entries.rtu[session_id].delete)
data.entries.rtu[session_id] = nil
if success then
log.debug(util.c("PGI: 已删除 RTU 条目 (", session_id, ")"))
else
log.error(util.c("PGI: 删除 RTU 条目失败 (", result, ")"), true)
end
else
log.warning(util.c("PGI: 尝试删除未知 RTU 条目 ", session_id))
end
end
function pgi.create_pdg_entry(session_id)
if data.pdg_list ~= nil and data.pdg_entry ~= nil then
local success, result = pcall(data.pdg_entry, data.pdg_list, session_id)
if success then
data.entries.pdg[session_id] = result
log.debug(util.c("PGI: 已创建 PDG 条目 (", session_id, ")"))
else
log.error(util.c("PGI: 创建 PDG 条目失败 (", result, ")"), true)
end
end
end
function pgi.delete_pdg_entry(session_id)
if data.entries.pdg[session_id] ~= nil then
local success, result = pcall(data.entries.pdg[session_id].delete)
data.entries.pdg[session_id] = nil
if success then
log.debug(util.c("PGI: 已删除 PDG 条目 (", session_id, ")"))
else
log.error(util.c("PGI: 删除 PDG 条目失败 (", result, ")"), true)
end
else
log.warning(util.c("PGI: 尝试删除未知 PDG 条目 ", session_id))
end
end
function pgi.create_chk_entry(unit, fail_code, msg, details)
local gw_session = unit.get_session_id()
if data.chk_list ~= nil and data.chk_entry ~= nil then
if not data.entries.chk[gw_session] then data.entries.chk[gw_session] = {} end
local success, result = pcall(data.chk_entry, data.chk_list, fail_code, msg, details)
if success then
data.entries.chk[gw_session][unit.get_unit_id()] = result
log.debug(util.c("PGI: 已创建 CHK 条目 (", gw_session, ":", unit.get_unit_id(), ")"))
else
log.error(util.c("PGI: 创建 CHK 条目失败 (", result, ")"), true)
end
end
end
function pgi.delete_chk_entry(unit)
local gw_session = unit.get_session_id()
local ent_chk = data.entries.chk
if ent_chk[gw_session] ~= nil and ent_chk[gw_session][unit.get_unit_id()] ~= nil then
local success, result = pcall(ent_chk[gw_session][unit.get_unit_id()].delete)
ent_chk[gw_session][unit.get_unit_id()] = nil
if success then
log.debug(util.c("PGI: 已删除 CHK 条目 ", gw_session, ":", unit.get_unit_id()))
else
log.error(util.c("PGI: 删除 CHK 条目失败 (", result, ")"), true)
end
else
log.warning(util.c("PGI: 尝试删除未知 CHK 条目，会话为 ", gw_session, "，机组 ID 为 ", unit.get_unit_id()))
end
end
function pgi.create_missing_entry(message)
if data.entries.missing[message] ~= nil then
log.warning(util.c("PGI: 尝试创建重复的缺失 CHK 条目 \"", message, "\""))
elseif data.chk_list ~= nil and data.chk_entry ~= nil then
local success, result = pcall(data.chk_entry, data.chk_list, 4, message)
if success then
data.entries.missing[message] = result
log.debug(util.c("PGI: 已创建缺失 CHK 条目 (", message, ")"))
else
log.error(util.c("PGI: 创建缺失 CHK 条目失败 (", result, ")"), true)
end
end
end
function pgi.delete_missing_entry(message)
if data.entries.missing[message] ~= nil then
local success, result = pcall(data.entries.missing[message].delete)
data.entries.missing[message] = nil
if success then
log.debug(util.c("PGI: 已删除缺失 CHK 条目 \"", message, "\""))
else
log.error(util.c("PGI: 删除缺失 CHK 条目失败 (", result, ")"), true)
end
else
log.warning(util.c("PGI: 尝试删除未知的缺失 CHK 条目 \"", message, "\""))
end
end
return pgi
