-- eightharsh's init.lua
--
-- Rewritten from scratch after the previous config (lazy.nvim +
-- treesitter + hand-rolled highlight groups relying on the terminal's
-- own background via bg = "NONE") produced a persistent, hard-to-pin-
-- down startup problem: `nvim` would open to an apparently empty
-- screen with no visible content at all. Extensive remote testing
-- (headless, real pty via tmux, isolated Xvfb) never conclusively
-- reproduced the exact symptom, so rather than keep chasing it, this
-- drops every moving part that could plausibly cause a startup hang
-- or a wrong/invisible color: no plugins (no network-dependent
-- bootstrap), and a real built-in colorscheme instead of custom
-- highight groups that depend on the terminal correctly supplying a
-- background color. If something in here needs fixing again later,
-- it needs to fail with a lot fewer moving parts to look through.
--
-- The old config's content is preserved in git history if anything
-- from it (treesitter, the hand-rolled statusline, etc.) is worth
-- bringing back deliberately later.

-- CORE
vim.opt.number         = true
vim.opt.hidden         = true
vim.opt.clipboard      = "unnamedplus"
vim.opt.mouse          = "a"
vim.opt.backup         = false
vim.opt.swapfile       = false
vim.opt.undofile       = true
vim.opt.undodir        = vim.fn.expand("~/.config/nvim/undo")
vim.opt.updatetime     = 250
vim.opt.timeoutlen     = 300
vim.opt.ignorecase     = true
vim.opt.smartcase      = true
vim.opt.expandtab      = true
vim.opt.shiftwidth     = 4
vim.opt.tabstop        = 4
vim.opt.signcolumn     = "yes"
vim.opt.scrolloff      = 8
vim.opt.splitright     = true
vim.opt.splitbelow     = true
vim.opt.termguicolors  = true

-- COLORSCHEME -- built into Neovim itself, no plugin, no custom
-- highlight overrides that depend on the terminal's own background.
vim.cmd.colorscheme("habamax")

-- LSP -- native vim.lsp, no plugin needed (Neovim 0.11+). filetypes
-- must be explicit: without it, all three attach to every buffer
-- regardless of language.
vim.lsp.config("clangd", {
    cmd = { "clangd" },
    filetypes = { "c", "cpp", "objc", "objcpp" },
    root_markers = { ".git", "compile_commands.json", "Makefile" },
})
vim.lsp.config("lua_ls", {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    root_markers = { ".git", ".luarc.json", ".luarc.jsonc" },
    settings = {
        Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = { checkThirdParty = false },
        },
    },
})
vim.lsp.config("bashls", {
    cmd = { "bash-language-server", "start" },
    filetypes = { "sh", "bash" },
    root_markers = { ".git" },
})
vim.lsp.enable({ "clangd", "lua_ls", "bashls" })

-- Remove trailing whitespace on save. Skips non-modifiable buffers --
-- a forced write of one (e.g. :w! on a readonly file, or a special
-- buffer that still fires BufWritePre) used to throw "E21: Cannot
-- make changes" from inside this callback.
vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*",
    callback = function()
        if not vim.bo.modifiable then return end
        local pos = vim.api.nvim_win_get_cursor(0)
        vim.cmd([[%s/\s\+$//e]])
        vim.api.nvim_win_set_cursor(0, pos)
    end,
})

-- Return to the last edit position when reopening a file.
vim.api.nvim_create_autocmd("BufReadPost", {
    callback = function()
        local mark       = vim.api.nvim_buf_get_mark(0, '"')
        local line_count = vim.api.nvim_buf_line_count(0)
        if mark[1] > 0 and mark[1] <= line_count then
            vim.api.nvim_win_set_cursor(0, mark)
        end
    end,
})

-- Prose filetypes: wrap instead of scroll, spellcheck on.
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown", "text", "gitcommit" },
    callback = function()
        vim.opt_local.wrap      = true
        vim.opt_local.linebreak = true
        vim.opt_local.spell     = true
    end,
})

-- Clear search highlight
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { silent = true })
