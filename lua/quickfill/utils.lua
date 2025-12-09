local M = {}

function M.fn(f, ...)
    local args = { ... }
    return function(...)
        return f(unpack(args), ...)
    end
end

---@param fn function
---@param delay number
---@return function
function M.debounce(fn, delay)
    local timer = nil
    return function(...)
        if timer then
            vim.fn.timer_stop(timer)
        end
        local args = { ... }
        timer = vim.fn.timer_start(delay, function()
            fn(unpack(args))
        end)
    end
end

---@generic T
---@param tbl T
---@return T
function M.tbl_copy(tbl)
    if not tbl then
        return tbl
    end
    local new = {}
    for idx, value in ipairs(tbl) do
        new[idx] = value
    end
    return new
end

return M
