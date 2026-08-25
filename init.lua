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
vim.o.termguicolors = true
vim.o.signcolumn = 'yes'

-- leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

-- simple mappings
local map = vim.api.nvim_set_keymap
local opts = {
	noremap = true,
	silent = true,
}

-- keybinds
map('n', '<leader>w', ':w<CR>', opts)
map('n', '<leader>q', ':qa<CR>', opts)

-- plugins
require('lazy').setup({
    spec = {
      -- colorscheme; loaded eagerly and first so nothing renders unstyled
      {
        'folke/tokyonight.nvim',
        lazy = false,
        priority = 1000,
        opts = {
          style = 'night', -- night | storm | moon | day
        },
        config = function(_, o)
          require('tokyonight').setup(o)
          vim.cmd.colorscheme('tokyonight')
        end,
      },

      -- animated cursor (the neovide smear effect, rendered in the terminal)
      {
        'sphamba/smear-cursor.nvim',
        event = 'VeryLazy',
        opts = {
          -- how fast the head of the smear catches up to the real cursor
          stiffness = 0.8,
          -- how fast the tail catches up; lower = longer trail
          trailing_stiffness = 0.5,
          -- stop animating once within this many cells of the target
          distance_stop_animating = 0.5,
        },
      },

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

      -- LSP server installer
      {
        'mason-org/mason.nvim',
        opts = {},
      },
      {
        'mason-org/mason-lspconfig.nvim',
        dependencies = { 'mason-org/mason.nvim', 'neovim/nvim-lspconfig' },
        opts = {
          -- servers mason should install for you
          ensure_installed = { 'lua_ls' },
          -- we call vim.lsp.enable() ourselves below, so keep the list explicit
          automatic_enable = false,
        },
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
        config = function()
          local cmp = require('cmp')
          local luasnip = require('luasnip')

          cmp.setup({
            snippet = {
              expand = function(args)
                luasnip.lsp_expand(args.body)
              end,
            },
            mapping = cmp.mapping.preset.insert({
              ['<C-Space>'] = cmp.mapping.complete(),
              ['<C-e>'] = cmp.mapping.abort(),
              ['<C-b>'] = cmp.mapping.scroll_docs(-4),
              ['<C-f>'] = cmp.mapping.scroll_docs(4),
              -- only confirm when an entry is actually selected
              ['<CR>'] = cmp.mapping.confirm({ select = false }),
              ['<Tab>'] = cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                elseif luasnip.expand_or_locally_jumpable() then
                  luasnip.expand_or_jump()
                else
                  fallback()
                end
              end, { 'i', 's' }),
              ['<S-Tab>'] = cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_prev_item()
                elseif luasnip.locally_jumpable(-1) then
                  luasnip.jump(-1)
                else
                  fallback()
                end
              end, { 'i', 's' }),
            }),
            sources = cmp.config.sources({
              { name = 'nvim_lsp' },
              { name = 'luasnip' },
            }, {
              { name = 'buffer' },
              { name = 'path' },
            }),
            formatting = {
              format = function(entry, item)
                item.menu = ({
                  nvim_lsp = '[LSP]',
                  luasnip = '[Snip]',
                  buffer = '[Buf]',
                  path = '[Path]',
                })[entry.source.name]
                return item
              end,
            },
          })
        end,
      },

      -- fuzzy finder
      {
        'nvim-telescope/telescope.nvim',
        tag = 'v0.2.2',
        dependencies = { 'nvim-lua/plenary.nvim' },
      },

      -- git gutter signs + hunk actions
      {
        'lewis6991/gitsigns.nvim',
        event = { 'BufReadPre', 'BufNewFile' },
        opts = {
          signs = {
            add          = { text = '│' },
            change       = { text = '│' },
            delete       = { text = '_' },
            topdelete    = { text = '‾' },
            changedelete = { text = '~' },
            untracked    = { text = '┆' },
          },
          current_line_blame = false, -- toggle with <leader>gb
          on_attach = function(buf)
            local gs = require('gitsigns')
            local function m(keys, fn, desc)
              vim.keymap.set('n', keys, fn, { buffer = buf, desc = 'Git: ' .. desc })
            end

            m(']c', function() gs.nav_hunk('next') end, 'next hunk')
            m('[c', function() gs.nav_hunk('prev') end, 'prev hunk')
            m('<leader>gs', gs.stage_hunk, 'stage hunk')
            m('<leader>gr', gs.reset_hunk, 'reset hunk')
            m('<leader>gu', gs.undo_stage_hunk, 'undo stage hunk')
            m('<leader>gp', gs.preview_hunk, 'preview hunk')
            m('<leader>gb', gs.toggle_current_line_blame, 'toggle line blame')
            m('<leader>gd', gs.diffthis, 'diff this')
          end,
        },
      },

      -- full git porcelain (:Git, :Git blame, :Gdiffsplit, ...)
      {
        'tpope/vim-fugitive',
        cmd = { 'G', 'Git', 'Gdiffsplit', 'Gread', 'Gwrite', 'Gedit', 'GBrowse' },
        keys = {
          { '<leader>gg', '<cmd>Git<cr>', desc = 'Git: status' },
          { '<leader>gB', '<cmd>Git blame<cr>', desc = 'Git: blame buffer' },
          { '<leader>gl', '<cmd>Git log --oneline --decorate --graph<cr>', desc = 'Git: log' },
        },
      },

      -- treesitter
      {
        'nvim-treesitter/nvim-treesitter',
        build = ':TSUpdate',
      },
    },
    install = { colorscheme = { "tokyonight" } },
    checker = { enabled = true },
})

