local M = {}

---@class quickfill.TrieNode
---@field children table<string, quickfill.TrieNode>
---@field longest_child string?
---@field longest_depth number
local TrieNode = {}
TrieNode.__index = TrieNode

---@return quickfill.TrieNode
function TrieNode:new()
    return setmetatable({
        children = {},
        longest_child = nil,
        longest_depth = 0,
    }, self)
end

---@class quickfill.Trie
---@field root quickfill.TrieNode
local Trie = {}
Trie.__index = Trie

---@return quickfill.Trie
function Trie:new()
    return setmetatable({
        root = TrieNode:new(),
    }, self)
end

---@param text string
---@param node quickfill.TrieNode?
---@return quickfill.TrieNode
function Trie:insert(text, node)
    node = node or self.root
    if not text or #text == 0 then return node end
    for i = 1, #text do
        local char = text:sub(i, i)
        if not node.children[char] then node.children[char] = TrieNode:new() end

        local depth = #text - i + 1

        if depth > node.longest_depth then
            node.longest_child = char
            node.longest_depth = depth
        end

        node = node.children[char]
    end
    return node
end

---@param text string
---@return quickfill.TrieNode?
function Trie:find(text)
    local node = self.root
    for i = 1, #text do
        local char = text:sub(i, i)
        if not node.children[char] then return nil end
        node = node.children[char]
    end
    return node
end

---@param node quickfill.TrieNode?
---@return string
function Trie:find_longest(node)
    node = node or self.root
    local result = {}
    while node.longest_child do
        result[#result + 1] = node.longest_child
        node = node.children[node.longest_child]
    end
    return table.concat(result)
end

---@return quickfill.Trie
function M.new()
    return Trie:new()
end

return M
