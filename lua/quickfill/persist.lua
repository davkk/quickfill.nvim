local M = {}

local logger = require "quickfill.logger"

local project_hash = vim.fn.sha256(vim.fs.root(0, ".git") or vim.fn.getcwd())

---@return string
local function get_file_path()
    local data_dir = vim.fs.joinpath(vim.fn.stdpath "data", "quickfill")
    local file = project_hash .. ".json"
    return vim.fs.joinpath(data_dir, file)
end

---@return table<string, string>?, table<quickfill.ExtraChunk>?
function M.load_persisted_data()
    local file_path = get_file_path()
    if vim.fn.filereadable(file_path) == 1 then
        local lines = vim.fn.readfile(file_path)
        local json_str = table.concat(lines, "\n")
        local data = vim.json.decode(json_str)
        logger.info("persistence data found", { file_path = file_path, data = data })
        return data.cache or {}, data.extra_chunks or {}
    end
    logger.warn("persistence data not found", { file_path = file_path })
    return nil, nil
end

---@class data
---@field cache table<string, string>
---@field extra_chunks table<quickfill.ExtraChunk>
---@param data data
function M.save_persisted_data(data)
    local file_path = get_file_path()
    vim.fn.mkdir(vim.fn.fnamemodify(file_path, ":p:h"), "p")
    local json_str = vim.json.encode(data)
    vim.fn.writefile(vim.split(json_str, "\n"), file_path)
    logger.info("persistence data written to file", { file_path = file_path, data = data })
end

return M
