local M = {}

local state = require "quickfill.state"
local async = require "quickfill.async"
local cache = require "quickfill.cache"
local context = require "quickfill.context"
local extra = require "quickfill.extra"
local request = require "quickfill.request"
local suggestion = require "quickfill.suggestion"

local group = vim.api.nvim_create_augroup("ai", { clear = true })

vim.api.nvim_create_user_command("AI", function()
    vim.keymap.set("i", "<C-q>", function()
        if #state.suggestion > 0 then
            if vim.fn.pumvisible() == 1 then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n", false)
            end
            vim.defer_fn(suggestion.accept, 10)
        end
    end)

    vim.keymap.set("i", "<C-l>", function()
        if #state.suggestion > 0 then
            if vim.fn.pumvisible() == 1 then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n", false)
            end
            vim.defer_fn(suggestion.accept_word, 10)
        end
    end)

    vim.keymap.set("i", "<C-space>", function()
        async.async(function()
            local local_context = context.get_local_context()
            local lsp_context = context.get_lsp_context(local_context.middle)
            vim.schedule(function()
                state.request_id = state.request_id + 1
                state.current_request_id = state.request_id
                request.request_infill(state.current_request_id, local_context, lsp_context)
            end)
        end)()
    end)

    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP", "InsertEnter" }, {
        group = group,
        callback = function()
            request.cancel_stream()
            suggestion.clear()

            state.request_id = state.request_id + 1
            local request_id = state.request_id
            state.current_request_id = request_id

            local row, col = unpack(vim.api.nvim_win_get_cursor(0))
            local best = ""
            local local_context = context.get_local_context()
            local cached = cache.cache_get(local_context)

            for i = 1, 64 do
                if cached then
                    best = cached
                    break
                end

                local new_middle = local_context.middle:sub(1, #local_context.middle - i)
                if #new_middle == 0 then
                    break
                end

                local new_context = {
                    prefix = local_context.prefix,
                    middle = new_middle,
                    suffix = local_context.suffix,
                }
                local hit = cache.cache_get(new_context)
                if hit then
                    local removed = local_context.middle:sub(#local_context.middle - i + 1)
                    if hit:sub(1, #removed) == removed then
                        local remain = hit:sub(#removed + 1)
                        if #remain > #best then
                            best = remain
                        end
                    end
                end
            end

            if #best > 0 then
                if request_id ~= state.current_request_id then
                    return
                end
                state.suggestion = best
                suggestion.show(best, row, col)
                return
            end

            async.async(function()
                if request_id ~= state.current_request_id then
                    return
                end
                local lsp_context = context.get_lsp_context(local_context.middle)
                vim.schedule(function()
                    if request_id ~= state.current_request_id then
                        return
                    end
                    request.request_infill(request_id, local_context, lsp_context)
                end)
            end)()
        end,
    })

    vim.api.nvim_create_autocmd({ "InsertLeavePre", "CursorMoved", "CursorMovedI" }, {
        group = group,
        callback = function()
            suggestion.clear()
            request.cancel_stream()
        end,
    })

    vim.api.nvim_create_autocmd({ "CursorHold", "BufWritePost" }, {
        group = group,
        callback = function(ev)
            local row = unpack(vim.api.nvim_win_get_cursor(0))
            extra.try_add_chunk(ev.buf, row)
        end,
    })
end, {})

return M
