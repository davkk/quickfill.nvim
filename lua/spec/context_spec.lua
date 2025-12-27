vim.g.quickfill = {
    n_prefix = 4,
    n_suffix = 4,
}

local test_utils = require "spec.test_utils"

local context = require "quickfill.context"
local async = require "quickfill.async"
local utils = require "quickfill.utils"

local function mock_clients()
    return {
        {
            flags = {},
            supports_method = function()
                return true
            end,
        },
    }
end

local function mock_request_all(_, method, _, callback)
    local results = { { result = {} }, { result = {} } }
    if method == vim.lsp.protocol.Methods.textDocument_completion then
        local items = {
            {
                label = "hello",
                kind = vim.lsp.protocol.CompletionItemKind.Function,
            },
            {
                label = "world",
                kind = vim.lsp.protocol.CompletionItemKind.Method,
            },
            {
                label = "foo",
                kind = vim.lsp.protocol.CompletionItemKind.Class,
                detail = "this is a lovely class",
            },
            {
                label = "bar",
            },
        }
        results[1].result.items = items
        results[2].result = items
    elseif method == vim.lsp.protocol.Methods.textDocument_signatureHelp then
        local signatures = {
            {
                label = "hello(world, foo, bar)",
            },
            {
                label = "foo(bar)",
            },
        }
        results[1].result.signatures = signatures
        results[2].result = signatures
    end
    callback(results, {})
end

local function mock_request_json()
    return function(resume)
        resume(nil, {
            tokens = {
                { piece = "(" },
                { piece = "bar" },
                { piece = "bar" },
                { piece = "foo" },
                { piece = "hello" },
                { piece = "hello" },
                { piece = "hello" },
                { piece = "world" },
            },
        })
    end
end

describe("context", function()
    vim.lsp.get_clients = mock_clients
    vim.lsp.buf_request_all = mock_request_all
    utils.request_json = mock_request_json

    local buf = test_utils.create_test_file()

    it("should get local context", function()
        vim.api.nvim_win_set_cursor(0, { 16, 10 })
        local result = context.get_local_context(buf)
        local expected = {
            middle = "    local ",
            prefix = "    end\n\n    local a = 0\n    local b = 1\n",
            suffix = "next_val\n\n    for i = 2, n do\n        next_val = a + b\n        a = b\n        b = next_val\n",
        }
        assert.are.same(expected, result)
    end)

    it("should get lsp context", function()
        local _test_done = false
        local err = nil
        async.async(function()
            local result = context.get_lsp_context(buf, "")
            local expected = {
                logit_bias = {
                    ["("] = 3,
                    ["bar"] = 3,
                    ["foo"] = 3,
                    ["hello"] = 3,
                    ["world"] = 3,
                },
                signatures = string.rep("hello(world, foo, bar)\nfoo(bar)\n", 2),
                completions = string.rep(
                    "function hello(\nmethod world(\nclass foo -> this is a lovely class\ntext bar\n",
                    2
                ),
            }
            _, err = pcall(function()
                _test_done = true
                assert.are.same(expected, result)
            end)
        end)()
        vim.wait(1000, function()
            return _test_done
        end)
        assert.is_falsy(err)
    end)
end)
