---@class quickfill.LocalContext
---@field prefix string
---@field middle string
---@field suffix string

---@class quickfill.LspContext
---@field logit_bias table<string, string>
---@field completions string?
---@field signatures string?

---@class quickfill.ExtraChunk
---@field filename string
---@field lines table<string, boolean>

local M = {}

M.group = nil
M.enabled = false

function M.start()
    if M.enabled then return end
    M.enabled = true

    local async = require "quickfill.async"
    local cache = require "quickfill.cache"
    local context = require "quickfill.context"
    local extra = require "quickfill.extra"
    local request = require "quickfill.request"
    local suggestion = require "quickfill.suggestion"
    local config = require "quickfill.config"
    local persist = require "quickfill.persist"
    local utils = require "quickfill.utils"

    M.group = vim.api.nvim_create_augroup("ai", { clear = true })

    local loaded_cache, loaded_extra = persist.load_persisted_data()
    cache.load(loaded_cache)
    extra.load(loaded_extra)

    vim.api.nvim_create_autocmd("VimLeave", {
        group = M.group,
        callback = function()
            persist.save_persisted_data {
                cache = cache.get_all(),
                extra_chunks = extra.get_chunks(),
            }
        end,
    })

    ---@param fn function
    local function accept(fn)
        if #suggestion.get() == 0 then return end
        if vim.fn.pumvisible() ~= 0 then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n", false)
        end
        vim.schedule(fn)
    end
    vim.keymap.set("i", "<Plug>(quickfill-accept)", utils.fn(accept, suggestion.accept))
    vim.keymap.set("i", "<Plug>(quickfill-accept-word)", utils.fn(accept, suggestion.accept_word))

    vim.keymap.set("i", "<Plug>(quickfill-trigger)", function()
        local buf = vim.api.nvim_get_current_buf()
        async.async(function()
            local local_context = context.get_local_context(buf)
            local lsp_context = context.get_lsp_context(buf, local_context.middle)
            vim.schedule(function()
                request.request_infill(request.next_request_id(), local_context, lsp_context)
            end)
        end)()
    end)

    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP", "InsertEnter", "CursorMovedI" }, {
        group = M.group,
        callback = function(ev)
            request.suggest(ev.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "InsertLeavePre", "CursorMoved" }, {
        group = M.group,
        callback = function()
            suggestion.clear()
            request.cancel_stream()
        end,
    })

    vim.api.nvim_create_autocmd({ "CursorHold", "BufWritePost" }, {
        group = M.group,
        callback = function(ev)
            if not config.extra_chunks then return end
            local row = unpack(vim.api.nvim_win_get_cursor(0))
            extra.try_add_chunk(ev.buf, row)
        end,
    })
end

function M.stop()
    if not M.enabled then return end
    M.enabled = false

    local persist = require "quickfill.persist"
    local cache = require "quickfill.cache"
    local extra = require "quickfill.extra"

    vim.api.nvim_clear_autocmds { group = M.group }

    persist.save_persisted_data {
        cache = cache.get_all(),
        extra_chunks = extra.get_chunks(),
    }

    pcall(vim.keymap.del, "i", "<Plug>(quickfill-accept)")
    pcall(vim.keymap.del, "i", "<Plug>(quickfill-accept-word)")
    pcall(vim.keymap.del, "i", "<Plug>(quickfill-trigger)")
end

return M
