local M = {}

local config = require "quickfill.config"
local logger = require "quickfill.logger"
local a = require "quickfill.async"

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
        if timer then vim.fn.timer_stop(timer) end
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
    if not tbl then return tbl end
    local new = {}
    for idx, value in ipairs(tbl) do
        new[idx] = value
    end
    return new
end

---@param left string
---@param right string
---@return string, string, string
function M.overlap(left, right)
    local max_overlap = math.min(#left, #right)
    local ol = 0
    for i = 1, max_overlap do
        local a_end = left:sub(-i)
        local b_start = right:sub(1, i)
        if a_end == b_start then ol = i end
    end
    return left:sub(1, #left - ol), left:sub(#left - ol + 1), right:sub(ol + 1)
end

---@param bufnr integer
---@param root string?
---@return string
function M.relative_path(bufnr, root)
    local cwd = root or vim.fn.getcwd()
    local fullpath = vim.api.nvim_buf_get_name(bufnr)
    return fullpath:sub(#cwd + 2)
end

---@param route string
---@param payload string
M.request_json = a.wrap(function(route, payload, resume)
    logger.info("request llama", { route = route })
    vim.system({
        "curl",
        ("%s/%s"):format(config.url, route),
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "-d",
        "@-",
    }, { stdin = payload }, function(result)
        if result.code == 0 then
            logger.info("request llama", { route = route, code = result.code })
            resume(nil, vim.json.decode(result.stdout))
        else
            logger.error("request llama", { route = route, error = result.stderr, code = result.code })
            resume(result.stderr)
        end
    end)
end)

return M
