-- eightharsh's init.lua

-- CORE
vim.opt.encoding    = "utf-8"
vim.opt.hidden      = true
vim.opt.clipboard   = "unnamed,unnamedplus"
vim.opt.mouse       = "a"
vim.opt.backup      = false
vim.opt.swapfile    = false
vim.opt.undofile    = true
vim.opt.undodir     = vim.fn.expand("~/.config/nvim/undo")
vim.opt.shortmess:append("I")
vim.opt.updatetime  = 250
vim.opt.timeoutlen  = 300
vim.opt.isfname:append("@-@")

-- PLUGINS
-- This config was plugin-free until now. Adding one here (lazy.nvim,
-- bootstrapped from a single git clone -- no package manager or
-- external installer step) specifically for nvim-treesitter: unlike
-- LSP (native vim.lsp, no plugin needed) or the statusline (hand-
-- rolled below), treesitter genuinely needs runtime parser
-- compilation/version management that's painful to hand-roll, and
-- nvim-treesitter is the standard way to get it. Kept to this one
-- plugin -- this isn't an invitation to grow a plugin list.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "master",
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter.configs").setup({
                -- Matches this repo's own languages (C sources under
                -- .local/src, this Lua config, sh scripts) plus
                -- markdown/vim for docs and vimscript compat.
                ensure_installed = {
                    "c", "lua", "bash", "markdown", "markdown_inline",
                    "vim", "vimdoc", "query",
                },
                highlight = { enable = true },
                indent = { enable = true },
            })
        end,
    },
}, {
    -- No startup UI/notifications -- keep this invisible unless
    -- something actually needs attention (§3's "quiet" principle).
    change_detection = { notify = false },
})

-- UI
vim.opt.number         = true
vim.opt.relativenumber = true
vim.opt.scrolloff      = 8
vim.opt.wrap           = false
vim.opt.splitbelow     = true
vim.opt.splitright     = true
vim.opt.cursorline     = true
vim.opt.termguicolors  = true
-- "no" would hide the LSP diagnostic signs configured below; "yes"
-- always reserves the column so it doesn't shift text when a sign
-- appears/disappears.
vim.opt.signcolumn     = "yes"
-- One global statusline for the whole instance instead of one per
-- split -- matches dwm's own "one bar, not one per window" model, and
-- is what the custom statusline below is built for.
vim.opt.laststatus     = 3
vim.opt.pumheight      = 10
vim.opt.colorcolumn    = "80"
vim.opt.showbreak      = "↪ "

-- SEARCH
vim.opt.hlsearch   = true
vim.opt.incsearch  = true
vim.opt.ignorecase = true
vim.opt.smartcase  = true
vim.opt.inccommand = "split"   -- live preview of :s substitutions

-- INDENT
vim.opt.autoindent  = true
vim.opt.smartindent = true
vim.opt.tabstop     = 4
vim.opt.shiftwidth  = 4
vim.opt.expandtab   = true

-- LEADER
vim.g.mapleader = " "

-- KEYMAPS
local map = function(mode, lhs, rhs, opts)
    opts = opts or { noremap = true, silent = true }
    vim.keymap.set(mode, lhs, rhs, opts)
end

-- Save / Quit
map("n", "<leader>w", ":w<CR>")
map("n", "<leader>q", ":q<CR>")
map("n", "<leader>Q", ":qa!<CR>")

-- Clear search highlight
map("n", "<leader>h", ":noh<CR>")

-- Toggle spell check
map("n", "<leader>s", ":setlocal spell!<CR>")

-- Toggle colorcolumn
map("n", "<leader>cc", function()
    if vim.opt.colorcolumn:get()[1] == "80" then
        vim.opt.colorcolumn = ""
    else
        vim.opt.colorcolumn = "80"
    end
end)

-- Window navigation
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- Better indenting in visual mode (stays in visual)
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Move lines up/down
map("n", "<A-j>", ":m .+1<CR>==")
map("n", "<A-k>", ":m .-2<CR>==")
map("v", "<A-j>", ":m '>+1<CR>gv=gv")
map("v", "<A-k>", ":m '<-2<CR>gv=gv")

-- Stay centered when jumping
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

-- Don't yank on paste (keeps register clean)
map("x", "<leader>p", '"_dP')

-- Yank to end of line (consistent with D, C)
map("n", "Y", "y$")

-- AUTOCMDS
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Highlight on yank
augroup("yank_highlight", { clear = true })
autocmd("TextYankPost", {
    group    = "yank_highlight",
    callback = function()
        vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
    end,
})

-- Markdown settings
augroup("markdown_settings", { clear = true })
autocmd("FileType", {
    group   = "markdown_settings",
    pattern = "markdown",
    callback = function()
        vim.opt_local.wrap        = true
        vim.opt_local.linebreak   = true
        vim.opt_local.breakindent = true
        vim.opt_local.scrolloff   = 4
        vim.opt_local.colorcolumn = ""     -- no column guide in prose
        vim.opt_local.spell       = true
    end,
})

