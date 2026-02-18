local Trie = require "quickfill.trie"

describe("trie", function()
    describe("new", function()
        it("should create a trie with empty root node", function()
            local trie = Trie.new()
            assert.is_not_nil(trie)
            assert.is_not_nil(trie.root)
            assert.are.same({}, trie.root.children)
            assert.is_nil(trie.root.longest_child)
            assert.are.equal(0, trie.root.longest_depth)
        end)
    end)

    describe("insert", function()
        it("should insert single word and create correct node chain", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie.root
            for _, char in ipairs { "h", "e", "l", "l", "o" } do
                assert.is_not_nil(node.children[char])
                node = node.children[char]
            end
        end)

        it("should share common prefix nodes for multiple words", function()
            local trie = Trie.new()
            trie:insert "hello"
            trie:insert "help"

            local h_node = trie.root.children["h"]
            assert.is_not_nil(h_node)
            local he_node = h_node.children["e"]
            assert.is_not_nil(he_node)
            local hel_node = he_node.children["l"]
            assert.is_not_nil(hel_node)
            assert.is_not_nil(hel_node.children["l"])
            assert.is_not_nil(hel_node.children["p"])
        end)

        it("should return node when inserting empty string", function()
            local trie = Trie.new()
            local result = trie:insert ""
            assert.are.equal(trie.root, result)
        end)

        it("should update longest_child and longest_depth on insert", function()
            local trie = Trie.new()
            trie:insert "hi"

            assert.are.equal("h", trie.root.longest_child)
            assert.are.equal(2, trie.root.longest_depth)

            local h_node = trie.root.children["h"]
            assert.are.equal("i", h_node.longest_child)
            assert.are.equal(1, h_node.longest_depth)
        end)

        it("should update longest when inserting longer word", function()
            local trie = Trie.new()
            trie:insert "hi"
            trie:insert "hello"

            assert.are.equal("h", trie.root.longest_child)
            assert.are.equal(5, trie.root.longest_depth)

            local h_node = trie.root.children["h"]
            assert.are.equal("e", h_node.longest_child)
            assert.are.equal(4, h_node.longest_depth)
        end)

        it("should return the final node after insertion", function()
            local trie = Trie.new()
            local result = trie:insert "abc"

            assert.is_not_nil(result)
            assert.are.same({}, result.children)
            assert.is_nil(result.longest_child)
            assert.are.equal(0, result.longest_depth)
        end)

        it("should insert with custom starting node", function()
            local trie = Trie.new()
            trie:insert "ab"

            local a_node = trie:find "a"
            trie:insert("cde", a_node)

            assert.are.equal("cde", trie:find_longest(a_node))
            assert.are.equal("acde", trie:find_longest())
        end)
    end)

    describe("find", function()
        it("should find existing path and return correct node", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie:find "hello" ---@cast node quickfill.TrieNode
            assert.is_not_nil(node)
            assert.are.same({}, node.children)
        end)

        it("should return nil for non-existent path", function()
            local trie = Trie.new()
            trie:insert "hello"

            assert.is_nil(trie:find "world")
            assert.is_nil(trie:find "hellx")
        end)

        it("should find intermediate node", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie:find "hel" ---@cast node quickfill.TrieNode
            assert.is_not_nil(node)
            assert.is_not_nil(node.children["l"])
        end)

        it("should return root for empty string", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie:find ""
            assert.are.equal(trie.root, node)
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

        it("should return empty string from leaf node", function()
            local trie = Trie.new()
            trie:insert "hello"

            local node = trie:find "hello"
            assert.are.equal("", trie:find_longest(node))
        end)

        it("should return empty string for empty trie", function()
            local trie = Trie.new()
            assert.are.equal("", trie:find_longest())
        end)

        it("should handle single character words", function()
            local trie = Trie.new()
            trie:insert "a"
            trie:insert "ab"

            assert.are.equal("ab", trie:find_longest())
            assert.are.equal("b", trie:find_longest(trie:find "a"))
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
