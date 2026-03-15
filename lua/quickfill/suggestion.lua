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
    local lines = vim.split(suggestion, "\n", { plain = true })
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local suffix = line:sub(col + 1)

    local new_text = utils.overlap(lines[1], suffix)
    if #new_text > 0 then
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { new_text })
        vim.api.nvim_win_set_cursor(0, { row, col + #lines[1] })
    else
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, #line, lines)
        local new_row = row + #lines - 1
        local new_col = #lines == 1 and col + #lines[1] or #lines[#lines]
        vim.api.nvim_win_set_cursor(0, { new_row, new_col })
    end

    logger.debug("suggestion accept", { suggestion = suggestion, row = row, col = col })

    M.clear()
    suggestion = ""
end

function M.accept_word()
    -- TODO: make it simpler
    if #suggestion == 0 then return end

    local lines = vim.split(suggestion, "\n", { plain = true })
    local word

    if #lines == 1 then
        local match = suggestion:match "^.-[%a%d_]+"
        word = match or suggestion
    else
        local first_line = lines[1]
        local match = first_line:match "^.-[%a%d_]+"

        if match and #match > 0 then
            word = match
        else
            word = first_line .. "\n"
            if lines[2] then
                local next_match = lines[2]:match "^.-[%a%d_]+"
                if next_match then
                    word = word .. next_match
                else
                    word = word .. lines[2]
                end
            end
        end
    end

    if #word == 0 then return end

    local row, col = context.get_cursor_pos()
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local suffix = line:sub(col + 1)

    local word_lines = vim.split(word, "\n", { plain = true })
    if #word_lines == 1 then
        local new_text = utils.overlap(word, suffix)
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { new_text })
        vim.api.nvim_win_set_cursor(0, { row, col + #word })
    else
        local _, _, remaining_suffix = utils.overlap(word_lines[1], suffix)
        word_lines[1] = word_lines[1] .. remaining_suffix
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, #line, word_lines)
        local new_row = row + #word_lines - 1
        local new_col = #word_lines == 1 and col + #word_lines[1] or #word_lines[#word_lines]
        vim.api.nvim_win_set_cursor(0, { new_row, new_col })
    end

    logger.info("suggestion accept word", { word = word, row = row, col = col })

    suggestion = suggestion:sub(#word + 1)

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
