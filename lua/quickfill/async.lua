local M = {}

local co = coroutine
local logger = require "quickfill.logger"

function M.pong(func, callback)
    local thread = co.create(func)
    local step
    step = function(...)
        local pack = { co.resume(thread, ...) }
        local ok, val = pack[1], pack[2]
        if not ok then
            logger.error("async coroutine error", { error = val })
            error(val)
        end
        if co.status(thread) == "dead" then
            if callback then callback(val) end
        else
            if type(val) ~= "function" then
                logger.error("async invalid yield", { type = type(val) })
                error("yielded value must be a thunk")
            end
            val(step)
        end
    end
    step()
end

function M.sync(func)
    return function(...)
        local args = { ... }
        local thunk = function(step)
            M.pong(function()
                return func(unpack(args))
            end, step)
        end
        if not co.running() then M.pong(function()
            return func(unpack(args))
        end, nil) end
        return thunk
    end
end

function M.wrap(func)
    return function(...)
        local args = { ... }
        return function(step)
            table.insert(args, step)
            return func(unpack(args))
        end
    end
end

function M.join(thunks)
    local len = #thunks
    local done = 0
    local acc = {}
    return function(step)
        if len == 0 then return step() end
        for i, tk in ipairs(thunks) do
            tk(function(...)
                acc[i] = { ... }
                done = done + 1
                if done == len then step(unpack(acc)) end
            end)
        end
    end
end

function M.wait(thunk)
    assert(type(thunk) == "function", "await expects a thunk")
    return co.yield(thunk)
end

function M.wait_all(thunks)
    assert(type(thunks) == "table", "await_all expects a table")
    return co.yield(M.join(thunks))
end

function M.main_loop(fn)
    vim.schedule(fn)
end

return M
