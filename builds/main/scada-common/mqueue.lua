
local mqueue = {}
local TYPE = {
COMMAND = 0,
DATA = 1,
NETWORK = 2
}
mqueue.TYPE = TYPE
local insert = table.insert
local remove = table.remove
function mqueue.new()
local queue = {}
local public = {}
function public.length() return #queue end
function public.empty() return #queue == 0 end
function public.ready() return #queue ~= 0 end
local function _push(qtype, message) insert(queue, { qtype = qtype, message = message }) end
function public.push_command(message) _push(TYPE.COMMAND, message) end
function public.push_data(key, value) _push(TYPE.DATA, { key = key, val = value }) end
function public.push_network(object) _push(TYPE.NETWORK, object) end
function public.pop()
if #queue > 0 then
return remove(queue, 1)
else return nil end
end
return public
end
return mqueue
