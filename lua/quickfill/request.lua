local M = {}

local a = require "quickfill.async"
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
        for _, char in ipairs(config.trigger_chars) do
            stop[#stop + 1] = char
        end
    end

    return vim.json.encode {
        model = config.model,
        input_prefix = local_context.prefix,
        prompt = local_context.middle,
        input_suffix = local_context.suffix,
        input_extra = input_extra,
        cache_prompt = true,
        n_predict = config.n_predict,
        temperature = config.temperature,
        top_k = config.top_k,
        top_p = config.top_p,
        repeat_penalty = config.repeat_penalty,
        samplers = { "top_k", "top_p", "temperature", "infill" },
        logit_bias = lsp_context.logit_bias,
        t_max_predict_ms = 500,
        stream = true,
        stop = #local_context.curr_suffix > 0 and stop or {},
    }
end

---@param trie quickfill.Trie
---@param prefix string
---@param typed string
---@return boolean
local function show_pending_suggestion(trie, prefix, typed)
    if #typed < #prefix then return false end
    if typed:sub(1, #prefix) ~= prefix then return false end

    local node, tail = trie:find(prefix)
    if not node then return false end

    local sug = trie:find_longest(node, tail)
    if #sug == 0 then return false end

    local row, col = context.get_cursor_pos()
    local typed_extra = typed:sub(#prefix + 1)

    if #typed_extra == 0 then
        suggestion.show(sug, row, col)
        return true
    end

    if sug:sub(1, #typed_extra) == typed_extra then
        local remaining = sug:sub(#typed_extra + 1)
        if #remaining > 0 then
            suggestion.show(remaining, row, col)
            return true
        end
    end

    return false
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
    if not text then return curr_node end

    if config.stop_on_trigger_char and resp.stop then
        if resp.stop_type ~= "word" or vim.tbl_contains(config.stop_chars, resp.stopping_word) then return curr_node end
        text = resp.stopping_word
    end

    curr_node = trie:insert(text, curr_node)

    local request_prefix = pending_request
    vim.schedule(function()
        if not request_prefix or pending_request ~= request_prefix then return end
        logger.debug("show pending suggestion", { pending_request = pending_request, text = text })
        show_pending_suggestion(trie, request_prefix, context.get_line_prefix())
    end)

    return curr_node
end

---@param buf number
---@param code number
local function on_stream_end(buf, code)
    if code ~= 0 then
        logger.error("request llama infill, curl error", { buf = buf, code = code })
        vim.schedule(function()
            vim.notify(("curl exited with code %d"):format(code), vim.diagnostic.severity.ERROR)
        end)
        return
    end

    vim.schedule(function()
        local lines = vim.split(suggestion.get(), "\n")
        local local_context = context.get_local_context(buf)
        local prefix_lines = vim.split(local_context.prefix, "\n")
        lines[1] = prefix_lines[#prefix_lines] .. local_context.middle .. lines[1]
        table.remove(prefix_lines, #prefix_lines)
        for idx = 2, #lines do
            table.remove(prefix_lines, 1)
            prefix_lines[#prefix_lines + 1] = lines[idx - 1]
            ---@type quickfill.LocalContext
            local new_context = {
                prefix = table.concat(prefix_lines, "\n") .. "\n",
                middle = "",
                suffix = local_context.suffix,
                curr_suffix = "",
            }
            local trie = cache.get_or_add(new_context)
            trie:insert(table.concat({ unpack(lines, idx) }, "\n"))
        end
    end)
end

---@param buf number
---@param local_context quickfill.LocalContext
---@param lsp_context quickfill.LspContext
---@param trie quickfill.Trie
---@param curr_node quickfill.TrieNode
function M.request_infill(buf, local_context, lsp_context, trie, curr_node)
    if vim.bo.readonly or vim.bo.buftype ~= "" then return end

    if handle and not handle:is_closing() then
        handle:kill()
        handle = nil
    end

    pending_request = local_context.middle

    local stdout = assert(vim.uv.new_pipe(false), "failed to create stdout pipe")
    local stdin = assert(vim.uv.new_pipe(false), "failed to create stdin pipe")

    local h
    h = vim.uv.spawn("curl", {
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
        logger.debug(
            "request llama infill, stream end",
            { handle = handle and handle:fileno() or vim.NIL, buf = buf, code = code }
        )
        if stdout and not stdout:is_closing() then
            stdout:read_stop()
            stdout:close()
        end
        if stdin and not stdin:is_closing() then
            stdin:read_stop()
            stdin:close()
        end
        if h and not h:is_closing() then h:close() end
        if handle == h then handle = nil end
        if pending_request then on_stream_end(buf, code) end
        pending_request = nil
    end)
    handle = h

    local payload = build_infill_payload(local_context, lsp_context)
    logger.debug(
        "request llama infill, stream start",
        { handle = handle and handle:fileno() or vim.NIL, prompt = local_context.middle }
    )
    stdin:write(payload, function()
        if stdin and not stdin:is_closing() then stdin:close() end
    end)

    stdout:read_start(function(_, chunk)
        if not chunk then return end
        curr_node = on_stream_read(chunk, trie, curr_node)
    end)
end

function M.cancel_stream()
    logger.debug(
        "request infill, cancel stream",
        { handle = handle and handle:fileno() or vim.NIL, pending_request = pending_request }
    )
    pending_request = nil
    if handle and not handle:is_closing() then
        handle:kill()
        handle = nil
    end
end

---@param buf number
function M.suggest(buf)
    local row, col = context.get_cursor_pos()
    local local_context = context.get_local_context(buf)
    local trie = cache.get_or_add(local_context)

    local node, tail = trie:find(local_context.middle)
    if node and next(node.children) then
        local sug = trie:find_longest(node, tail)
        if #sug > 0 then
            suggestion.show(sug, row, col)
            return
        end
    end

    if pending_request then
        suggestion.clear()
        return
    end

    local insert_node = trie:insert(local_context.middle)
    local sug = trie:find_longest(insert_node)
    if #sug > 0 then
        suggestion.show(sug, row, col)
        return
    end
    suggestion.clear()

    a.pong(function()
        local lsp_context = a.wait(context.get_lsp_context(buf, local_context.middle))

        a.wait(a.main_loop)

        local curr_context = context.get_local_context(buf)
        if curr_context.middle ~= local_context.middle then
            M.cancel_stream()
            M.suggest(buf)
            return
        end

        if not pending_request then
            M.request_infill(buf, local_context, lsp_context, trie, insert_node)
        end
    end, nil)
end

return M
