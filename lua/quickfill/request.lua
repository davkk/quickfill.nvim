local M = {}

local async = require "quickfill.async"
local utils = require "quickfill.utils"
local config = require "quickfill.config"
local cache = require "quickfill.cache"
local suggestion = require "quickfill.suggestion"
local extra = require "quickfill.extra"
local logger = require "quickfill.logger"
local context = require "quickfill.context"

---@type uv.uv_process_t?
local handle = nil
---@type uv.uv_pipe_t?
local stdout = nil
---@type uv.uv_pipe_t?
local stdin = nil

local request_id = 0

---@return number
function M.latest_id()
    return request_id
end

---@return number
function M.next_request_id()
    request_id = request_id + 1
    return request_id
end

---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
---@return string
local function build_infill_payload(local_context, lsp_context)
    local input_extra = extra.get_input_extra()
    if lsp_context.completions then input_extra[#input_extra + 1] = { text = lsp_context.completions } end
    if lsp_context.signatures then input_extra[#input_extra + 1] = { text = lsp_context.signatures } end

    local stop = utils.tbl_copy(config.stop_chars or {})
    if config.stop_on_trigger_char then
        for _, char in ipairs { ".", ":", "[", "{", "(" } do
            stop[#stop + 1] = char
        end
    end

    return vim.json.encode {
        input_prefix = local_context.prefix,
        prompt = local_context.middle,
        input_suffix = local_context.suffix,
        input_extra = input_extra,
        cache_prompt = true,
        max_tokens = config.n_predict,
        n_predict = config.n_predict,
        top_k = config.top_k,
        top_p = config.top_p,
        repeat_penalty = config.repeat_penalty,
        samplers = { "top_k", "top_p", "infill" },
        logit_bias = lsp_context.logit_bias,
        t_max_predict_ms = 500,
        stream = true,
        stop = stop,
    }
end

---@param chunk string
---@param req_id number
---@param row number
---@param col number
local function on_stream_read(chunk, req_id, row, col)
    assert(chunk, "chunk should be defined")

    if req_id ~= request_id then return end
    if #chunk < 6 or chunk:sub(1, 6) ~= "data: " then return end

    chunk = chunk:sub(7)
    local ok, resp = pcall(vim.json.decode, chunk)
    if not ok then return end

    local text = resp.content

    if config.stop_on_trigger_char and resp.stop then
        if resp.stop_type ~= "word" or vim.tbl_contains(config.stop_chars, resp.stopping_word) then return end
        text = resp.stopping_word
    end

    vim.schedule(function()
        if req_id ~= request_id then return end
        local new_suggestion = suggestion.get() .. text
        suggestion.show(new_suggestion, row, col)
    end)
end

---@param code number
local function on_stream_end(code)
    if code ~= 0 then
        -- TODO: more info about error?
        logger.error("request llama infill, curl error", { code = code })
        vim.schedule(function()
            vim.notify(("curl exited with code %d"):format(code), vim.diagnostic.severity.ERROR)
        end)
    end
    if stdout then
        stdout:close()
        stdout = nil
    end
    if handle then
        handle:close()
        handle = nil
    end
end

---@param req_id number
---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
local function request_infill(req_id, local_context, lsp_context)
    if req_id ~= request_id then return end
    if vim.bo.readonly or vim.bo.buftype ~= "" then return end

    M.cancel_stream()
    suggestion.clear()

    ---@type number, number
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))

    stdout = assert(vim.uv.new_pipe(false), "failed to create stdout pipe")
    stdin = assert(vim.uv.new_pipe(false), "failed to create stdin pipe")

    handle = vim.uv.spawn("curl", {
        args = {
            ("%s/infill"):format(config.url),
            "--no-buffer",
            "--request",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            "@-",
        },
        stdio = { stdin, stdout },
    }, function(code)
        on_stream_end(code)

        local sug = suggestion.get()
        if #sug == 0 then return end

        logger.info("request llama infill, stream stop", { req_id = req_id, suggestion = sug })

        vim.schedule(function()
            cache.add(local_context, sug)
        end)
    end)

    local payload = build_infill_payload(local_context, lsp_context)
    logger.info("request llama infill, stream start", { req_id = req_id, prompt = local_context.middle })
    stdin:write(payload, function()
        stdin:close()
    end)

    stdout:read_start(function(_, chunk)
        if not chunk then return end
        on_stream_read(chunk, req_id, row, col)
    end)
end

M.request_infill = request_infill

function M.cancel_stream()
    -- FIXME: I don't think this should be wrapped in pcall
    pcall(function()
        if handle and handle:is_active() then
            handle:kill()
            handle:close()
            handle = nil
        end
        if stdin then
            stdin:close()
            stdin = nil
        end
        if stdout then
            stdout:close()
            stdout = nil
        end
    end)
end

---@param buf number
function M.suggest(buf)
    M.cancel_stream()
    suggestion.clear()

    local req_id = M.next_request_id()

    ---@type number, number
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local best = ""
    local local_context = context.get_local_context(buf)
    local cached = cache.get(local_context)

    for i = 1, 64 do
        if cached then
            best = cached
            break
        end

        local new_middle = local_context.middle:sub(1, #local_context.middle - i)
        if #new_middle == 0 then break end

        local new_context = {
            prefix = local_context.prefix,
            middle = new_middle,
            suffix = local_context.suffix,
        }
        local hit = cache.get(new_context)
        if hit then
            local removed = local_context.middle:sub(#local_context.middle - i + 1)
            if hit:sub(1, #removed) == removed then
                local remain = hit:sub(#removed + 1)
                if #remain > #best then best = remain end
            end
        end
    end

    if #best > 0 then
        if req_id ~= M.latest_id() then return end
        suggestion.show(best, row, col)
        return
    end

    async.async(function()
        if req_id ~= M.latest_id() then return end
        local lsp_context = context.get_lsp_context(buf, local_context.middle)
        vim.schedule(function()
            if req_id ~= M.latest_id() then return end
            M.request_infill(req_id, local_context, lsp_context)
        end)
    end)()
end

return M
