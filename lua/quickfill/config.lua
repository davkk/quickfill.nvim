---@class quickfill.Config
---@field url? string Server URL
---@field model? string Model name
---@field n_predict? integer Max tokens to predict
---@field temperature? number Temperature
---@field top_k? integer Top-k sampling
---@field top_p? number Top-p sampling
---@field repeat_penalty? number Repeat penalty
---@field presence_penalty? number Presence penalty
---@field stop_chars? string[] Stop characters
---@field trigger_chars? string[] Trigger characters
---@field fresh_on_trigger_char? boolean Make fresh request on trigger char
---@field stop_on_trigger_char? boolean Stop generating on trigger char
---@field n_prefix? integer Prefix lines
---@field n_suffix? integer Suffix lines
---@field max_cache_entries? integer Max cache entries
---@field extra_chunks? boolean Enable extra chunks
---@field max_extra_chunks? integer Max extra chunks
---@field chunk_lines? integer Lines per chunk
---@field lsp_completion? boolean Enable LSP completion
---@field max_lsp_completion_items? integer Max LSP items
---@field lsp_signature_help? boolean Enable signature help

---@type quickfill.Config | fun():quickfill.Config | nil
vim.g.quickfill = vim.g.quickfill

---@type quickfill.Config
local default_config = {
    url = "http://localhost:8080",
    n_predict = 128,
    temperature = 0.3,
    top_k = 20,
    top_p = 0.9,
    repeat_penalty = 1.05,
    presence_penalty = 0,

    stop_chars = {},
    trigger_chars = { ".", ":", "[", "{", "(" },
    fresh_on_trigger_char = true,
    stop_on_trigger_char = false,

    n_prefix = 16,
    n_suffix = 16,

    max_cache_entries = 32,

    extra_chunks = true,
    max_extra_chunks = 6,
    chunk_lines = 16,

    lsp_completion = true,
    max_lsp_completion_items = 20,

    lsp_signature_help = true,
}

local user_config = type(vim.g.quickfill) == "function" and vim.g.quickfill() or vim.g.quickfill or {}

---@type quickfill.Config
local config = vim.tbl_deep_extend("force", default_config, user_config)

local ok, err = pcall(vim.validate, {
    url = { config.url, "string" },
    model = { config.model, "string" },
    n_predict = { config.n_predict, "number" },
    temperature = { config.temperature, "number" },
    top_k = { config.top_k, "number" },
    top_p = { config.top_p, "number" },
    repeat_penalty = { config.repeat_penalty, "number" },
    presence_penalty = { config.presence_penalty, "number" },
    stop_chars = { config.stop_chars, "table" },
    trigger_chars = { config.trigger_chars, "table" },
    fresh_on_trigger_char = { config.fresh_on_trigger_char, "boolean" },
    stop_on_trigger_char = { config.stop_on_trigger_char, "boolean" },
    n_prefix = { config.n_prefix, "number" },
    n_suffix = { config.n_suffix, "number" },
    max_cache_entries = { config.max_cache_entries, "number" },
    extra_chunks = { config.extra_chunks, "boolean" },
    max_extra_chunks = { config.max_extra_chunks, "number" },
    chunk_lines = { config.chunk_lines, "number" },
    lsp_completion = { config.lsp_completion, "boolean" },
    max_lsp_completion_items = { config.max_lsp_completion_items, "number" },
    lsp_signature_help = { config.lsp_signature_help, "boolean" },
})
if not ok then vim.notify("quickfill: Invalid config - " .. err, vim.log.levels.WARN) end

return config
