local M = {}

local utils = require "quickfill.utils"
local state = require "quickfill.state"
local config = require "quickfill.config"
local cache = require "quickfill.cache"
local suggestion = require "quickfill.suggestion"

function M.cancel_stream()
    pcall(function()
        if state.handle and state.handle:is_active() then
            state.handle:kill()
            state.handle:close()
            state.handle = nil
        end
        if state.stdin then
            state.stdin:close()
            state.stdin = nil
        end
        if state.stdout then
            state.stdout:close()
            state.stdout = nil
        end
    end)
end

---@param request_id number
---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
function M.request_infill(request_id, local_context, lsp_context)
    if vim.bo.readonly or vim.bo.buftype ~= "" then
        return
    end

    if request_id ~= state.current_request_id then
        return
    end

    M.cancel_stream()
    suggestion.clear()

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))

    local input_extra = {}
    for _, chunk in ipairs(state.chunks) do
        input_extra[#input_extra + 1] = {
            filename = chunk.filename,
            text = table.concat(chunk.lines, "\n") .. "\n",
        }
    end
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

    state.stdout = vim.uv.new_pipe(false)
    state.stdin = vim.uv.new_pipe(false)
    state.handle = vim.uv.spawn("curl", {
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
        stdio = { state.stdin, state.stdout },
    }, function(code)
        if state.stdout then
            state.stdout:close()
            state.stdout = nil
        end
        if state.handle then
            state.handle:close()
            state.handle = nil
        end
        if code ~= 0 then
            vim.schedule(function()
                vim.notify(("curl exited with code %d"):format(code), vim.diagnostic.severity.ERROR)
            end)
        end
    end)
    state.stdin:write(payload, function()
        state.stdin:close()
    end)
    state.stdout:read_start(function(_, chunk)
        if chunk then
            M.on_stream_chunk(chunk, local_context, request_id, row, col)
        end
    end)
end

---@param chunk string
---@param local_context quickfill.LocalContext
---@param request_id number
---@param row number
---@param col number
function M.on_stream_chunk(chunk, local_context, request_id, row, col)
    if request_id ~= state.current_request_id then
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
            state.suggestion = state.suggestion .. text
            vim.schedule(function()
                if request_id ~= state.current_request_id then
                    return
                end
                suggestion.show(state.suggestion, row, col)
                if state.suggestion and #state.suggestion > 0 then
                    cache.cache_add(local_context, state.suggestion)
                end
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
