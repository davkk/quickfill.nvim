local M = {}

local utils = require "quickfill.utils"

local ns = vim.api.nvim_create_namespace "user.ai"

local suggestion = ""

function M.get()
    return suggestion
end

---@param text string
---@param row number
---@param col number
function M.show(text, row, col)
    suggestion = text
    if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
        pcall(vim.api.nvim_buf_set_extmark, 0, ns, row - 1, col, {
            virt_text = { { text, "Comment" } },
            virt_text_pos = "overlay",
        })
    end
end

function M.clear()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    suggestion = ""
end

function M.accept()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local suffix = line:sub(col + 1)

    local new_text = utils.overlap(suggestion, suffix)
    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { new_text })
    vim.api.nvim_win_set_cursor(0, { row, col + #suggestion })

    M.clear()
    suggestion = ""
end

function M.accept_word()
    if #suggestion == 0 then
        return
    end
    local match = suggestion:match "^.-[%a%d_]+"
    local word = match or suggestion
    if #word == 0 then
        return
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local suffix = line:sub(col + 1)

    local new_text = utils.overlap(word, suffix)
    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { new_text })
    vim.api.nvim_win_set_cursor(0, { row, col + #word })

    suggestion = suggestion:sub(#word + 1)

    if #suggestion > 0 then
        M.show(suggestion, row, col + #word)
    else
        M.clear()
    end
end

return M
