
local util = require("scada-common.util")
local psil = {}
function psil.create()
local ic = {}
local function alloc(key)
ic[key] = { subscribers = {}, value = nil }
end
local public = {}
function public.subscribe(key, func)
if ic[key] == nil then
alloc(key)
elseif ic[key].value ~= nil then
func(ic[key].value)
end
table.insert(ic[key].subscribers, { notify = func })
end
function public.unsubscribe(key, func)
if ic[key] ~= nil then
util.filter_table(ic[key].subscribers, function (s) return s.notify ~= func end)
end
end
function public.publish(key, value)
if ic[key] == nil then alloc(key) end
if ic[key].value ~= value then
ic[key].value = value
for i = 1, #ic[key].subscribers do
ic[key].subscribers[i].notify(value)
end
end
end
function public.toggle(key)
if ic[key] == nil then alloc(key) end
ic[key].value = ic[key].value == false
for i = 1, #ic[key].subscribers do
ic[key].subscribers[i].notify(ic[key].value)
end
end
function public.get(key)
if ic[key] ~= nil then return ic[key].value else return nil end
end
function public.purge() ic = {} end
return public
end
return psil
