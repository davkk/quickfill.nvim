return {
    url = "http://localhost:8012",

    n_predict = 8,
    top_k = 30,
    top_p = 0.4,
    repeat_penalty = 1.5,

    stop_chars = { "\n", "\r", "\r\n" },
    stop_on_stop_char = true,

    n_prefix = 16,
    n_suffix = 8,

    max_cache_entries = 32,

    extra_chunks = false,
    max_extra_chunks = 4,
    chunk_lines = 16,

    lsp_completion = true,
    max_lsp_completion_items = 15,

    lsp_signature_help = false,
}