-- telescope bindings
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Telescope live grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })


-- ---------------------------------------------------------------------------
-- LSP
-- ---------------------------------------------------------------------------

-- feed nvim-cmp's extra capabilities to every server
vim.lsp.config('*', {
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})

-- neovim-aware settings for the lua server (knows `vim`, plugin runtime files)
vim.lsp.config('lua_ls', {
  on_init = function(client)
    if client.workspace_folders then
      local path = client.workspace_folders[1].name
      if
        path ~= vim.fn.stdpath('config')
        and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc'))
      then
        return
      end
    end

    client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua or {}, {
      runtime = {
        version = 'LuaJIT',
        path = { 'lua/?.lua', 'lua/?/init.lua' },
      },
      workspace = {
        checkThirdParty = false,
        library = { vim.env.VIMRUNTIME },
      },
    })
  end,
  settings = { Lua = {} },
})

-- servers to start; add names from :h lspconfig-all (mason installs them)
vim.lsp.enable({
  'lua_ls',
})

-- buffer-local keymaps, set only once a server actually attaches
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP keymaps',
  callback = function(ev)
    local function m(keys, fn, desc)
      vim.keymap.set('n', keys, fn, { buffer = ev.buf, desc = 'LSP: ' .. desc })
    end

    m('gd', vim.lsp.buf.definition, 'goto definition')
    m('gD', vim.lsp.buf.declaration, 'goto declaration')
    m('gi', vim.lsp.buf.implementation, 'goto implementation')
    m('gr', vim.lsp.buf.references, 'references')
    m('K', vim.lsp.buf.hover, 'hover docs')
    m('<leader>rn', vim.lsp.buf.rename, 'rename')
    m('<leader>ca', vim.lsp.buf.code_action, 'code action')
    m('<leader>e', vim.diagnostic.open_float, 'line diagnostics')
    -- not <leader>f: that prefix belongs to telescope
    m('<leader>cf', function() vim.lsp.buf.format({ async = true }) end, 'format buffer')
  end,
})

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = 'rounded', source = true },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = 'E',
      [vim.diagnostic.severity.WARN] = 'W',
      [vim.diagnostic.severity.INFO] = 'I',
      [vim.diagnostic.severity.HINT] = 'H',
    },
  },
})
