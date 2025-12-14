local M = {}

local async = require "quickfill.async"
local utils = require "quickfill.utils"
local config = require "quickfill.config"
local cache = require "quickfill.cache"
local suggestion = require "quickfill.suggestion"
local extra = require "quickfill.extra"
local logger = require "quickfill.logger"

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
---@param lsp_clients vim.lsp.Client[]
---@return string
local function build_infill_payload(local_context, lsp_context, lsp_clients)
    local input_extra = extra.get_input_extra()
    if lsp_context.completions then input_extra[#input_extra + 1] = { text = lsp_context.completions } end
    if lsp_context.signatures then input_extra[#input_extra + 1] = { text = lsp_context.signatures } end

    local stop = utils.tbl_copy(config.STOP_CHARS)
    for _, client in ipairs(lsp_clients) do
        for _, char in ipairs(client.server_capabilities.completionProvider.triggerCharacters or {}) do
            if char ~= " " and not vim.tbl_contains(stop, char) then stop[#stop + 1] = char end
        end
    end

    return vim.json.encode {
        input_prefix = local_context.prefix,
        prompt = local_context.middle,
        input_suffix = local_context.suffix,
        input_extra = input_extra,
        cache_prompt = true,
        max_tokens = config.MAX_TOKENS,
        n_predict = config.MAX_TOKENS,
        top_k = 40,
        top_p = 0.5,
        repeat_penalty = 1.3,
        samplers = { "top_k", "top_p", "infill" },
        logit_bias = lsp_context.logit_bias,
        t_max_predict_ms = 500,
        stream = true,
        stop = stop,
    }
end

---@param req_id number
---@param local_context quickfill.LocalContext
---@param lsp_clients vim.lsp.Client[]
---@param sug string
---@param row number
---@param col number
local function request_infill_speculative(req_id, local_context, lsp_clients, sug, row, col)
    local new_line = local_context.middle .. sug
    local new_local_context = {
        prefix = local_context.prefix,
        middle = new_line,
        suffix = local_context.suffix,
    }

    local temp_buf = vim.api.nvim_create_buf(false, true)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    lines[row] = new_line
    vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines)

    local filename = vim.api.nvim_buf_get_name(0)
    local parts = vim.split(filename, ".", { plain = true })
    local ext = parts[#parts] or "tmp"

    local ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
    vim.api.nvim_buf_set_name(temp_buf, ("%s.%s"):format(vim.fn.sha256(filename), ext))
    vim.api.nvim_set_option_value("filetype", ft, { buf = temp_buf })

    async.async(function()
        local context = require "quickfill.context"
        for _, client in ipairs(lsp_clients) do
            vim.lsp.buf_attach_client(temp_buf, client.id)
        end
        local new_lsp_context = context.get_lsp_context(temp_buf, new_line, row, col)
        vim.schedule(function()
            M.request_infill(req_id, new_local_context, new_lsp_context, new_line)
            vim.api.nvim_buf_delete(temp_buf, { force = true })
        end)
    end)()
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
    if resp.stop then
        if resp.stop_type ~= "word" or vim.tbl_contains(config.STOP_CHARS, resp.stopping_word) then return end
        text = resp.stopping_word
    end
    vim.schedule(function()
        if req_id ~= request_id then return end
        local new_suggestion = suggestion.get() .. text
        suggestion.show(new_suggestion, row, col)
    end)
end

---@param req_id number
---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
---@param speculative? string
M.request_infill = utils.debounce(function(req_id, local_context, lsp_context, speculative)
    if req_id ~= request_id then return end
    if vim.bo.readonly or vim.bo.buftype ~= "" then return end

    if not speculative then
        M.cancel_stream()
        suggestion.clear()
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local lsp_clients = vim.lsp.get_clients { bufnr = 0 }

    stdout = assert(vim.uv.new_pipe(false), "failed to create stdout pipe")
    stdin = assert(vim.uv.new_pipe(false), "failed to create stdin pipe")

    handle = vim.uv.spawn("curl", {
        args = {
            ("%s/infill"):format(config.URL),
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

        logger.info(
            "request llama infill, stream stop",
            { req_id = req_id, suggestion = sug, speculative = speculative ~= nil }
        )

        vim.schedule(function()
            if speculative and #speculative > 0 then
                local pre_line, _, suf_sug = utils.overlap(speculative, sug)
                cache.cache_add({
                    prefix = local_context.prefix,
                    middle = pre_line,
                    suffix = local_context.suffix,
                }, sug)
                sug = suf_sug
            end
            cache.cache_add(local_context, sug)

            if not speculative then
                request_infill_speculative(req_id, local_context, lsp_clients, suggestion.get(), row, col + #sug)
            end
        end)
    end)

    local payload = build_infill_payload(local_context, lsp_context, lsp_clients)
    logger.info(
        "request llama infill, stream start",
        { req_id = req_id, prompt = local_context.middle, speculative = speculative ~= nil }
    )
    stdin:write(payload, function()
        stdin:close()
    end)

    stdout:read_start(function(_, chunk)
        if not chunk then return end
        on_stream_read(chunk, req_id, row, col)
    end)
end, 50)

---@param route string
---@param payload string
function M.request_json(route, payload)
    return function(resume)
        logger.info("request llama", { route = route })
        vim.system({
            "curl",
            ("%s/%s"):format(config.URL, route),
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            "@-",
        }, { stdin = payload }, function(result)
            if result.code == 0 then
                logger.info("request llama", { route = route, code = result.code })
                resume(nil, vim.json.decode(result.stdout))
            else
                logger.error("request llama", { route = route, error = result.stderr, code = result.code })
                resume(result.stderr)
            end
        end)
    end
end

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

return M
