# quickfill.nvim

[![Neovim](https://img.shields.io/badge/Neovim-0.11+-blue.svg)](https://neovim.io/)

Fast, local AI-powered code completion for Neovim using llama.cpp with LSP integration.

`quickfill.nvim` provides intelligent code infill suggestions by combining your LSP server's context with a local llama.cpp server, offering blazing-fast completions with near-zero latency.

![quickfill-demo](https://github.com/user-attachments/assets/40d947d0-0449-4cb8-997f-11c92bfc92c7)

## Features

- **LSP-Backed Context**: Leverages your existing LSP servers for rich context (completions & signatures).
- **Local AI Inference**: Uses llama.cpp for fast, on-device inference—no data leaves your machine.
- **Smart Caching**: Caches suggestions for repeated contexts to reduce latency.
- **Extra Context Chunks**: Automatically extracts and includes relevant code snippets from your project.
- **Git-Aware**: Respects `.gitignore` for context extraction.

## Installation

```lua
vim.pack.add("https://github.com/folke/which-key.nvim")

-- no need to call setup!

-- the plugin uses `<Plug>` mappings for flexibility
-- you can map them to your preferred keys like this:
vim.keymap.set("i", "<C-y>", "<Plug>(quickfill-accept)")         -- accept full suggestion
vim.keymap.set("i", "<C-k>", "<Plug>(quickfill-accept-word)")    -- accept next word
vim.keymap.set("i", "<C-x>", "<Plug>(quickfill-trigger)")        -- trigger fresh infill request
```

## Configuration

Customize behavior via `vim.g.quickfill`.

Defaults are used if not set explicitly:

```lua
vim.g.quickfill = {
    url = "http://localhost:8012",          -- llama.cpp server URL

    n_predict = 8,                          -- max tokens to predict
    top_k = 30,                             -- top-k sampling
    top_p = 0.4,                            -- top-p sampling
    repeat_penalty = 1.5,                   -- repeat penalty

    stop_chars = { "\n", "\r", "\r\n" },    -- stop characters
    stop_on_trigger_char = true,            -- stop on trigger chars defined by LSP server

    n_prefix = 16,                          -- prefix context lines
    n_suffix = 8,                           -- suffix context lines

    max_cache_entries = 32,                 -- max cache entries

    extra_chunks = false,                   -- enable extra project chunks
    max_extra_chunks = 4,                   -- max extra chunks
    chunk_lines = 16,                       -- lines per chunk

    lsp_completion = true,                  -- enable LSP completions
    max_lsp_completion_items = 15,          -- max LSP completion items

    lsp_signature_help = false,             -- enable signature help
}
```

## Commands

- `:AI start`: Initialize and start suggestions.
- `:AI stop`: Stop and clean up.
- `:AI status`: (Planned) Show plugin status and health.
