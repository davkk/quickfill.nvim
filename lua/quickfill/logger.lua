local M = {}

local INFO = 0
local WARN = 5
local ERROR = 10

local levels = {
    [INFO] = "INFO",
    [WARN] = "WARN",
    [ERROR] = "ERROR",
}

local log_path = vim.fs.joinpath(vim.fn.stdpath "state", "quickfill.log")
local fd, fd_err = vim.uv.fs_open(log_path, "a", 438)
if not fd then error("unable to open log file: " .. log_path .. " " .. (fd_err or "")) end

--- @param data table
--- @return string
local function stringify_table(data)
    local out = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            v = vim.inspect(v, { newline = "", depth = 3 })
        elseif type(v) == "string" then
            v = string.format("'%s'", v)
        else
            v = tostring(v)
        end
        table.insert(out, string.format("%s=%s", k, v))
    end
    return table.concat(out, ", ")
end

--- @param level number
--- @param msg string
--- @param data table?
function M.log(level, msg, data)
    local _, b = math.modf(os.clock())
    local timestamp = os.date("%Y-%m-%d %H:%M:%S.", os.time()) .. tostring(b):sub(3, 5)
    local level_str = levels[level]
    local line = string.format("[%s] [%s] %s { %s }\n", timestamp, level_str, msg, stringify_table(data or {}))
    local success, err = vim.uv.fs_write(fd, line)
    if not success then error("unable to write to log: " .. (err or "")) end
end

--- @param msg string
--- @param data table?
function M.info(msg, data)
    M.log(INFO, msg, data)
end

--- @param msg string
--- @param data table?
function M.warn(msg, data)
    M.log(WARN, msg, data)
end

--- @param msg string
--- @param data table?
function M.error(msg, data)
    M.log(ERROR, msg, data)
end

return M
