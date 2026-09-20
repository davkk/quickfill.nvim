local a = require "quickfill.async"
local extra = require "quickfill.extra"
local config = require "quickfill.config"
local utils = require "quickfill.utils"

describe("extra chunk similarity", function()
    local orig_request_json = utils.request_json
    local orig_relative_path = utils.relative_path
    local orig_system = vim.system
    local orig_config = {
        extra_chunks = config.extra_chunks,
        max_extra_chunks = config.max_extra_chunks,
        chunk_lines = config.chunk_lines,
        model = config.model,
    }
    local bufs = {}

    local function clear_chunks()
        local chunks = extra.get_chunks()
        while #chunks > 0 do
            table.remove(chunks, 1)
        end
    end

    before_each(function()
        clear_chunks()

        config.extra_chunks = true
        config.max_extra_chunks = 6
        config.chunk_lines = 6
        config.model = "test-model"

        utils.request_json = function(_, _)
            return function(step)
                step(nil, {})
            end
        end

        utils.relative_path = function(_, _)
            return "test.lua"
        end

        vim.system = function(_)
            return {
                wait = function()
                    return { stdout = "" }
                end,
            }
        end
    end)

    after_each(function()
        utils.request_json = orig_request_json
        utils.relative_path = orig_relative_path
        vim.system = orig_system
        for k, v in pairs(orig_config) do
            config[k] = v
        end
        clear_chunks()
        for _, buf in ipairs(bufs) do
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
        bufs = {}
    end)

    local function create_buf(lines)
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        bufs[#bufs + 1] = buf
        return buf
    end

    local function add_chunk(buf, row)
        return extra.try_add_chunk(buf, row)
    end

    it(
        "should remove similar chunk when similarity > 0.55",
        a.sync(function()
            local buf1 = create_buf { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }
            a.wait(add_chunk(buf1, 4))
            assert.are.equal(1, #extra.get_chunks())

            -- modify buffer to be 6/7 overlap (=0.85) with previous chunk
            vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "a", "b", "c", "d", "e", "f", "x", "h", "i", "j" })
            a.wait(add_chunk(buf1, 4))

            -- old similar chunk should have been removed, only new chunk remains
            assert.are.equal(1, #extra.get_chunks())
            assert.are.same({ "a", "b", "c", "d", "e", "f", "x" }, extra.get_chunks()[1].lines)
        end)
    )

    it(
        "should keep dissimilar chunks when similarity <= 0.55",
        a.sync(function()
            local buf1 = create_buf { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }
            a.wait(add_chunk(buf1, 4))
            assert.are.equal(1, #extra.get_chunks())

            vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "u", "v", "w", "x", "y", "z", "q", "r", "s", "t" })
            a.wait(add_chunk(buf1, 4))

            assert.are.equal(2, #extra.get_chunks())
        end)
    )

    it(
        "should enforce max_extra_chunks eviction",
        a.sync(function()
            config.max_extra_chunks = 2
            local buf = create_buf { "a1", "b1", "c1", "d1", "e1", "f1", "g1", "h1", "i1", "j1" }
            a.wait(add_chunk(buf, 4))
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2", "i2", "j2" })
            a.wait(add_chunk(buf, 4))
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a3", "b3", "c3", "d3", "e3", "f3", "g3", "h3", "i3", "j3" })
            a.wait(add_chunk(buf, 4))

            assert.are.equal(2, #extra.get_chunks())
            -- oldest chunk evicted
            assert.are.same({ "a2", "b2", "c2", "d2", "e2", "f2", "g2" }, extra.get_chunks()[1].lines)
            assert.are.same({ "a3", "b3", "c3", "d3", "e3", "f3", "g3" }, extra.get_chunks()[2].lines)
        end)
    )

    it(
        "should remove all similar chunks when multiple existing chunks are similar (regression for ipairs mutation)",
        a.sync(function()
            -- manually inject two identical chunks to simulate state where two entries are similar to new chunk
            local chunks = extra.get_chunks()
            chunks[#chunks + 1] = { filename = "test.lua", lines = { "a", "b", "c", "d", "e", "f", "g" } }
            chunks[#chunks + 1] = { filename = "test.lua", lines = { "a", "b", "c", "d", "e", "f", "g" } }
            assert.are.equal(2, #chunks)

            local buf = create_buf { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }
            a.wait(add_chunk(buf, 4))

            -- both old similar chunks should be removed, leaving only the new one
            assert.are.equal(1, #extra.get_chunks())
        end)
    )
end)
