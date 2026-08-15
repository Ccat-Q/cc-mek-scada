
local util = require("scada-common.util")
local txnctrl = {}
local TIMEOUT = 2000
function txnctrl.new()
local self = {
list = {},
next_id = 0
}
local public = {}
local insert = table.insert
local remove = table.remove
function public.length()
return #self.list
end
function public.empty()
return #self.list == 0
end
function public.create(txn_type)
local txn_id = self.next_id
insert(self.list, {
txn_id = txn_id,
txn_type = txn_type,
expiry = util.time() + TIMEOUT
})
self.next_id = self.next_id + 1
return txn_id
end
function public.resolve(txn_id)
local txn_type = nil
for i = 1, public.length() do
if self.list[i].txn_id == txn_id then
local entry = remove(self.list, i)
txn_type = entry.txn_type
break
end
end
return txn_type
end
function public.renew(txn_id, txn_type)
insert(self.list, {
txn_id = txn_id,
txn_type = txn_type,
expiry = util.time() + TIMEOUT
})
end
function public.cleanup()
local now = util.time()
util.filter_table(self.list, function (txn) return txn.expiry > now end)
end
function public.clear()
self.list = {}
end
return public
end
return txnctrl