-- Remove trailing whitespace on save
augroup("trim_whitespace", { clear = true })
autocmd("BufWritePre", {
    group   = "trim_whitespace",
    pattern = "*",
    callback = function()
        local pos = vim.api.nvim_win_get_cursor(0)
        vim.cmd([[%s/\s\+$//e]])
        vim.api.nvim_win_set_cursor(0, pos)
    end,
})

-- Return to last edit position when opening a file
augroup("last_position", { clear = true })
autocmd("BufReadPost", {
    group    = "last_position",
    callback = function()
        local mark       = vim.api.nvim_buf_get_mark(0, '"')
        local line_count = vim.api.nvim_buf_line_count(0)
        if mark[1] > 0 and mark[1] <= line_count then
            vim.api.nvim_win_set_cursor(0, mark)
        end
    end,
})

-- FILETYPE INDENT OVERRIDES
-- C: dwm/dmenu/st/slock/dwmblocks source under .local/src is real tabs
-- at a 4-column display width (verified against dwm.c), not the
-- global 4-space default above -- this is the actual editor for that
-- source. install/*.sh and .local/bin/* (verified against configs.sh)
-- already use 4-space indent matching the global default, so sh needs
-- no override here.
augroup("filetype_indent", { clear = true })
autocmd("FileType", {
    group   = "filetype_indent",
    pattern = "c",
    callback = function()
        vim.opt_local.tabstop     = 4
        vim.opt_local.shiftwidth  = 4
        vim.opt_local.expandtab   = false
    end,
})
autocmd("FileType", {
    group   = "filetype_indent",
    pattern = { "json", "yaml" },
    callback = function()
        vim.opt_local.tabstop    = 2
        vim.opt_local.shiftwidth = 2
        vim.opt_local.expandtab  = true
    end,
})

-- TERMINAL MODE
map("t", "<Esc>", [[<C-\><C-n>]])
map("t", "<C-h>", [[<C-\><C-n><C-w>h]])
map("t", "<C-j>", [[<C-\><C-n><C-w>j]])
map("t", "<C-k>", [[<C-\><C-n><C-w>k]])
map("t", "<C-l>", [[<C-\><C-n><C-w>l]])

-- QUICKFIX
-- Auto-open after a command populates the quickfix list (:grep,
-- :make), auto-close if it's the last window left.
augroup("quickfix_behavior", { clear = true })
autocmd("QuickFixCmdPost", {
    group   = "quickfix_behavior",
    pattern = { "[^l]*" },
    command = "cwindow",
})
autocmd("QuickFixCmdPost", {
    group   = "quickfix_behavior",
    pattern = { "l*" },
    command = "lwindow",
})
-- <leader>cc is already colorcolumn toggle above; cq avoids the clash.
map("n", "<leader>cq", function()
    if vim.fn.getqflist({ winid = 0 }).winid ~= 0 then
        vim.cmd("cclose")
    else
        vim.cmd("copen")
    end
end)

-- LSP
-- Native vim.lsp (built into Neovim core since 0.8, this API since
-- 0.11) -- no plugin needed. Matches the languages this repo itself
-- is actually written in: C (dwm/dmenu/st/slock/dwmblocks), Lua (this
-- file), POSIX sh (install/*.sh, .local/bin/*). Servers themselves are
-- official Arch packages (clang, lua-language-server,
-- bash-language-server), not bundled or auto-installed by this config.
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
    filetypes = { "sh" },
    root_markers = { ".git" },
})
vim.lsp.enable({ "clangd", "lua_ls", "bashls" })

vim.diagnostic.config({
    virtual_text = { prefix = "●" },
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = "✗",
            [vim.diagnostic.severity.WARN]  = "!",
            [vim.diagnostic.severity.INFO]  = "i",
            [vim.diagnostic.severity.HINT]  = "?",
        },
    },
    underline = true,
    severity_sort = true,
})

augroup("lsp_attach", { clear = true })
autocmd("LspAttach", {
    group = "lsp_attach",
    callback = function(args)
        local bufnr = args.buf
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        local bufmap = function(mode, lhs, rhs)
            vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, noremap = true, silent = true })
        end

        bufmap("n", "K",          vim.lsp.buf.hover)
        bufmap("n", "gd",         vim.lsp.buf.definition)
        bufmap("n", "gD",         vim.lsp.buf.declaration)
        bufmap("n", "gi",         vim.lsp.buf.implementation)
        bufmap("n", "gr",         vim.lsp.buf.references)
        bufmap("n", "<leader>rn", vim.lsp.buf.rename)
        bufmap("n", "<leader>ca", vim.lsp.buf.code_action)
        bufmap("n", "[d",         function() vim.diagnostic.jump({ count = -1, float = true }) end)
        bufmap("n", "]d",         function() vim.diagnostic.jump({ count = 1, float = true }) end)
        bufmap("n", "<leader>e",  vim.diagnostic.open_float)

        if client and client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
        end
    end,
})

-- STATUSLINE
-- Hand-rolled, no plugin -- laststatus=3 above makes this the one
-- global bar for the whole instance, matching dwm's own "one bar" model
-- rather than a per-split statusline. Reuses the StatusLine colors
-- defined below, plus the same dark-text-on-accent-bg pattern used
-- throughout (dmenu's SchemeOut, the Visual/Search highlights above)
-- for the mode indicator.
local mode_names = {
    n       = "NORMAL",
    i       = "INSERT",
    v       = "VISUAL",
    V       = "V-LINE",
    ["\22"] = "V-BLOCK",
    c       = "COMMAND",
    R       = "REPLACE",
    t       = "TERMINAL",
    s       = "SELECT",
    S       = "S-LINE",
}

function _G.SpacbrStatusline()
    local mode = mode_names[vim.fn.mode()] or vim.fn.mode()
    local filename = vim.fn.expand("%:t")
    if filename == "" then filename = "[No Name]" end
    local modified = vim.bo.modified and " [+]" or ""

    local diag = ""
    local n_err = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
    local n_warn = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
    if n_err > 0 then diag = diag .. "%#DiagnosticError#✗" .. n_err .. " " end
    if n_warn > 0 then diag = diag .. "%#DiagnosticWarn#!" .. n_warn .. " " end

    local filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "no ft"

    return table.concat({
        "%#StatuslineMode# ", mode, " ",
        "%#StatusLine# ", filename, modified,
        "%=",
        diag,
        "%#StatusLine#", filetype, " │ %l:%c  %p%% ",
    })
end

vim.o.statusline = "%!v:lua.SpacbrStatusline()"

-- MARKDOWN
vim.g.markdown_fenced_languages = { "bash", "python", "javascript", "vim", "sh" }
vim.g.markdown_syntax_conceal   = 0

-- COLORS
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

-- UI Elements
hi("Visual",       { fg = "#2f343f", bg = "#ffffff" })
hi("VisualNOS",    { fg = "#2f343f", bg = "#ffffff" })
hi("Search",       { fg = "#2f343f", bg = "#f6d13a" })
hi("IncSearch",    { fg = "#2f343f", bg = "#60e1e0" })
hi("MatchParen",   { fg = "#f6d13a", bg = "NONE",    bold = true })
hi("StatusLine",   { fg = "#e1e3e7", bg = "#404552" })
hi("StatuslineMode", { fg = "#2f343f", bg = "#4084d6", bold = true })
hi("StatusLineNC", { fg = "#404552", bg = "#2f343f" })
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
hi("markdownCode",          { fg = "#9bcf4f" })
hi("markdownCodeBlock",     { fg = "#9bcf4f" })
hi("markdownCodeDelimiter", { fg = "#404552" })
hi("markdownLinkText",      { fg = "#4084d6" })
hi("markdownUrl",           { fg = "#404552" })
hi("markdownListMarker",    { fg = "#60e1e0" })
hi("markdownRule",          { fg = "#404552" })
hi("markdownBlockquote",    { fg = "#60e1e0", italic = true })

-- LSP / diagnostics
hi("DiagnosticError",           { fg = "#ed4737" })
hi("DiagnosticWarn",            { fg = "#f6d13a" })
hi("DiagnosticInfo",            { fg = "#4084d6" })
hi("DiagnosticHint",            { fg = "#60e1e0" })
hi("DiagnosticVirtualTextError", { fg = "#ed4737", bg = "NONE" })
hi("DiagnosticVirtualTextWarn",  { fg = "#f6d13a", bg = "NONE" })
hi("DiagnosticVirtualTextInfo",  { fg = "#4084d6", bg = "NONE" })
hi("DiagnosticVirtualTextHint",  { fg = "#60e1e0", bg = "NONE" })
hi("DiagnosticUnderlineError",  { sp = "#ed4737", underline = true })
hi("DiagnosticUnderlineWarn",   { sp = "#f6d13a", underline = true })
hi("DiagnosticUnderlineInfo",   { sp = "#4084d6", underline = true })
hi("DiagnosticUnderlineHint",   { sp = "#60e1e0", underline = true })
hi("LspReferenceText",  { bg = "#404552" })
hi("LspReferenceRead",  { bg = "#404552" })
hi("LspReferenceWrite", { bg = "#404552" })
hi("NormalFloat", { fg = "#e1e3e7", bg = "#404552" })
hi("FloatBorder", { fg = "#404552", bg = "#404552" })

