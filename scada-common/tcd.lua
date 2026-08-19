--
-- Timer Callback Dispatcher
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

local tcd = {}

---@type { callback: function, duration: number, expiry: number }[]
local registry = {}

-- request a function to be called after the specified time
---@param time number seconds
---@param f function callback function
function tcd.dispatch(time, f)
    local timer = util.start_timer(time)
    registry[timer] = {
        callback = f,
        duration = time,
        expiry = time + util.time_s()
    }
end

-- request a function to be called after the specified time, aborting any registered instances of that function reference
---@param time number seconds
---@param f function callback function
function tcd.dispatch_unique(time, f)
    -- cancel if already registered
    for timer, entry in pairs(registry) do
        if entry.callback == f then
            -- found an instance of this function reference, abort it
            log.debug(util.c("TCD: 中止重复的定时器回调 [timer: ", timer, ", ", f, "]"))

            -- cancel event and remove from registry (even if it fires it won't call)
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

-- abort a requested callback
---@param f function callback function
function tcd.abort(f)
    for timer, entry in pairs(registry) do
        if entry.callback == f then
            -- cancel event and remove from registry (even if it fires it won't call)
            util.cancel_timer(timer)
            registry[timer] = nil
        end
    end
end

-- lookup a timer event and execute the callback if found
---@param event integer timer event timer ID
function tcd.handle(event)
    if registry[event] ~= nil then
        local callback = registry[event].callback
        -- clear first so that dispatch_unique call from inside callback won't throw a debug message
        registry[event] = nil
        callback()
    end
end

-- identify any overdue callbacks<br>
-- prints to log debug output
function tcd.diagnostics()
    for timer, entry in pairs(registry) do
        if entry.expiry < util.time_s() then
            local overtime = util.time_s() - entry.expiry
            log.debug(util.c("TCD: 未处理的定时器 ", timer, " 的回调 ", entry.callback, " 至少延迟 ", overtime, " 秒"))
        else
            local time = entry.expiry - util.time_s()
            log.debug(util.c("TCD: 待处理定时器 ", timer, " 的回调 ", entry.callback, "（", entry.duration, " 秒后调用，剩余 ", time, " 秒）"))
        end
    end
end

return tcd
