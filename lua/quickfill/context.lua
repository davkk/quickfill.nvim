local M = {}

local config = require "quickfill.config"
local async = require "quickfill.async"
local request = require "quickfill.request"

---@return quickfill.LocalContext
function M.get_local_context()
    local buf = vim.api.nvim_get_current_buf()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local prefix = table.concat(lines, "\n", math.max(0, row - 1 - config.N_PREFIX) + 1, math.max(0, row - 1)) .. "\n"
    local curr_prefix = lines[row]:sub(1, col)

    local curr_suffix = lines[row]:sub(col + 1)
    local suffix = (#curr_suffix > 0 and curr_suffix .. "\n" or "")
        .. "\n"
        .. table.concat(lines, "\n", math.min(#lines + 1, row + 1), math.min(#lines, row + config.N_SUFFIX + 1))
        .. "\n"

    return { prefix = prefix, middle = curr_prefix, suffix = suffix }
end

---@param method string
---@param buf number
---@param params table
local function lsp_request(buf, method, params)
    return vim.schedule_wrap(function(resume)
        local supported = false
        for _, client in ipairs(vim.lsp.get_clients { bufnr = 0 }) do
            if client:supports_method(method) then
                supported = true
                break
            end
        end
        if not supported then
            resume {}
            return
        end
        local done = false
        local timer = vim.uv.new_timer() ---@cast timer uv.uv_timer_t
        local cancel_lsp_req = vim.lsp.buf_request_all(buf, method, params, function(results)
            if not done then
                done = true
                timer:stop()
                timer:close()
                resume(results)
            end
        end)
        timer:start(500, 0, function()
            if not done then
                done = true
                vim.schedule(cancel_lsp_req)
                timer:stop()
                timer:close()
                resume {}
            end
        end)
    end)
end

local function is_function(kind)
    return kind == vim.lsp.protocol.CompletionItemKind.Function --
        or kind == vim.lsp.protocol.CompletionItemKind.Method
end

---@param line string
---@return quickfill.LspContext
function M.get_lsp_context(line)
    local params = vim.lsp.util.make_position_params(0, "utf-8")

    ---@type table<integer, { err: (lsp.ResponseError)?, result: lsp.SignatureHelp, context: lsp.HandlerContext }>
    local sig_resp = async.await(lsp_request(0, "textDocument/signatureHelp", params)) or {}
    local signatures = {}
    for _, resp in ipairs(sig_resp) do
        if resp.err then
            break
        end
        if resp.result then
            for _, sig in ipairs(resp.result.signatures or resp.result or {}) do
                local signature = {}
                if sig.label then
                    signature[#signature + 1] = sig.label
                end
                signatures[#signatures + 1] = table.concat(signature, "\n")
            end
        end
    end

    ---@type table<integer, { err: (lsp.ResponseError)?, result: lsp.CompletionList, context: lsp.HandlerContext }>
    local cmp_resp = async.await(lsp_request(0, "textDocument/completion", params)) or {}
    local cmp_items = {}
    for _, resp in ipairs(cmp_resp) do
        if resp.err then
            break
        end
        if resp.result then
            for _, item in ipairs(resp.result.items or resp.result or {}) do
                cmp_items[#cmp_items + 1] = item
            end
        end
    end

    local re = vim.regex [[\k*$]]
    local s, e = re:match_str(line)
    local keyword = s and line:sub(s + 1, e) or ""

    local completions = {}
    local tokenize = {}

    local num_items = 0
    for _, v in ipairs(cmp_items) do
        if num_items > 20 then
            break
        end
        if v.kind ~= vim.lsp.protocol.CompletionItemKind.Snippet and v.label:sub(1, #keyword) == keyword then
            local label = ("%s %s"):format(vim.lsp.protocol.CompletionItemKind[v.kind]:lower(), v.label)
            if is_function(v.kind) and not label:match "%(" then
                label = label .. "("
            end
            if v.detail then
                label = ("%s -> %s"):format(label, v.detail)
            end
            completions[#completions + 1] = label

            local content = (v.filterText or v.insertText or v.label):gsub("^%.", ""):sub(#keyword + 1)
            if is_function(v.kind) and not content:match "%(" then
                content = content .. "("
            end
            tokenize[#tokenize + 1] = content

            num_items = num_items + 1
        end
    end

    local err, tokenize_resp = async.await(request.request_json(
        "tokenize",
        vim.json.encode {
            content = tokenize,
            with_pieces = true,
        }
    ))
    if err ~= nil then
        return {}
    end

    local logit_bias = {}
    for _, token in ipairs(tokenize_resp.tokens or {}) do
        local piece = token.piece
        if not logit_bias[piece] then
            logit_bias[piece] = 3
        end
    end

    return {
        logit_bias = logit_bias,
        completions = #completions > 0 and table.concat(completions, "\n") .. "\n" or nil,
        signatures = #signatures > 0 and table.concat(signatures, "\n") .. "\n" or nil,
    }
end

return M
