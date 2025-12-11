local M = {}

local async = require "quickfill.async"
local config = require "quickfill.config"

---@type table<quickfill.ExtraChunk>
local chunks = {}

---@param text string
local function trim(text)
    return text:gsub("^%s+", ""):gsub("^\t+", "")
end

---@param lines1 table<string>
---@param lines2 table<string>
---@return number
local function similarity(lines1, lines2)
    local inter = {}
    local common = 0
    for _, val in ipairs(lines1) do
        inter[val] = true
    end
    for _, val in ipairs(lines2) do
        if inter[val] then
            common = common + 1
        end
    end
    return 2 * common / (#lines1 + #lines2)
end

---@return table<quickfill.ExtraChunk>
function M.get_input_extra()
    local input_extra = {}
    for _, chunk in ipairs(chunks) do
        input_extra[#input_extra + 1] = {
            filename = chunk.filename,
            text = table.concat(chunk.lines, "\n") .. "\n",
        }
    end
    return input_extra
end

---@param buf number
---@param row number
function M.try_add_chunk(buf, row)
    if vim.bo.readonly or vim.bo.buftype ~= "" then
        return
    end

    local chunk_start = row - config.CHUNK_SIZE / 2 - 1
    local chunk_end = row + config.CHUNK_SIZE / 2

    local max_line_nr = vim.api.nvim_buf_line_count(buf)

    if chunk_start < 0 then
        chunk_end = math.min(chunk_end + math.abs(chunk_start), max_line_nr)
        chunk_start = 0
    elseif chunk_end > max_line_nr then
        chunk_start = math.max(chunk_start - (chunk_end - max_line_nr), 0)
        chunk_end = max_line_nr
    end

    assert(chunk_start < chunk_end)

    local lines = vim.api.nvim_buf_get_lines(buf, chunk_start, chunk_end, false)
    lines = vim.tbl_filter(function(line)
        return #trim(line) > 0
    end, lines)

    -- skip small chunks
    if #lines < 5 then
        return
    end

    ---@type quickfill.ExtraChunk
    local new_chunk = {
        filename = vim.api.nvim_buf_get_name(buf),
        lines = lines,
    }

    -- TODO: chunks should have unique lines between them
    for idx, chunk in ipairs(chunks) do
        if similarity(lines, chunk.lines) > 0.55 then
            table.remove(chunks, idx)
        end
    end

    if #chunks + 1 > config.MAX_EXTRAS then
        table.remove(chunks, 1)
    end
    chunks[#chunks + 1] = new_chunk

    local input_extra = M.get_input_extra()

    async.async(function()
        async.await(require("quickfill.request").request_json(
            "infill",
            vim.json.encode {
                input_prefix = "",
                prompt = "",
                input_suffix = "",
                input_extra = input_extra,
                cache_prompt = true,
                samplers = {},
                n_predict = 0,
                max_tokens = 0,
                t_max_predict_ms = 1,
                response_fields = { "" },
            }
        ))
    end)()
end

return M
