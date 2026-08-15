
local tcd  = require("scada-common.tcd")
local util = require("scada-common.util")
local flasher = {}
local PERIOD = {
BLINK_250_MS = 1,
BLINK_500_MS = 2,
BLINK_1000_MS = 3
}
flasher.PERIOD = PERIOD
local active = false
local registry = { {}, {}, {} }
local callback_counter = 0
local function callback_250ms()
if active then
for _, f in ipairs(registry[PERIOD.BLINK_250_MS]) do f() end
if callback_counter % 2 == 0 then
for _, f in ipairs(registry[PERIOD.BLINK_500_MS]) do f() end
end
if callback_counter % 4 == 0 then
for _, f in ipairs(registry[PERIOD.BLINK_1000_MS]) do f() end
end
callback_counter = callback_counter + 1
tcd.dispatch_unique(0.25, callback_250ms)
end
end
function flasher.run()
if not active then
active = true
callback_250ms()
end
end
function flasher.clear()
active = false
callback_counter = 0
registry = { {}, {}, {} }
end
function flasher.start(f, period)
if type(registry[period]) == "table" and not util.table_contains(registry[period], f) then
table.insert(registry[period], f)
end
end
function flasher.stop(f)
for i = 1, #registry do
for key, val in ipairs(registry[i]) do
if val == f then
table.remove(registry[i], key)
return
end
end
end
end
return flasher
