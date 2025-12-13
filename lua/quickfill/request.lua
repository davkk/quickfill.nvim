local M = {}

local async = require "quickfill.async"
local utils = require "quickfill.utils"
local config = require "quickfill.config"
local cache = require "quickfill.cache"
local suggestion = require "quickfill.suggestion"
local extra = require "quickfill.extra"

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

function M.cancel_stream()
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

---@param req_id number
---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
---@param speculative? string
M.request_infill = utils.debounce(function(req_id, local_context, lsp_context, speculative)
    if vim.bo.readonly or vim.bo.buftype ~= "" then
        return
    end

    if req_id ~= request_id then
        return
    end

    if not speculative then
        M.cancel_stream()
        suggestion.clear()
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))

    local input_extra = extra.get_input_extra()

    if lsp_context.completions then
        input_extra[#input_extra + 1] = { text = lsp_context.completions }
    end
    if lsp_context.signatures then
        input_extra[#input_extra + 1] = { text = lsp_context.signatures }
    end

    local stop = utils.tbl_copy(config.STOP_CHARS)
    local clients = vim.lsp.get_clients { bufnr = 0 }
    for _, client in ipairs(clients) do
        for _, char in ipairs(client.server_capabilities.completionProvider.triggerCharacters or {}) do
            if char ~= " " and not vim.tbl_contains(stop, char) then
                stop[#stop + 1] = char
            end
        end
    end

    local payload = vim.json.encode {
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

    stdout = vim.uv.new_pipe(false)
    stdin = vim.uv.new_pipe(false)
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
        if stdout then
            stdout:close()
            stdout = nil
        end
        if handle then
            handle:close()
            handle = nil
        end
        if code ~= 0 then
            vim.schedule(function()
                vim.notify(("curl exited with code %d"):format(code), vim.diagnostic.severity.ERROR)
            end)
            return
        end
        local sug = suggestion.get()
        if #sug > 0 then
            vim.schedule(function()
                if speculative and #speculative > 0 then
                    local _, _, suffix = utils.overlap(speculative, sug)
                    sug = suffix
                end
                cache.cache_add(local_context, sug)
            end)
        end
        if not speculative then
            local new_line = local_context.middle .. sug
            local new_local_context = {
                prefix = local_context.prefix,
                middle = new_line,
                suffix = local_context.suffix,
            }
            vim.schedule(function()
                local temp_buf = vim.api.nvim_create_buf(false, true)
                local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                lines[row] = new_line
                vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines)
                async.async(function()
                    local context = require "quickfill.context"
                    for _, client in ipairs(clients) do
                        vim.lsp.buf_attach_client(temp_buf, client.id)
                    end
                    local new_lsp_context = context.get_lsp_context(temp_buf, new_line, row, col + #new_line - 1)
                    vim.schedule(function()
                        M.request_infill(req_id, new_local_context, new_lsp_context, new_line)
                        vim.api.nvim_buf_delete(temp_buf, { force = true })
                    end)
                end)()
            end)
        end
    end)
    if stdin then
        stdin:write(payload, function()
            stdin:close()
        end)
    end
    if stdout then
        stdout:read_start(function(_, chunk)
            if chunk then
                M.on_stream_chunk(chunk, req_id, row, col)
            end
        end)
    end
end, 50)

---@param chunk string
---@param req_id number
---@param row number
---@param col number
function M.on_stream_chunk(chunk, req_id, row, col)
    if req_id ~= request_id then
        return
    end
    if #chunk > 6 and chunk:sub(1, 6) == "data: " then
        chunk = chunk:sub(7)
        local ok, resp = pcall(vim.json.decode, chunk)
        if ok then
            local text = resp.content
            if resp.stop then
                if resp.stop_type == "word" and not vim.tbl_contains(config.STOP_CHARS, resp.stopping_word) then
                    text = resp.stopping_word
                else
                    return
                end
            end
            vim.schedule(function()
                if req_id ~= request_id then
                    return
                end
                local new_suggestion = suggestion.get() .. text
                suggestion.show(new_suggestion, row, col)
            end)
        end
    end
end

---@param route string
---@param payload string
function M.request_json(route, payload)
    return function(resume)
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
                resume(nil, vim.json.decode(result.stdout))
            else
                resume(result.stderr)
            end
        end)
    end
end

return M
