local M = {}

local async = require "quickfill.async"
local config = require "quickfill.config"
local utils = require "quickfill.utils"
local logger = require "quickfill.logger"

local git_root = vim.fs.root(0, ".git")

---@type table<quickfill.ExtraChunk>
local chunks = {}

---@param text string
---@return string
local function trim(text)
    text = text:gsub("^%s+", "")
    text = text:gsub("^\t+", "")
    return text
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
        if inter[val] then common = common + 1 end
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
    if not config.extra_chunks then return end
    if vim.bo.readonly or vim.bo.buftype ~= "" then return end

    if git_root then
        local relative_path = utils.relative_path(buf, git_root)
        local obj = vim.system({ "git", "check-ignore", relative_path }):wait()
        if #obj.stdout > 0 then
            logger.warn("file in gitignore", { buf = buf })
            return
        end
    end

    local chunk_start = row - config.chunk_lines / 2 - 1
    local chunk_end = row + config.chunk_lines / 2

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
    local clean = {}
    for _, line in ipairs(lines) do
        if #trim(line) > 0 then clean[#clean + 1] = line:sub(1, 256) end
    end
    lines = clean

    -- skip small chunks
    if #lines < 5 then return end

    ---@type quickfill.ExtraChunk
    local new_chunk = {
        filename = utils.relative_path(buf, git_root),
        lines = lines,
    }

    -- TODO: chunks should have unique lines between them
    for idx, chunk in ipairs(chunks) do
        local sim = similarity(lines, chunk.lines)
        if sim > 0.55 then
            logger.info("extra remove chunk", { idx = idx, sim = sim })
            table.remove(chunks, idx)
        end
    end

    if #chunks + 1 > config.max_extra_chunks then
        logger.info "extra chunks full, remove first chunk"
        table.remove(chunks, 1)
    end
    chunks[#chunks + 1] = new_chunk
    logger.info("extra add chunk", { idx = #chunks })

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

---@return table<quickfill.ExtraChunk>
function M.get_chunks()
    return chunks
end

---@param loaded_chunks table<quickfill.ExtraChunk>?
function M.load_extra(loaded_chunks)
    chunks = loaded_chunks or {}
end

return M
