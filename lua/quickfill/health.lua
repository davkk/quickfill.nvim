local M = {}

local function check_config()
    vim.health.start("quickfill: Configuration")

    local config = require("quickfill.config")

    -- check required fields
    local required_fields = {
        "url", "n_predict", "top_k", "top_p", "repeat_penalty",
        "stop_chars", "stop_on_trigger_char", "speculative_infill",
        "n_prefix", "n_suffix", "max_cache_entries", "extra_chunks",
        "max_extra_chunks", "chunk_lines", "lsp_completion",
        "max_lsp_completion_items", "lsp_signature_help"
    }

    for _, field in ipairs(required_fields) do
        if config[field] == nil then
            vim.health.error(string.format("Missing required config field: %s", field))
        else
            vim.health.ok(string.format("%s = %s", field, tostring(config[field])))
        end
    end

    -- validate URL format
    if type(config.url) ~= "string" or not config.url:match("^https?://") then
        vim.health.error("Invalid URL format. Expected http:// or https://")
    else
        vim.health.ok(string.format("Server URL: %s", config.url))
    end
end

local function check_dependencies()
    vim.health.start("quickfill: Dependencies")

    -- check curl availability
    local curl_check = vim.system({ "curl", "--version" }):wait()
    if curl_check.code == 0 then
        vim.health.ok("curl is available")
    else
        vim.health.error("curl is not available (required for server communication)")
    end

    -- check server connectivity
    local server_check = vim.system({
        "curl", "-s", "--max-time", "5",
        vim.g.quickfill and vim.g.quickfill.url or "http://localhost:8012"
    }):wait()

    if server_check.code == 0 then
        vim.health.ok("AI server is reachable")
    else
        vim.health.warn("AI server is not reachable. Start llama.cpp server first.")
    end
end

local function check_lsp()
    vim.health.start("quickfill: LSP Integration")

    local clients = vim.lsp.get_clients()
    if #clients == 0 then
        vim.health.warn("No LSP clients active. LSP features will be limited.")
    else
        vim.health.ok(string.format("%d LSP client(s) active", #clients))
        for _, client in ipairs(clients) do
            vim.health.info(string.format("  - %s (%s)", client.name, client.id))
        end
    end
end

local function check_plugin_state()
    vim.health.start("quickfill: Plugin State")

    local quickfill = package.loaded["quickfill"]
    if not quickfill then
        vim.health.warn("Plugin not loaded. Run :AI start to initialize.")
        return
    end

    if quickfill.enabled then
        vim.health.ok("Plugin is enabled")
    else
        vim.health.warn("Plugin is disabled. Run :AI start to enable.")
    end

    -- check cache status
    local cache = require("quickfill.cache")
    local cache_size = vim.tbl_count(cache.get_all())
    vim.health.info(string.format("Cache entries: %d/%d",
        cache_size, require("quickfill.config").max_cache_entries))

    -- check extra chunks
    local extra = require("quickfill.extra")
    local chunk_count = #extra.get_chunks()
    vim.health.info(string.format("Extra chunks: %d", chunk_count))
end

local function check_persistence()
    vim.health.start("quickfill: Persistence")

    local data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "quickfill")

    if vim.fn.isdirectory(data_dir) == 1 then
        vim.health.ok(string.format("Data directory exists: %s", data_dir))

        -- check for project-specific data
        local project_hash = vim.fn.sha256(vim.fs.root(0, ".git") or vim.fn.getcwd())
        local data_file = vim.fs.joinpath(data_dir, project_hash .. ".json")

        if vim.fn.filereadable(data_file) == 1 then
            vim.health.ok("Project data file exists")
        else
            vim.health.info("No project data file (normal for new projects)")
        end
    else
        vim.health.info("Data directory not created yet")
    end
end

function M.check()
    check_config()
    check_dependencies()
    check_lsp()
    check_plugin_state()
    check_persistence()
end

return M
