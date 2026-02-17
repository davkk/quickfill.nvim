local M = {}

local async = require "quickfill.async"
local utils = require "quickfill.utils"
local config = require "quickfill.config"
local cache = require "quickfill.cache"
local suggestion = require "quickfill.suggestion"
local extra = require "quickfill.extra"
local logger = require "quickfill.logger"
local context = require "quickfill.context"
local Trie = require "quickfill.trie"

---@class quickfill.ActiveRequest
---@field req_id number
---@field handle uv.uv_process_t
---@field stdout uv.uv_pipe_t
---@field stdin uv.uv_pipe_t
---@field trie quickfill.Trie
---@field node quickfill.TrieNode
---@field current_node quickfill.TrieNode[]
---@field local_context quickfill.LocalContext

---@type table<number, quickfill.ActiveRequest>
local active_requests = {}

---@type table<number, quickfill.Trie?>
M.tries = {}

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

---@param req quickfill.ActiveRequest
---@param chunk string
local function on_stream_read(req, chunk)
    assert(chunk, "chunk should be defined")

    if not active_requests[req.req_id] then return end
    if #chunk < 6 or chunk:sub(1, 6) ~= "data: " then return end

    chunk = chunk:sub(7)
    local ok, resp = pcall(vim.json.decode, chunk)
    if not ok then return end

    local text = resp.content

    if config.stop_on_trigger_char and resp.stop then
        if resp.stop_type ~= "word" or vim.tbl_contains(config.stop_chars, resp.stopping_word) then return end
        text = resp.stopping_word
    end

    req.current_node[1] = req.trie:insert(text, req.current_node[1])

    vim.schedule(function()
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local current_middle = context.get_local_context(0).middle
        local current_node = req.trie:find(current_middle)
        if current_node then
            local sug = req.trie:find_longest(current_node)
            if #sug > 0 then suggestion.show(sug, row, col) end
        end
    end)
end

---@param req quickfill.ActiveRequest
---@param code number
local function on_stream_end(req, code)
    if code ~= 0 then
        logger.error("request llama infill, curl error", { code = code, req_id = req.req_id })
        vim.schedule(function()
            vim.notify(("curl exited with code %d"):format(code), vim.diagnostic.severity.ERROR)
        end)
    end

    if req.stdout then
        req.stdout:read_stop()
        req.stdout:close()
    end
    if req.handle then req.handle:close() end

    active_requests[req.req_id] = nil

    local sug = suggestion.get()
    if #sug == 0 then return end

    logger.info("request llama infill, stream stop", { req_id = req.req_id, suggestion = sug })

    vim.schedule(function()
        cache.add(req.local_context, sug)
    end)
end

vim.keymap.set("n", "<leader>pt", function()
    print(vim.inspect(M.tries))
    print("active requests: " .. vim.tbl_count(active_requests))
end)

---@param req_id number
---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
---@param trie quickfill.Trie
---@param node quickfill.TrieNode
local function request_infill(req_id, local_context, lsp_context, trie, node)
    if vim.bo.readonly or vim.bo.buftype ~= "" then return end

    local stdout = assert(vim.uv.new_pipe(false), "failed to create stdout pipe")
    local stdin = assert(vim.uv.new_pipe(false), "failed to create stdin pipe")

    -- Track current position in trie as we receive stream chunks
    local current_node = { node }

    ---@type quickfill.ActiveRequest
    local req = {
        req_id = req_id,
        trie = trie,
        node = node,
        current_node = current_node,
        local_context = local_context,
    }

    active_requests[req_id] = req

    local handle
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
        req.handle = handle
        req.stdout = stdout
        req.stdin = stdin
        on_stream_end(req, code)
    end)

    req.handle = handle
    req.stdout = stdout
    req.stdin = stdin

    local payload = build_infill_payload(local_context, lsp_context)
    logger.info("request llama infill, stream start", { req_id = req_id, prompt = local_context.middle })
    stdin:write(payload, function()
        stdin:close()
    end)

    stdout:read_start(function(_, chunk)
        if not chunk then return end
        on_stream_read(req, chunk)
    end)
end

M.request_infill = request_infill

function M.cancel_stream()
    for req_id, req in pairs(active_requests) do
        if req.handle and req.handle:is_active() and not req.handle:is_closing() then
            pcall(req.handle.kill, req.handle)
        end
        if req.handle and not req.handle:is_closing() then pcall(req.handle.close, req.handle) end
        if req.stdin and not req.stdin:is_closing() then pcall(req.stdin.close, req.stdin) end
        if req.stdout and not req.stdout:is_closing() then
            req.stdout:read_stop()
            pcall(req.stdout.close, req.stdout)
        end
        active_requests[req_id] = nil
    end
end

local current_req = 0

---@return number
function M.next_request_id()
    current_req = current_req + 1
    return current_req
end

---@param buf number
function M.suggest(buf)
    suggestion.clear()

    local req_id = M.next_request_id()

    ---@type number, number
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))

    local local_context = context.get_local_context(buf)

    if not M.tries[row] then M.tries[row] = Trie:new() end
    local trie = M.tries[row] ---@cast trie quickfill.Trie

    local node = trie:find(local_context.middle)
    if node and (node.is_end or next(node.children)) then
        local sug = trie:find_longest(node)
        if #sug > 0 then
            suggestion.show(sug, row, col)
            return
        end
    end

    node = trie:insert(local_context.middle)

    local sug = trie:find_longest(node)
    if #sug > 0 then
        suggestion.show(sug, row, col)
        return
    end

    M.request_infill(req_id, local_context, { logit_bias = {} }, trie, node)
end

return M
