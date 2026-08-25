# brenden's dotfiles repo

how do i get what's in here, and put it over there!

## bootstrap

```sh
git clone git@github.com:brendenehlers/.dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

`install.sh` symlinks each config into place, backing up anything already
there as `<dest>.bak.<timestamp>`. It's idempotent — re-run it any time.

Then launch `nvim`: lazy.nvim installs plugins pinned by `nvim/lazy-lock.json`,
and mason installs the LSP servers.

## what's here

| path   | links to        |
| ------ | --------------- |
| `nvim` | `~/.config/nvim` |

## adding a new config

Drop the directory in the repo root and add one line to `LINKS` in `install.sh`:

```sh
LINKS=(
  "nvim:$CONFIG_HOME/nvim"
  "tmux/tmux.conf:$HOME/.tmux.conf"
)
```

## dependencies

Required: `git`, `nvim` (0.10+).
Recommended: `ripgrep` and `fd` (telescope), a C compiler (treesitter),
`curl`/`unzip` (mason), and a Nerd Font for icons.
