local M = {}

local utils = require "quickfill.utils"
local logger = require "quickfill.logger"
local context = require "quickfill.context"

local ns = vim.api.nvim_create_namespace "quickfill.suggestion"

local suggestion = ""

---@return string
function M.get()
    return suggestion
end

---@param text string
---@param row number
---@param col number
function M.show(text, row, col)
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

    suggestion = text
    if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then return end

    local lines = vim.split(text, "\n", { plain = true })
    if #lines == 0 then return end

    local first_line = lines[1]:gsub(" ", "·")
    local extmark_opts = {
        virt_text = { { first_line, "Comment" } },
        virt_text_pos = "overlay",
    }

    if #lines > 1 and #first_line == 0 then
        local virt_lines = {}
        for i = 2, #lines do
            virt_lines[i - 1] = { { lines[i]:gsub(" ", "·"), "Comment" } }
        end
        extmark_opts.virt_lines = virt_lines
    end

    pcall(vim.api.nvim_buf_set_extmark, 0, ns, row - 1, col, extmark_opts)
end

function M.clear()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    suggestion = ""
end

function M.accept()
    local row, col = context.get_cursor_pos()
    local sug_lines = vim.split(suggestion, "\n", { plain = true })
    local curr_lines = vim.api.nvim_buf_get_lines(0, row - 1, row + #sug_lines, false)
    local curr_line = curr_lines[1]
    local suffix = curr_line:sub(col + 1)
    local new_text = utils.overlap(sug_lines[1], suffix)

    if #new_text > 0 then
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { new_text })
        vim.api.nvim_win_set_cursor(0, { row, col + #sug_lines[1] })
    elseif col < #curr_line then
        vim.api.nvim_win_set_cursor(0, { row, #curr_line })
    else
        local skip = 0
        for idx = 2, #sug_lines do
            if idx > #curr_lines or curr_lines[idx] ~= sug_lines[idx] then break end
            skip = skip + 1
        end

        local ins_lines = vim.list_slice(sug_lines, skip + 1)

        if #ins_lines > 0 then
            if skip > 0 then
                vim.api.nvim_buf_set_text(0, row - 1 + skip, 0, row - 1 + skip, 0, ins_lines)
            else
                vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, ins_lines)
            end
        end

        local new_row = row + skip + #ins_lines - 1
        local new_col
        if #ins_lines == 0 then
            new_col = #(curr_lines[skip + 1] or "")
        elseif #ins_lines == 1 then
            new_col = col + #ins_lines[1]
        else
            new_col = #ins_lines[#ins_lines]
        end
        vim.api.nvim_win_set_cursor(0, { new_row, new_col })
    end

    logger.debug("suggestion accept", { suggestion = suggestion, row = row, col = col })
    M.clear()
    suggestion = ""
end

function M.accept_word()
    if #suggestion == 0 then return end

    local row, col = context.get_cursor_pos()

    if suggestion:sub(1, 1) == "\n" then
        suggestion = suggestion:sub(2)
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { "", "" })
        vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    else
        local first_line = vim.split(suggestion, "\n", { plain = true })[1]
        local word = first_line:match "^.-[%a%d_]+" or first_line
        if #word == 0 then return end

        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local suffix = line:sub(col + 1)

        local new_text = utils.overlap(word, suffix)
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { new_text })
        vim.api.nvim_win_set_cursor(0, { row, col + #word })
        suggestion = suggestion:sub(#word + 1)
    end

    logger.info("suggestion accept word", { suggestion = suggestion, row = row, col = col })

    local new_row, new_col = context.get_cursor_pos()
    if #suggestion > 0 then
        M.show(suggestion, new_row, new_col)
    else
        M.clear()
    end
end

function M.accept_replace()
    local row, col = context.get_cursor_pos()
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local lines = vim.split(suggestion, "\n", { plain = true })

    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, #line, lines)

    local new_row = row + #lines - 1
    local new_col = #lines == 1 and col + #lines[1] or #lines[#lines]
    vim.api.nvim_win_set_cursor(0, { new_row, new_col })

    logger.debug("suggestion accept replace", { suggestion = suggestion, row = row, col = col })

    M.clear()
    suggestion = ""
end

return M
