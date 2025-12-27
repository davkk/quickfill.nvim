local M = {}

function M.create_test_file()
    local content = vim.split(
        [[local M = {}

function M.calculate_fib(n)
    if n < 0 then
        return 0
    end
    if n == 0 then
        return 0
    end
    if n == 1 then
        return 1
    end

    local a = 0
    local b = 1
    local next_val
    for i = 2, n do
        next_val = a + b
        a = b
        b = next_val
    end

    return b
end

return M]],
        "\n"
    )
    local buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, content)
    vim.api.nvim_win_set_buf(0, buffer)
    return buffer
end

return M
