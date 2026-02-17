local M = {}

local config = require "quickfill.config"
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

    lru = vim.tbl_filter(function(k)
        return k ~= key
    end, lru)
    lru[#lru + 1] = key

    if not cache[key] then
        if vim.tbl_count(cache) > config.max_cache_entries - 1 then
            local least_used = lru[1]
            cache[least_used] = nil
            table.remove(lru, 1)
        end
        cache[key] = Trie:new()
    end

    return cache[key]
end

---@return table<string, quickfill.Trie>
function M.get_all()
    return cache
end

return M
