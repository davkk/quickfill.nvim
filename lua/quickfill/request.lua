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

    local stop = utils.tbl_copy(config.stop_chars)
    if config.stop_on_stop_char then
        for _, client in ipairs(lsp_clients) do
            for _, char in ipairs(client.server_capabilities.completionProvider.triggerCharacters or {}) do
                if char ~= " " and not vim.tbl_contains(stop, char) then stop[#stop + 1] = char end
            end
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

---@param buf number
---@param row number
---@param text string
local function notify_line_change(buf, row, text)
    local clients = vim.lsp.get_clients { bufnr = buf }
    for _, client in ipairs(clients) do
        client:notify("textDocument/didChange", {
            textDocument = {
                uri = vim.uri_from_bufnr(buf),
                version = vim.lsp.util.buf_versions[buf] + 1,
            },
            contentChanges = {
                {
                    range = {
                        start = { line = row - 1, character = 0 },
                        ["end"] = {
                            line = row - 1,
                            character = vim.lsp.util.character_offset(buf, row - 1, #text, "utf-16"),
                        },
                    },
                    text = text,
                },
            },
        })
    end
end

---@param buf number
---@param req_id number
---@param local_context quickfill.LocalContext
---@param sug string
---@param row number
---@param col number
local function request_infill_speculative(buf, req_id, local_context, sug, row, col)
    local new_line = local_context.middle .. sug
    local new_local_context = {
        prefix = local_context.prefix,
        middle = new_line,
        suffix = local_context.suffix,
    }
    notify_line_change(buf, row, new_line)
    async.async(function()
        local new_lsp_context = require("quickfill.context").get_lsp_context(buf, new_line, {
            textDocument = { uri = vim.uri_from_bufnr(buf), version = vim.lsp.util.buf_versions[buf] },
            position = { line = row - 1, character = col },
        })
        vim.schedule(function()
            M.request_infill(req_id, new_local_context, new_lsp_context, new_line)
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
    if config.stop_on_stop_char and resp.stop then
        if resp.stop_type ~= "word" or vim.tbl_contains(config.stop_chars, resp.stopping_word) then return end
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
function M.request_infill(req_id, local_context, lsp_context, speculative)
    if req_id ~= request_id then return end
    if vim.bo.readonly or vim.bo.buftype ~= "" then return end

    if not speculative then
        M.cancel_stream()
        suggestion.clear()
    end

    ---@type number, number
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local buf = vim.api.nvim_get_current_buf()
    local lsp_clients = vim.lsp.get_clients { bufnr = buf }

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

        logger.info(
            "request llama infill, stream stop",
            { req_id = req_id, suggestion = sug, speculative = speculative ~= nil }
        )

        vim.schedule(function()
            if speculative and #speculative > 0 then
                local pre_line, _, suf_sug = utils.overlap(speculative, sug)
                notify_line_change(buf, row, pre_line)
                cache.cache_add({
                    prefix = local_context.prefix,
                    middle = pre_line,
                    suffix = local_context.suffix,
                }, sug)
                sug = suf_sug
            end
            cache.cache_add(local_context, sug)

            if config.stop_on_stop_char and not speculative then
                request_infill_speculative(buf, req_id, local_context, suggestion.get(), row, col + #sug)
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
end

---@param route string
---@param payload string
function M.request_json(route, payload)
    return function(resume)
        logger.info("request llama", { route = route })
        vim.system({
            "curl",
            ("%s/%s"):format(config.url, route),
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
