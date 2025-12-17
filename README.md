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

### How It Works

- **Context Gathering**: Collects prefix/suffix from the current buffer and enriches with LSP data (completions, signatures).
- **Infill Request**: Uses llama.cpp's `/infill` endpoint with context, model config, and extra chunks.
- **Streaming Response**: Receives and displays suggestions in real-time.
- **Caching**: Stores results for identical contexts to speed up repeats.

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

## 📋 Requirements

- **curl** installed in path
- **llama.cpp server**: A running instance of the llama.cpp server for infill. Download and run with a compatible model (e.g., Qwen).
  - Example: `./llama-server --model codellama-7b-instruct.gguf --ctx-size 4096 --host 127.0.0.1 --port 8080`
- **LSP Server**: Recommended for enhanced context (e.g., tsserver for TypeScript, pyright for Python).

## 🛠️ Setup

1. **Start the llama.cpp server** on `http://127.0.0.1:8080` (or configure a custom URL).
2. **Start the plugin** in Neovim: `:AI start`
3. **Edit code**: Suggestions appear as you type in insert mode.

## 📖 Commands

- `:AI start`: Initialize and start suggestions.
- `:AI stop`: Stop and clean up.
- `:AI status`: (Planned) Show plugin status and health.
