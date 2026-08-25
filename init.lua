-- lazy setup
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- core options
vim.o.number = true
vim.o.relativenumber = true
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4
vim.o.syntax = 'on'
vim.o.filetype = 'on'

-- leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

-- simple mappings
local map = vim.api.nvim_set_keymap
local opts = {
	noremap = true,
	silent = true,
}

map('n', '<leader>w', ':w<CR>', opts)
map('n', '<leader>q', ':qa<CR>', opts)

-- plugins
require('lazy').setup({
    spec = {
      -- statusline
      {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        opts = {},
      },

      -- file explorer
      {
        'nvim-tree/nvim-tree.lua',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        opts = {},
      },

      -- LSP configuration
      { 'neovim/nvim-lspconfig' },

      -- autocompletion
      {
        'hrsh7th/nvim-cmp',
        dependencies = {
          'hrsh7th/cmp-nvim-lsp',
          'hrsh7th/cmp-buffer',
          'hrsh7th/cmp-path',
          'L3MON4D3/LuaSnip',
          'saadparwaiz1/cmp_luasnip',
        },
      },

      -- fuzzy finder
      {
        'nvim-telescope/telescope.nvim',
        tag = 'v0.2.2',
        dependencies = { 'nvim-lua/plenary.nvim' },
      },

      -- treesitter
      {
        'nvim-treesitter/nvim-treesitter',
        build = ':TSUpdate',
      },
    },
    install = { colorscheme = { "habamax" } },
    checker = { enabled = true },
})

