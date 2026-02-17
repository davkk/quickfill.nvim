local M = {}

local async = require "quickfill.async"
local utils = require "quickfill.utils"
local config = require "quickfill.config"
local suggestion = require "quickfill.suggestion"
local extra = require "quickfill.extra"
local logger = require "quickfill.logger"
local context = require "quickfill.context"
local cache = require "quickfill.cache"

---@type string?
local pending_request = nil

---@type uv.uv_process_t?
local handle = nil

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
---@param trie quickfill.Trie
---@param curr_node quickfill.TrieNode
---@return quickfill.TrieNode
local function on_stream_read(chunk, trie, curr_node)
    if #chunk < 6 or chunk:sub(1, 6) ~= "data: " then return curr_node end

    chunk = chunk:sub(7)
    local ok, resp = pcall(vim.json.decode, chunk)
    if not ok then return curr_node end

    local text = resp.content

    if config.stop_on_trigger_char and resp.stop then
        if resp.stop_type ~= "word" or vim.tbl_contains(config.stop_chars, resp.stopping_word) then return curr_node end
        text = resp.stopping_word
    end

    curr_node = trie:insert(text, curr_node)

    vim.schedule(function()
        local row, col = context.get_cursor_pos()
        local line_prefix = context.get_line_prefix()
        if pending_request then
            local node = trie:find(line_prefix)
            if node then
                local sug = trie:find_longest(node)
                if #sug > 0 then
                    suggestion.show(sug, row, col)
                else
                    suggestion.clear()
                end
            end
        end
    end)

    return curr_node
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

    pending_request = nil

    if handle then
        handle:close()
        handle = nil
    end
end

---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
---@param trie quickfill.Trie
---@param curr_node quickfill.TrieNode
function M.request_infill(local_context, lsp_context, trie, curr_node)
    if vim.bo.readonly or vim.bo.buftype ~= "" then return end

    M.cancel_stream()

    local stdout = assert(vim.uv.new_pipe(false), "failed to create stdout pipe")
    local stdin = assert(vim.uv.new_pipe(false), "failed to create stdin pipe")

    pending_request = local_context.middle

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
        if stdout and not stdout:is_closing() then
            stdout:read_stop()
            stdout:close()
        end
        if stdin and not stdin:is_closing() then stdin:read_stop() end
        on_stream_end(code)
    end)

    local payload = build_infill_payload(local_context, lsp_context)
    logger.info("request llama infill, stream start", { prompt = local_context.middle })
    stdin:write(payload, function()
        if stdin and not stdin:is_closing() then stdin:close() end
    end)

    stdout:read_start(function(_, chunk)
        if not chunk then return end
        curr_node = on_stream_read(chunk, trie, curr_node)
    end)
end

function M.cancel_stream()
    pending_request = nil
    if handle and not handle:is_closing() then
        handle:kill()
        handle:close()
    end
    handle = nil
end

---@param buf number
function M.suggest(buf)
    suggestion.clear()

    local row, col = context.get_cursor_pos()

    local local_context = context.get_local_context(buf)
    local trie = cache.get_or_add(local_context)

    local node = trie:find(local_context.middle)
    if node and next(node.children) then
        local sug = trie:find_longest(node)
        if #sug > 0 then
            suggestion.show(sug, row, col)
            return
        end
        suggestion.clear()
    end

    if pending_request then
        if local_context.middle:sub(1, #pending_request) == pending_request then return end
        M.cancel_stream()
    end

    node = trie:insert(local_context.middle)

    local sug = trie:find_longest(node)
    if #sug > 0 then
        suggestion.show(sug, row, col)
        return
    end
    suggestion.clear()

    async.async(function()
        local lsp_context = context.get_lsp_context(buf, local_context.middle)
        vim.schedule(function()
            M.request_infill(local_context, lsp_context, trie, node)
        end)
    end)()
end

return M
