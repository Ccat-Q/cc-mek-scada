
local log  = require("scada-common.log")
local util = require("scada-common.util")
local tcd = {}
local registry = {}
function tcd.dispatch(time, f)
local timer = util.start_timer(time)
registry[timer] = {
callback = f,
duration = time,
expiry = time + util.time_s()
}
end
function tcd.dispatch_unique(time, f)
for timer, entry in pairs(registry) do
if entry.callback == f then
log.debug(util.c("TCD: aborting duplicate timer callback [timer: ", timer, ", ", f, "]"))
util.cancel_timer(timer)
registry[timer] = nil
end
end
local timer = util.start_timer(time)
registry[timer] = {
callback = f,
duration = time,
expiry = time + util.time_s()
}
end
function tcd.abort(f)
for timer, entry in pairs(registry) do
if entry.callback == f then
util.cancel_timer(timer)
registry[timer] = nil
end
end
end
function tcd.handle(event)
if registry[event] ~= nil then
local callback = registry[event].callback
registry[event] = nil
callback()
end
end
function tcd.diagnostics()
for timer, entry in pairs(registry) do
if entry.expiry < util.time_s() then
local overtime = util.time_s() - entry.expiry
log.debug(util.c("TCD: unserviced timer ", timer, " for callback ", entry.callback, " is at least ", overtime, "s late"))
else
local time = entry.expiry - util.time_s()
log.debug(util.c("TCD: pending timer ", timer, " for callback ", entry.callback, " (call after ", entry.duration, "s, expires ", time, ")"))
end
end
end
return tcd
