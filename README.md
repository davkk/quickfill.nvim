<div align="center">

<img width="256" height="auto" alt="quickfill-logo" src="https://github.com/user-attachments/assets/e08f122b-83fc-4029-b983-c86bc5f46b2f" />

# quickfill.nvim

[![Neovim](https://img.shields.io/badge/Neovim-0.11+-blue.svg)](https://neovim.io/)

Quick code infill suggestions by combining a local llama.cpp server with active LSP servers.

<img width="900" height="auto" alt="quickfill-demo" src="https://github.com/user-attachments/assets/40d947d0-0449-4cb8-997f-11c92bfc92c7" />

</div>

## Features

- **Local AI Inference**: Uses llama.cpp for low latency, on-device inference == no data leaves your machine.
- **LSP-Backed Context**: Leverages your existing LSP servers for rich context (completions & signatures).
- **Prompt Caching**: Caches suggestions for repeated contexts to reduce latency.
- **Cross-file Context Chunks**: Automatically extracts and includes relevant code snippets from your project files.
- **Git-Aware**: Respects `.gitignore` for context extraction.
- **Trigger Characters**: Automatically makes fresh requests on trigger characters (e.g., `.`, `:`, `(`, `{`, `[`).

## Installation

```lua
vim.pack.add({ "https://github.com/davkk/quickfill.nvim" })

-- no need to call setup!

-- the plugin uses `<Plug>` mappings for flexibility
-- you can map them to your preferred keys like this:
vim.keymap.set("i", "<C-y>", "<Plug>(quickfill-accept)")         -- accept full suggestion
vim.keymap.set("i", "<C-k>", "<Plug>(quickfill-accept-word)")    -- accept next word
vim.keymap.set("i", "<C-l>", "<Plug>(quickfill-accept-replace)") -- accept and replace
vim.keymap.set("i", "<C-x>", "<Plug>(quickfill-trigger)")        -- trigger fresh infill request
```

## Configuration

Customize behavior via `vim.g.quickfill`.

Defaults are used if not set explicitly:

```lua
vim.g.quickfill = {
    url = "http://localhost:8080",          -- llama.cpp server URL

    n_predict = 128,                        -- max tokens to predict
    temperature = 0.3,                      -- temperature
    top_k = 20,                             -- top-k sampling
    top_p = 0.4,                            -- top-p sampling
    repeat_penalty = 1.5,                   -- repeat penalty

    stop_chars = { "\n", "\r", "\r\n" },    -- stop characters
    trigger_chars = { ".", ":", "[", "{", "(" }, -- trigger characters for fresh request
    fresh_on_trigger_char = true,           -- make fresh request on trigger char
    stop_on_trigger_char = false,           -- stop generating on trigger char

    n_prefix = 16,                          -- prefix context lines
    n_suffix = 16,                          -- suffix context lines

    max_cache_entries = 32,                 -- max cache entries

    extra_chunks = true,                    -- enable extra project chunks
    max_extra_chunks = 6,                   -- max extra chunks
    chunk_lines = 16,                       -- lines per chunk

    lsp_completion = true,                  -- enable LSP completions
    max_lsp_completion_items = 20,          -- max LSP completion items

    lsp_signature_help = true,              -- enable signature help
}
```

## Local Inference Server Setup

Before using the plugin, make sure to have a llama.cpp server running.

Here's an example command to download a model and start the server in the background:

```bash
llama-server \
    -hf bartowski/Qwen2.5-Coder-0.5B-GGUF:Q4_0 \
    --n-gpu-layers 99 \
    --ctx-size 0 \
    --flash-attn on \
    --mlock \
    --cache-reuse 256
```

## Commands

- start plugin with `:AI start` or `:AI`
- stop plugin with `:AI stop`
