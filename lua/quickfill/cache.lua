local M = {}

local config = require "quickfill.config"

---@type table<string, string>
local cache = {}

---@type table<string>
local lru = {}

---@param context quickfill.LocalContext
local function get_hash(context)
    return vim.fn.sha256(context.prefix .. context.middle .. "█" .. context.suffix)
end

---@param context quickfill.LocalContext
---@param value string
function M.cache_add(context, value)
    if vim.tbl_count(cache) > config.MAX_CACHE - 1 then
        local least_used = lru[1]
        cache[least_used] = nil
        table.remove(lru, 1)
    end

    local hash = get_hash(context)
    cache[hash] = value

    lru = vim.tbl_filter(function(k)
        return k ~= hash
    end, lru)
    lru[#lru + 1] = hash
end

---@param context quickfill.LocalContext
function M.cache_get(context)
    local hash = get_hash(context)
    local value = cache[hash]
    if not value then
        return nil
    end

    lru = vim.tbl_filter(function(k)
        return k ~= hash
    end, lru)
    lru[#lru + 1] = hash

    return value
end

return M
