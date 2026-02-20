local Trie = require "quickfill.trie"

describe("trie", function()
    describe("insert", function()
        it("should insert single word as a single edge node", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie.root.children["h"]
            assert.is_not_nil(node)
            assert.are.equal("hello", node.value)
            assert.are.same({}, node.children)
        end)

        it("should split edge and share common prefix for multiple words", function()
            local trie = Trie.new()
            trie:insert "hello"
            trie:insert "help"

            local h_node = trie.root.children["h"]
            assert.is_not_nil(h_node)
            assert.are.equal("hel", h_node.value)
            assert.is_not_nil(h_node.children["l"])
            assert.is_not_nil(h_node.children["p"])
            assert.are.equal("lo", h_node.children["l"].value)
            assert.are.equal("p", h_node.children["p"].value)
        end)

        it("should return node when inserting empty string", function()
            local trie = Trie.new()
            local result = trie:insert ""
            assert.are.equal(trie.root, result)
        end)

        it("should update longest_child and longest_depth on root after insert", function()
            local trie = Trie.new()
            trie:insert "hi"

            assert.are.equal("h", trie.root.longest_child)
            assert.are.equal(2, trie.root.longest_depth)

            local h_node = trie.root.children["h"]
            assert.is_nil(h_node.longest_child)
            assert.are.equal(0, h_node.longest_depth)
        end)

        it("should update longest when inserting longer word", function()
            local trie = Trie.new()
            trie:insert "hi"
            trie:insert "hello"

            assert.are.equal("h", trie.root.longest_child)
            assert.are.equal(5, trie.root.longest_depth)
        end)

        it("should insert with custom starting node", function()
            local trie = Trie.new()
            trie:insert "ab"

            local ab_node = trie:find "ab"
            trie:insert("cde", ab_node)

            assert.are.equal("cde", trie:find_longest(ab_node))
            assert.are.equal("abcde", trie:find_longest())
        end)
    end)

    describe("find", function()
        it("should find existing path and return correct node", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie:find "hello" ---@cast node quickfill.TrieNode
            assert.is_not_nil(node)
            assert.are.same({}, node.children)
            assert.are.equal("hello", node.value)
        end)

        it("should return nil for non-existent path", function()
            local trie = Trie.new()
            trie:insert "hello"

            assert.is_nil(trie:find "world")
            assert.is_nil(trie:find "hellx")
        end)

        it("should find intermediate node when query ends mid-edge", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie:find "hel" ---@cast node quickfill.TrieNode
            assert.is_not_nil(node)
            assert.are.equal("hello", node.value)
        end)

        it("should find word among multiple words", function()
            local trie = Trie.new()
            trie:insert "hello"
            trie:insert "help"
            trie:insert "world"

            assert.is_not_nil(trie:find "hello")
            assert.is_not_nil(trie:find "help")
            assert.is_not_nil(trie:find "world")
            assert.is_nil(trie:find "hells")
        end)
    end)

    describe("find_longest", function()
        it("should return longest word from root", function()
            local trie = Trie.new()
            trie:insert "hi"
            trie:insert "hello"

            assert.are.equal("hello", trie:find_longest())
        end)

        it("should return longest suffix from intermediate node", function()
            local trie = Trie.new()
            trie:insert "hello"
            trie:insert "help"

            local hel_node = trie:find "hel"
            assert.are.equal("lo", trie:find_longest(hel_node))
        end)

        it("should handle single character words", function()
            local trie = Trie.new()
            trie:insert "a"
            trie:insert "ab"

            assert.are.equal("ab", trie:find_longest())
        end)

        it("should update longest when adding longer word to existing prefix", function()
            local trie = Trie.new()
            trie:insert "a"
            assert.are.equal("a", trie:find_longest())

            trie:insert "abc"
            assert.are.equal("abc", trie:find_longest())
        end)
    end)
end)
