vim.api.nvim_create_user_command("AI", function(opts)
    local quickfill = require "quickfill"
    local subcmd = opts.args
    if subcmd == "" or subcmd == "start" then
        quickfill.start()
        vim.api.nvim_echo({ { "Plugin started!", "Normal" } }, false, {})
    elseif subcmd == "stop" then
        quickfill.stop()
        vim.api.nvim_echo({ { "Plugin stopped!", "Normal" } }, false, {})
    else
        vim.api.nvim_echo({ { "Invalid subcommand. Use `start` or `stop`", "WarningMsg" } }, false, {})
    end
end, {
    nargs = "?",
    complete = function(arg_lead)
        local cmds = { "start", "stop", "status" }
        return vim.tbl_filter(function(cmd)
            return vim.startswith(cmd, arg_lead)
        end, cmds)
    end,
})
