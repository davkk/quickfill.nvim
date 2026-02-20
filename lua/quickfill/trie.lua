local M = {}

---@class quickfill.TrieNode
---@field value string
---@field children table<string, quickfill.TrieNode>
---@field longest_depth number
---@field longest_child string?
local TrieNode = {}
TrieNode.__index = TrieNode

---@param value string?
---@return quickfill.TrieNode
function TrieNode:new(value)
    return setmetatable({
        children = {},
        value = value or "",
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

---@param a string
---@param b string
local function common_prefix_len(a, b)
    local len = 1
    while len <= #a and len <= #b and a:sub(len, len) == b:sub(len, len) do
        len = len + 1
    end
    return len - 1
end

---@param text string
---@param node quickfill.TrieNode?
---@return quickfill.TrieNode
function Trie:insert(text, node)
    node = node or self.root
    if not text or #text == 0 then return node end

    local i = 1
    while i <= #text do
        local ch = text:sub(i, i)
        if not node.children[ch] then
            local new_node = TrieNode:new(text:sub(i))
            node.children[ch] = new_node
            local depth = #text - i + 1
            if depth > node.longest_depth then
                node.longest_child = ch
                node.longest_depth = depth
            end
            return new_node
        end

        local child = node.children[ch]
        local prefix_len = common_prefix_len(child.value, text:sub(i))

        if prefix_len < #child.value then
            local split_node = child

            local suffix_node = TrieNode:new(split_node.value:sub(prefix_len + 1))
            suffix_node.children = split_node.children
            suffix_node.longest_depth = split_node.longest_depth
            suffix_node.longest_child = split_node.longest_child

            split_node.value = split_node.value:sub(1, prefix_len)
            split_node.children = { [suffix_node.value:sub(1, 1)] = suffix_node }
            split_node.longest_depth = suffix_node.longest_depth + #suffix_node.value
            split_node.longest_child = suffix_node.value:sub(1, 1)
        end

        local depth = #text - i + 1
        if depth > node.longest_depth then
            node.longest_child = ch
            node.longest_depth = depth
        end

        node = child
        i = i + prefix_len
    end

    return node
end

---@param text string
---@return quickfill.TrieNode?, string
function Trie:find(text)
    local node = self.root
    local i = 1
    while i <= #text do
        local ch = text:sub(i, i)
        if not node.children[ch] then return nil, "" end
        local child = node.children[ch]
        local prefix_len = common_prefix_len(child.value, text:sub(i))
        if prefix_len < #child.value then
            if prefix_len < #text - i + 1 then return nil, "" end
            return child, child.value:sub(prefix_len + 1)
        end
        i = i + prefix_len
        node = child
    end
    return node, ""
end

---@param node quickfill.TrieNode?
---@param prefix string?
---@return string
function Trie:find_longest(node, prefix)
    node = node or self.root
    local result = {}
    if prefix and #prefix > 0 then result[#result + 1] = prefix end
    while node.longest_child do
        local child = node.children[node.longest_child]
        result[#result + 1] = child.value
        node = child
    end
    return table.concat(result)
end

---@return quickfill.Trie
function M.new()
    return Trie:new()
end

return M
