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

-- UI
vim.opt.number         = true
vim.opt.relativenumber = true
vim.opt.scrolloff      = 8
vim.opt.wrap           = false
vim.opt.splitbelow     = true
vim.opt.splitright     = true
vim.opt.cursorline     = true
vim.opt.termguicolors  = true
vim.opt.signcolumn     = "no"
vim.opt.laststatus     = 0
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

