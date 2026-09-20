local M = {}

local config = require "quickfill.config"
local logger = require "quickfill.logger"
local Trie = require "quickfill.trie"

---@type table<string, quickfill.Trie>
local cache = {}

---@type table<string>
local lru = {}

---@param context quickfill.LocalContext
local function get_key(context)
    return vim.fn.sha256(context.prefix .. "█" .. context.suffix)
end

---@param context quickfill.LocalContext
function M.remove_entry(context)
    local key = get_key(context)
    cache[key] = nil
    lru = vim.tbl_filter(function(k)
        return k ~= key
    end, lru)
end

---@param context quickfill.LocalContext
function M.get_or_add(context)
    local key = get_key(context)

    if cache[key] then
        lru = vim.tbl_filter(function(k)
            return k ~= key
        end, lru)
        lru[#lru + 1] = key
        return cache[key]
    end

    if #lru >= config.max_cache_entries then
        local least_used = lru[1]
        logger.debug("cache evict", { key = least_used })
        cache[least_used] = nil
        table.remove(lru, 1)
    end
    cache[key] = Trie:new()
    lru[#lru + 1] = key

    return cache[key]
end

---@return table<string, quickfill.Trie>
function M.get_all()
    return cache
end

return M
