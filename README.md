# quickfill.nvim

[![Neovim](https://img.shields.io/badge/Neovim-0.9+-blue.svg)](https://neovim.io/)
[![Lua](https://img.shields.io/badge/Lua-5.1+-blue.svg)](https://lua.org/)

Fast, local AI-powered code completion for Neovim using llama.cpp with LSP integration.

`quickfill.nvim` provides intelligent code infill suggestions by combining your LSP server's context with a local llama.cpp server, offering blazing-fast completions with near-zero latency.

## ✨ Features

- **LSP-Backed Context**: Leverages your existing LSP servers for rich context (completions & signatures).
- **Local AI Inference**: Uses llama.cpp for fast, on-device inference—no data leaves your machine.
- **Smart Caching**: Caches suggestions for repeated contexts to reduce latency.
- **Extra Context Chunks**: Automatically extracts and includes relevant code snippets from your project.
- **Git-Aware**: Respects `.gitignore` for context extraction.

## 🚀 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "davkk/quickfill.nvim",
    lazy = true,
    cmd = "AI",
    config = function()
        -- no need to call setup!

        -- the plugin uses `<Plug>` mappings for flexibility
        -- you can map them to your preferred keys like this:
        vim.keymap.set("i", "<C-y>", "<Plug>(quickfill-accept)")         -- Accept full suggestion
        vim.keymap.set("i", "<C-k>", "<Plug>(quickfill-accept-word)")    -- Accept next word
        vim.keymap.set("i", "<C-x>", "<Plug>(quickfill-trigger)")        -- Manual infill trigger
    end,
}
```

## ⚙️ Configuration

Customize behavior via `vim.g.quickfill`.

Defaults are used if not set explicitly:

```lua
vim.g.quickfill = {
    url = "http://localhost:8012",          -- Llama.cpp server URL

    n_predict = 8,                          -- Max tokens to predict
    top_k = 30,                             -- Top-k sampling
    top_p = 0.4,                            -- Top-p sampling
    repeat_penalty = 1.5,                   -- Repeat penalty

    stop_chars = { "\n", "\r", "\r\n" },    -- Stop characters
    stop_on_stop_char = true,               -- Stop on stop chars

    n_prefix = 16,                          -- Prefix context lines
    n_suffix = 8,                           -- Suffix context lines

    max_cache_entries = 32,                 -- Max cache entries

    extra_chunks = false,                   -- Enable extra project chunks
    max_extra_chunks = 4,                   -- Max extra chunks
    chunk_lines = 16,                       -- Lines per chunk

    lsp_completion = true,                  -- Enable LSP completions
    max_lsp_completion_items = 15,          -- Max LSP items

    lsp_signature_help = false,             -- Enable signature help
}
```

## 📖 Commands

- `:AI start`: Initialize and start suggestions.
- `:AI stop`: Stop and clean up.
- `:AI status`: (Planned) Show plugin status and health.
