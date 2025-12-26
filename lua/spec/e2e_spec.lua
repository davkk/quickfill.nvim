local test_utils = require "spec.test_utils"

describe("end-to-end", function()
    local suggestion = require "lua.quickfill.suggestion"
    local cache = require "lua.quickfill.cache"
    local context = require "lua.quickfill.context"
    local request = require "lua.quickfill.request"

    local buf = test_utils.create_test_file()

    it("should do complete flow", function()
        vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { 20, 9 })

        request.suggest(buf)

        suggestion.show(" = next_val", 20, 9)

        local sug = suggestion.get()
        assert.is_not.equal("", sug, "Suggestion should be set")

        suggestion.accept()

        local local_context = context.get_local_context(buf)
        cache.add(local_context, sug)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.same("        b = next_val", lines[20], "Suggestion should be inserted into the line")

        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        assert.are.same(20, row)
        assert.are.same(8 + #sug, col, "Cursor should be at end of insertion")

        local cached = cache.get(local_context)
        assert.is_not.equal(nil, cached, "Suggestion should be cached")
        assert.are.same(sug, cached, "Cached suggestion should match what was shown")
    end)
end)
