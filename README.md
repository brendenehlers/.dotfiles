# brenden's dotfiles repo

how do i get what's in here, and put it over there!

## bootstrap

```sh
git clone git@github.com:brendenehlers/.dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

`install.sh` installs missing dependencies, then symlinks each config into
place, backing up anything already there as `<dest>.bak.<timestamp>`. It's
idempotent — re-run it any time.

Use `install.sh --check` to report what's missing without installing or
changing anything.

Then launch `nvim`: lazy.nvim installs plugins pinned by `nvim/lazy-lock.json`,
and mason installs the LSP servers.

## what's here

| path             | links to         |
| ---------------- | ---------------- |
| `nvim`           | `~/.config/nvim` |
| `tmux/tmux.conf` | `~/.tmux.conf`   |

## adding a new config

Drop the directory in the repo root and add one line to `LINKS` in `install.sh`:

```sh
LINKS=(
  "nvim:$CONFIG_HOME/nvim"
  "tmux/tmux.conf:$HOME/.tmux.conf"
  "git/gitconfig:$HOME/.gitconfig"
)
```

## dependencies

Installed automatically via the system package manager (`apt`, `dnf`, `pacman`,
`zypper`, `apk`, or `brew`):

| dep       | needed by            |
| --------- | -------------------- |
| `git`     | lazy.nvim, fugitive  |
| `curl`    | mason                |
| `unzip`   | mason                |
| `ripgrep` | telescope live-grep  |
| `fd`      | telescope find-files |
| a C compiler | treesitter parsers |
| `tmux`    | `tmux/tmux.conf`     |

Two things are handled specially:

- **neovim** is installed from the official GitHub release tarball into
  `~/.local/share/neovim`, with a symlink at `~/.local/bin/nvim` — *not* from
  the distro package, since Ubuntu 24.04 still ships 0.9.5 and this config
  needs 0.11+. An existing new-enough `nvim` is left alone.
- **renamed binaries.** Debian/Ubuntu ship `fd` as `fdfind`. A dep tagged
  `shim` in the `DEPS` table gets a symlink in `~/.local/bin` under its
  canonical name, so tooling that hardcodes `fd` works. (`bat`/`batcat` is the
  same story when it comes up — tag it and it's handled.)

Not automated: a **Nerd Font** for `nvim-web-devicons` icons. Fonts are
selected by the terminal emulator, which on WSL lives on the Windows side.
