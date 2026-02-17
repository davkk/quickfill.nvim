local M = {}

local function check_dependencies()
    vim.health.start "quickfill: Dependencies"

    local curl_check = vim.system({ "curl", "--version" }):wait()
    if curl_check.code == 0 then
        vim.health.ok "curl is available"
    else
        vim.health.error "curl is not available (required for server communication)"
    end

    local server_check = vim.system({
        "curl",
        "-s",
        "--max-time",
        "5",
        vim.g.quickfill and vim.g.quickfill.url or "http://localhost:8012",
    }):wait()

    if server_check.code == 0 then
        vim.health.ok "AI server is reachable"
    else
        vim.health.warn "AI server is not reachable. Start llama.cpp server first."
    end
end

local function check_lsp()
    vim.health.start "quickfill: LSP Integration"

    local clients = vim.lsp.get_clients()
    if #clients == 0 then
        vim.health.warn "No LSP clients active. LSP features will be limited."
    else
        vim.health.ok(string.format("%d LSP client(s) active", #clients))
        for _, client in ipairs(clients) do
            vim.health.info(string.format("  - %s (%s)", client.name, client.id))
        end
    end
end

local function check_plugin_state()
    vim.health.start "quickfill: Plugin State"

    local quickfill = package.loaded["quickfill"]
    if not quickfill then
        vim.health.warn "Plugin not loaded. Run :AI start to initialize."
        return
    end

    if quickfill.enabled then
        vim.health.ok "Plugin is enabled"
    else
        vim.health.warn "Plugin is disabled. Run :AI start to enable."
    end

    local cache = require "quickfill.cache"
    local cache_size = vim.tbl_count(cache.get_all())
    vim.health.info(string.format("Cache entries: %d/%d", cache_size, require("quickfill.config").max_cache_entries))

    local extra = require "quickfill.extra"
    local chunk_count = #extra.get_chunks()
    vim.health.info(string.format("Extra chunks: %d", chunk_count))
end

function M.check()
    check_dependencies()
    check_lsp()
    check_plugin_state()
end

return M
