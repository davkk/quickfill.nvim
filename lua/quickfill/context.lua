local M = {}

local config = require "quickfill.config"
local async = require "quickfill.async"
local utils = require "quickfill.utils"
local logger = require "quickfill.logger"

---@class quickfill.LspCompletion
---@field label string
---@field text string

---@type table<number, table<string, function>>
local active_cancels = {}

---@param buf number
---@return quickfill.LocalContext
function M.get_local_context(buf)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local prefix = table.concat(lines, "\n", math.max(0, row - 1 - config.n_prefix) + 1, math.max(0, row - 1)) .. "\n"
    local curr_prefix = lines[row]:sub(1, col)

    local curr_suffix = lines[row]:sub(col + 1)
    local suffix = (#curr_suffix > 0 and curr_suffix .. "\n" or "")
        .. "\n"
        .. table.concat(lines, "\n", math.min(#lines + 1, row + 1), math.min(#lines, row + config.n_suffix))
        .. "\n"

    logger.info("context local", {
        prefix = prefix:sub(-10):gsub("\n", "\\n"),
        middle = curr_prefix:gsub("\n", "\\n"),
        suffix = suffix:sub(1, 10):gsub("\n", "\\n"),
    })
    return { prefix = prefix, middle = curr_prefix, suffix = suffix }
end

---@param method string
---@return boolean
local function is_supported(buf, method)
    for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
        if client:supports_method(method) then return true end
    end
    return false
end

---@param method string
---@param buf number
---@param params table
local function lsp_request(buf, method, params)
    return vim.schedule_wrap(function(resume)
        logger.info("context lsp send", { buf = buf, method = method, params = params })

        if not is_supported(buf, method) then
            logger.warn("context lsp, buffer does not support method", { buf = buf, method = method, params = params })
            resume {}
            return
        end

        if active_cancels[buf] and active_cancels[buf][method] then
            pcall(active_cancels[buf][method])
            active_cancels[buf][method] = nil
        end

        local done = false
        local timer = assert(vim.uv.new_timer(), "failed to create timer")

        local cancel_lsp_req = vim.lsp.buf_request_all(buf, method, params, function(results)
            if not done then
                done = true
                if active_cancels[buf] then active_cancels[buf][method] = nil end
                timer:stop()
                timer:close()
                logger.info("context lsp receive", { buf = buf, method = method, params = params, results = results })
                resume(results)
            end
        end)

        active_cancels[buf] = active_cancels[buf] or {}
        active_cancels[buf][method] = cancel_lsp_req
        timer:start(300, 0, function()
            if not done then
                done = true
                if active_cancels[buf] then active_cancels[buf][method] = nil end
                if cancel_lsp_req then vim.schedule(cancel_lsp_req) end
                timer:stop()
                timer:close()
                logger.warn("context lsp timeout", { buf = buf, method = method, params = params })
                resume {}
            end
        end)
    end)
end

---@return boolean
local function is_function(kind)
    return kind == vim.lsp.protocol.CompletionItemKind.Function --
        or kind == vim.lsp.protocol.CompletionItemKind.Method
end

---@param buf number
---@param params lsp.TextDocumentPositionParams
---@return table<string>
local function get_lsp_signature_help(buf, params)
    ---@type table<integer, { err: (lsp.ResponseError)?, result: lsp.SignatureHelp, context: lsp.HandlerContext }>
    local sig_resp = async.await(lsp_request(buf, vim.lsp.protocol.Methods.textDocument_signatureHelp, params)) or {}
    local signatures = {}
    for _, resp in ipairs(sig_resp) do
        if resp.err then
            logger.error("context lsp", { buf = buf, method = "signatureHelp", error = resp.err, params = params })
            vim.notify(("error while lsp signature help: %s"):format(resp.err.message), vim.diagnostic.severity.ERROR)
            break
        end
        if resp.result then
            logger.info("context lsp", { buf = buf, method = "signatureHelp", params = params })
            for _, sig in ipairs(resp.result.signatures or resp.result or {}) do
                local signature = {}
                if sig.label then signature[#signature + 1] = sig.label end
                signatures[#signatures + 1] = table.concat(signature, "\n")
            end
        end
    end
    return signatures
end

---@param buf number
---@param params lsp.TextDocumentPositionParams
---@param line_prefix string
---@return table<quickfill.LspCompletion>
local function get_lsp_completion(buf, params, line_prefix)
    ---@type table<integer, { err: (lsp.ResponseError)?, result: lsp.CompletionList, context: lsp.HandlerContext }>
    local cmp_resp = async.await(lsp_request(buf, vim.lsp.protocol.Methods.textDocument_completion, params)) or {}

    local re = vim.regex [[\k*$]]
    local s, e = re:match_str(line_prefix)
    local keyword = s and line_prefix:sub(s + 1, e) or ""

    local num_items = 0
    local completions = {}
    for _, resp in ipairs(cmp_resp) do
        if resp.err then
            logger.error("context lsp", { buf = buf, method = "signatureHelp", error = resp.err, params = params })
            vim.notify(("error while lsp completion: %s"):format(resp.err.message), vim.diagnostic.severity.ERROR)
            break
        end
        if resp.result then
            logger.info("context lsp", { buf = buf, method = "completion", params = params })
            for _, item in ipairs(resp.result.items or resp.result or {}) do
                if num_items >= config.max_lsp_completion_items then break end
                if
                    item.kind ~= vim.lsp.protocol.CompletionItemKind.Snippet
                    and item.label:sub(1, #keyword) == keyword
                then
                    local label = ("%s %s"):format(
                        vim.lsp.protocol.CompletionItemKind[item.kind or 1]:lower(),
                        item.label
                    )
                    if is_function(item.kind) and not label:match "%(" then label = label .. "(" end
                    if item.detail then label = ("%s -> %s"):format(label, item.detail) end

                    local text = (item.filterText or item.insertText or item.label):gsub("^%.", ""):sub(#keyword + 1)
                    if is_function(item.kind) and not text:match "%(" then text = text .. "(" end

                    completions[#completions + 1] = {
                        label = label,
                        text = text,
                    }
                    num_items = num_items + 1
                end
            end
        end
    end
    return completions
end

---@param completions table<quickfill.LspCompletion>
local function get_logit_bias(completions)
    local content = vim.tbl_map(function(item)
        return item.text
    end, completions)
    local err, tokenize_resp = async.await(utils.request_json(
        "tokenize",
        vim.json.encode {
            content = content,
            with_pieces = true,
        }
    ))
    if err ~= nil then return {} end

    local logit_bias = {}
    for _, token in ipairs(tokenize_resp.tokens or {}) do
        local piece = token.piece
        if not logit_bias[piece] then logit_bias[piece] = 3 end
    end
    return logit_bias
end

---@param buf number
---@param params lsp.TextDocumentPositionParams?
---@param line_prefix string
---@return quickfill.LspContext
function M.get_lsp_context(buf, params, line_prefix)
    params = params or vim.lsp.util.make_position_params(0, "utf-8")

    local lsp_signatures = config.lsp_signature_help and get_lsp_signature_help(buf, params) or {}
    local lsp_completions = config.lsp_completion and get_lsp_completion(buf, params, line_prefix) or {}
    local logit_bias = #lsp_completions > 0 and get_logit_bias(lsp_completions) or {}

    local cmp_labels = vim.tbl_map(function(item)
        return item.label
    end, lsp_completions)

    return {
        logit_bias = vim.tbl_count(logit_bias) > 0 and logit_bias or nil,
        completions = #cmp_labels > 0 and table.concat(cmp_labels, "\n") .. "\n" or nil,
        signatures = #lsp_signatures > 0 and table.concat(lsp_signatures, "\n") .. "\n" or nil,
    }
end

return M
