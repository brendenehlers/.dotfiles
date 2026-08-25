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
| `zsh/zshrc`      | `~/.zshrc`       |
| `zsh/p10k.zsh`   | `~/.p10k.zsh`    |

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
| `zsh`     | `zsh/zshrc`          |

Two things are handled specially:

- **neovim** is installed from the official GitHub release tarball into
  `~/.local/share/neovim`, with a symlink at `~/.local/bin/nvim` — *not* from
  the distro package, since Ubuntu 24.04 still ships 0.9.5 and this config
  needs 0.11+. An existing new-enough `nvim` is left alone.
- **renamed binaries.** Debian/Ubuntu ship `fd` as `fdfind`. A dep tagged
  `shim` in the `DEPS` table gets a symlink in `~/.local/bin` under its
  canonical name, so tooling that hardcodes `fd` works. (`bat`/`batcat` is the
  same story when it comes up — tag it and it's handled.)

`install.sh` also clones the three repos `zsh/zshrc` needs — oh-my-zsh,
powerlevel10k, and zsh-syntax-highlighting — into `$HOME`. They need no root
and no version pinning, so cloning them beats leaving you with a broken prompt.

Not automated: a **Nerd Font** for `nvim-web-devicons` icons. Fonts are
selected by the terminal emulator, which on WSL lives on the Windows side.

## zsh

`zsh/zshrc` is one file. Split it only once it gets long enough to scroll or
slow enough to bisect.

Two files it sources stay out of git, because they hold values that differ per
machine. `install.sh` creates both, empty, and never overwrites one that
already exists:

| file            | holds                     | mode  |
| --------------- | ------------------------- | ----- |
| `~/.secrets`    | API keys and tokens       | `600` |
| `~/.zshrc.local` | per-machine overrides    | `644` |

Use `~/.zshrc.local` for anything a repo setup script wants to append to your
shell rc. `~/.zshrc` is a symlink into this repo, so an append there would edit
a tracked file.

### tools that may not be installed

`install.sh` installs no language runtime. Instead each tool block in
`zsh/zshrc` checks for the file it needs and does nothing when that file is
absent:

| tool  | gate                              |
| ----- | --------------------------------- |
| rust  | `~/.cargo/env`                    |
| nvm   | `$NVM_DIR/nvm.sh`                 |
| mise  | `~/.local/bin/mise`               |
| go    | `/usr/local/go/bin` on `$PATH`    |

The shell starts clean on a bare machine, and picks a tool up on its own the
day you install it. Add a new tool the same way: one gate, no installer.
