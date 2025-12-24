local M = {}

local config = require "quickfill.config"
local logger = require "quickfill.logger"

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
function M.add(context, value)
    if vim.tbl_count(cache) > config.max_cache_entries - 1 then
        local least_used = lru[1]
        logger.info(
            "cache full, removing cache entry",
            { hash = least_used, value = cache[least_used], prompt = context.middle }
        )
        cache[least_used] = nil
        table.remove(lru, 1)
    end

    local hash = get_hash(context)
    cache[hash] = value
    logger.info("cache add", { hash = hash, value = value, prompt = context.middle })

    lru = vim.tbl_filter(function(k)
        return k ~= hash
    end, lru)
    lru[#lru + 1] = hash
    logger.info("cache lru promote", { hash = hash })
end

---@param context quickfill.LocalContext
function M.get(context)
    local hash = get_hash(context)
    local value = cache[hash]
    if not value then return nil end

    logger.info("cache get ", { hash = hash, value = value, prompt = context.middle })

    lru = vim.tbl_filter(function(k)
        return k ~= hash
    end, lru)
    lru[#lru + 1] = hash
    logger.info("cache lru promote", { hash = hash })

    return value
end

---@return table<string, string>
function M.get_all()
    return cache
end

---@param loaded_cache table<string, string>?
function M.load(loaded_cache)
    cache = loaded_cache or {}
    lru = vim.tbl_keys(cache)
end

function M.clear()
    cache = {}
    lru = {}
end

return M
