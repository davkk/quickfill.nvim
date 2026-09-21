vim.g.quickfill = {
    n_prefix = 4,
    n_suffix = 4,
    enable_lsp = true,
}

local test_utils = require "spec.test_utils"

local context = require "quickfill.context"
local a = require "quickfill.async"
local utils = require "quickfill.utils"

local orig_get_clients = vim.lsp.get_clients
local orig_request_all = vim.lsp.buf_request_all

local function mock_clients()
    return {
        {
            flags = {},
            supports_method = function()
                return true
            end,
            stop = function() end,
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

local function mock_request_json(_, _)
    return function(step)
        step(nil, {
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

---@param s string?
---@return table<string, boolean>
local function completions_set(s)
    local set = {}
    if not s then return set end
    for _, w in ipairs(vim.split(s, "\n", { plain = true })) do
        if w ~= "" then set[w] = true end
    end
    return set
end

describe("context", function()
    local orig_request_json
    local buf

    setup(function()
        orig_request_json = utils.request_json
        vim.lsp.get_clients = mock_clients
        vim.lsp.buf_request_all = mock_request_all
        utils.request_json = mock_request_json
        buf = test_utils.create_test_file()
    end)

    teardown(function()
        vim.lsp.get_clients = orig_get_clients
        vim.lsp.buf_request_all = orig_request_all
        utils.request_json = orig_request_json
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("should get local context", function()
        vim.api.nvim_win_set_cursor(0, { 16, 10 })
        local result = context.get_local_context(buf)
        local expected = {
            middle = "    local ",
            prefix = "    end\n\n    local a = 0\n    local b = 1\n",
            suffix = "next_val\n\n    for i = 2, n do\n        next_val = a + b\n        a = b\n        b = next_val\n",
            curr_suffix = "next_val",
        }
        assert.are.same(expected, result)
    end)

    it(
        "should get lsp context",
        a.sync(function()
            local result = a.wait(context.get_lsp_context(buf, ""))
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
            assert.are.same(expected, result)
        end)
    )

    describe("get_buffers_context", function()
        local scratch_bufs = {}
        local saved_request_json

        local function create_scratch(lines)
            local b = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
            scratch_bufs[#scratch_bufs + 1] = b
            return b
        end

        before_each(function()
            saved_request_json = utils.request_json
        end)

        after_each(function()
            utils.request_json = saved_request_json
            for _, b in ipairs(scratch_bufs) do
                pcall(vim.api.nvim_buf_delete, b, { force = true })
            end
            scratch_bufs = {}
        end)

        it(
            "returns empty completions when keyword is less than 2 chars",
            a.sync(function()
                create_scratch { "qfzz_alpha qfzz_alpine qfzz_beta" }
                local result = a.wait(context.get_buffers_context("    "))
                assert.is_nil(result.completions)
                assert.is_nil(result.signatures)
            end)
        )

        it(
            "captures trailing keyword and filters open buffers by prefix",
            a.sync(function()
                create_scratch { "qfzz_alpha qfzz_alpine qfzz_beta" }
                local result = a.wait(context.get_buffers_context("    qfzz_alp"))
                local set = completions_set(result.completions)
                assert.is_true(set["qfzz_alpha"])
                assert.is_true(set["qfzz_alpine"])
                assert.is_nil(set["qfzz_beta"])
                assert.is_nil(result.signatures)
            end)
        )

        it(
            "strips non-keyword chars before capturing keyword",
            a.sync(function()
                create_scratch { "qfzz_alpha qfzz_alpine qfzz_beta" }
                local result = a.wait(context.get_buffers_context("  foo.qfzz_alp"))
                local set = completions_set(result.completions)
                assert.is_true(set["qfzz_alpha"])
                assert.is_true(set["qfzz_alpine"])
                assert.is_nil(set["qfzz_beta"])
            end)
        )

        it(
            "matches buffer words case-insensitively",
            a.sync(function()
                create_scratch { "Qfzz_CaseWord" }
                local result = a.wait(context.get_buffers_context("qfzz_case"))
                local set = completions_set(result.completions)
                assert.is_true(set["Qfzz_CaseWord"])
            end)
        )

        it(
            "returns nil completions and logit_bias when nothing matches",
            a.sync(function()
                create_scratch { "qfzz_alpha" }
                local result = a.wait(context.get_buffers_context("qfzz_nomatch_xyz"))
                assert.is_nil(result.completions)
                assert.is_nil(result.logit_bias)
                assert.is_nil(result.signatures)
            end)
        )

        it(
            "builds logit_bias from token pieces of buffer words",
            a.sync(function()
                create_scratch { "qfzz_alpha qfzz_alpine" }
                local seen_content
                utils.request_json = function(_, payload)
                    return function(step)
                        seen_content = vim.json.decode(payload).content
                        step(nil, {
                            tokens = {
                                { piece = "qfzz_alpha" },
                                { piece = "qfzz_alpha" },
                                { piece = "qfzz_alpine" },
                            },
                        })
                    end
                end
                local result = a.wait(context.get_buffers_context("qfzz_alp"))
                assert.are.same({ qfzz_alpha = 3, qfzz_alpine = 3 }, result.logit_bias)
                -- tokenize payload must be built from the captured buffer words
                table.sort(seen_content)
                assert.are.same({ "qfzz_alpha", "qfzz_alpine" }, seen_content)
            end)
        )

        it(
            "keeps completions but drops logit_bias on tokenize error",
            a.sync(function()
                create_scratch { "qfzz_alpha qfzz_alpine" }
                utils.request_json = function(_, _)
                    return function(step)
                        step("boom", nil)
                    end
                end
                local result = a.wait(context.get_buffers_context("qfzz_alp"))
                local set = completions_set(result.completions)
                assert.is_true(set["qfzz_alpha"])
                assert.is_nil(result.logit_bias)
            end)
        )
    end)
end)
