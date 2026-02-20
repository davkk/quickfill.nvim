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

    local a = require "quickfill.async"
    local cache = require "quickfill.cache"
    local context = require "quickfill.context"
    local extra = require "quickfill.extra"
    local request = require "quickfill.request"
    local suggestion = require "quickfill.suggestion"
    local config = require "quickfill.config"
    local utils = require "quickfill.utils"

    M.group = vim.api.nvim_create_augroup("ai", { clear = true })

    ---@param fn function
    local function accept(fn)
        if #suggestion.get() == 0 then return end
        if vim.fn.pumvisible() ~= 0 then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x>", true, false, true), "n", false)
        end
        vim.schedule(fn)
    end
    vim.keymap.set("i", "<Plug>(quickfill-accept)", utils.fn(accept, suggestion.accept))
    vim.keymap.set("i", "<Plug>(quickfill-accept-word)", utils.fn(accept, suggestion.accept_word))
    vim.keymap.set("i", "<Plug>(quickfill-accept-replace)", utils.fn(accept, suggestion.accept_replace))

    vim.keymap.set(
        "i",
        "<Plug>(quickfill-trigger)",
        a.sync(function()
            local buf = vim.api.nvim_get_current_buf()
            local local_context = context.get_local_context(buf)

            request.cancel_stream()
            suggestion.clear()
            cache.remove_entry(local_context)

            local lsp_context = a.wait(context.get_lsp_context(buf, local_context.middle))

            a.wait(a.main_loop)
            local trie = cache.get_or_add(local_context)
            local node = trie:insert(local_context.middle)
            request.request_infill(local_context, lsp_context, trie, node)
        end)
    )

    vim.api.nvim_create_autocmd({ "CursorMovedI", "TextChangedP" }, {
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
            local row, _ = context.get_cursor_pos()
            extra.try_add_chunk(ev.buf, row)
        end,
    })
end

function M.stop()
    if not M.enabled then return end
    M.enabled = false

    vim.api.nvim_clear_autocmds { group = M.group }

    pcall(vim.keymap.del, "i", "<Plug>(quickfill-accept)")
    pcall(vim.keymap.del, "i", "<Plug>(quickfill-accept-word)")
    pcall(vim.keymap.del, "i", "<Plug>(quickfill-trigger)")
end

return M
