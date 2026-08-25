# brenden's dotfiles repo

how do i get what's in here, and put it over there!

## bootstrap

```sh
git clone git@github.com:brendenehlers/.dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

Use `install.sh --check` to report what's missing without installing or
changing anything.

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

## zsh

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

