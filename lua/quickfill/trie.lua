local M = {}

---@class quickfill.TrieNode
---@field children table<string, quickfill.TrieNode>
---@field is_end boolean
local TrieNode = {}
TrieNode.__index = TrieNode

---@return quickfill.TrieNode
function TrieNode:new()
    return setmetatable({
        children = {},
        is_end = false,
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
        node = node.children[char]
    end
    node.is_end = true
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
    if not next(node.children) then return "" end

    local longest = ""
    local function dfs(n, prefix)
        if n.is_end and #prefix > #longest then longest = prefix end
        for char, child in pairs(n.children) do
            dfs(child, prefix .. char)
        end
    end
    dfs(node, "")

    return longest
end

---@return quickfill.Trie
function M.new()
    return Trie:new()
end

---@param data quickfill.Trie
function Trie:deserialize(data)
    local function from_table(t, node)
        node.is_end = t.is_end
        for char, child_data in pairs(t.children or {}) do
            node.children[char] = TrieNode:new()
            from_table(child_data, node.children[char])
        end
    end
    from_table(data.root, self.root)
end

return M
