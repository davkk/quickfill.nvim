local M = {}

---@param fn function
---@return function(...): void
function M.async(fn)
    return function(...)
        local co = coroutine.create(fn)
        assert(type(co) == "thread", "failed to create coroutine")

        local function step(...)
            local ok, yielded = coroutine.resume(co, ...)
            if not ok then
                error(yielded)
            end

            if coroutine.status(co) == "dead" then
                return
            end

            assert(type(yielded) == "function", "async coroutine must yield a function")

            yielded(step)
        end

        step(...)
    end
end

---@generic T
---@param fn fun(resume: fun(result: T))
---@return T
function M.await(fn)
    assert(coroutine.running(), "await must be called inside a coroutine")
    return coroutine.yield(function(resume)
        assert(type(resume) == "function", "internal resume must be a function")
        fn(resume)
    end)
end

return M
