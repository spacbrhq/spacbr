-- eightharsh's init.lua
--
-- Rewritten from scratch after a persistent "nvim shows nothing"
-- report that turned out to be unrelated to this file at all: the
-- real causes were a locked screen being mistaken for a broken one
-- (see .local/src/slock), and dunst failing to start after reboot
-- (see .config/xinitrc). No plugins here (no network-dependent
-- bootstrap) to keep this simple to reason about if anything ever
-- does need debugging again. The old config's content -- including
-- treesitter and a hand-rolled statusline -- is preserved in git
-- history if worth bringing back deliberately later.
--
-- Colors match .config/vim/vimrc's denshichrome palette exactly (same
-- guibg=NONE approach -- proven fine there, so the theory that this
-- pattern itself caused the "shows nothing" report doesn't hold up).

-- CORE
vim.opt.number         = true
vim.opt.relativenumber = true
vim.opt.cursorline     = true
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

-- COLORS -- denshichrome, same palette/approach as .config/vim/vimrc.
vim.cmd("syntax on")
vim.cmd("highlight clear")

local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
end

-- Base
hi("Normal",       { fg = "#e1e3e7", bg = "NONE" })
hi("LineNr",       { fg = "#404552", bg = "NONE" })
hi("CursorLineNr", { fg = "#ffffff", bg = "NONE", bold = true })
hi("CursorLine",   { fg = "NONE",    bg = "NONE" })
hi("SignColumn",   { fg = "#404552", bg = "NONE" })

-- Syntax
hi("Comment",    { fg = "#60e1e0", bg = "NONE" })
hi("String",     { fg = "#9bcf4f", bg = "NONE" })
hi("Keyword",    { fg = "#dab6fc", bg = "NONE" })
hi("Function",   { fg = "#4084d6", bg = "NONE" })
hi("Type",       { fg = "#f6d13a", bg = "NONE" })
hi("Constant",   { fg = "#fda685", bg = "NONE" })
hi("Number",     { fg = "#fda685", bg = "NONE" })
hi("Statement",  { fg = "#dab6fc", bg = "NONE" })
hi("PreProc",    { fg = "#60e1e0", bg = "NONE" })
hi("Special",    { fg = "#9bcf4f", bg = "NONE" })
hi("Identifier", { fg = "#e1e3e7", bg = "NONE" })
hi("Error",      { fg = "#ed4737", bg = "NONE" })

-- Spell (disabled visually)
hi("SpellBad",   {})
hi("SpellCap",   {})
hi("SpellRare",  {})
hi("SpellLocal", {})

-- UI elements
hi("Visual",       { fg = "#2f343f", bg = "#ffffff" })
hi("VisualNOS",    { fg = "#2f343f", bg = "#ffffff" })
hi("Search",       { fg = "#2f343f", bg = "#f6d13a" })
hi("IncSearch",    { fg = "#2f343f", bg = "#60e1e0" })
hi("MatchParen",   { fg = "#f6d13a", bg = "NONE",    bold = true })
hi("StatusLine",   { fg = "#e1e3e7", bg = "NONE" })
hi("StatusLineNC", { fg = "#404552", bg = "NONE" })
hi("VertSplit",    { fg = "#404552", bg = "NONE" })
hi("WinSeparator", { fg = "#404552", bg = "NONE" })
hi("Pmenu",        { fg = "#e1e3e7", bg = "#404552" })
hi("PmenuSel",     { fg = "#2f343f", bg = "#dab6fc" })
hi("PmenuSbar",    { bg = "#404552" })
hi("PmenuThumb",   { bg = "#dab6fc" })
hi("WildMenu",     { fg = "#2f343f", bg = "#f6d13a" })
hi("ColorColumn",  { bg = "#404552" })
hi("EndOfBuffer",  { fg = "#404552", bg = "NONE" })
hi("NonText",      { fg = "#404552", bg = "NONE" })
hi("Folded",       { fg = "#60e1e0", bg = "#404552" })
hi("Title",        { fg = "#dab6fc", bg = "NONE",    bold = true })
hi("Todo",         { fg = "#f6d13a", bg = "NONE",    bold = true })
hi("Directory",    { fg = "#4084d6", bg = "NONE" })

-- Markdown
hi("markdownH1",            { fg = "#dab6fc", bold = true })
hi("markdownH2",            { fg = "#dab6fc", bold = true })
hi("markdownH3",            { fg = "#dab6fc", bold = true })
hi("markdownH4",            { fg = "#dab6fc", bold = true })
hi("markdownH1Delimiter",   { fg = "#dab6fc", bold = true })
hi("markdownH2Delimiter",   { fg = "#dab6fc", bold = true })
hi("markdownH3Delimiter",   { fg = "#dab6fc", bold = true })
hi("markdownBold",          { fg = "#f6d13a", bold = true })
hi("markdownItalic",        { fg = "#60e1e0", italic = true })
hi("markdownCode",          { fg = "#9bcf4f", bg = "NONE" })
hi("markdownCodeBlock",     { fg = "#9bcf4f", bg = "NONE" })
hi("markdownCodeDelimiter", { fg = "#404552", bg = "NONE" })
hi("markdownLinkText",      { fg = "#4084d6", bg = "NONE" })
hi("markdownUrl",           { fg = "#404552", bg = "NONE" })
hi("markdownListMarker",    { fg = "#60e1e0", bg = "NONE" })
hi("markdownRule",          { fg = "#404552", bg = "NONE" })
hi("markdownBlockquote",    { fg = "#60e1e0", bg = "NONE", italic = true })

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
