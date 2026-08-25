# brenden's dotfiles repo

how do i get what's in here, and put it over there!

## bootstrap

```sh
git clone git@github.com:brendenehlers/.dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

`install.sh` links every config into place, installs the tools, and creates the
two untracked zsh files. Run it again any time; it is safe to repeat.

Use `install.sh --check` to report what's missing without installing or
changing anything.

## zsh

Two files that `~/.zshrc` sources stay out of git, because they hold values that
differ per machine. `install.sh` creates both, empty, and never overwrites one
that already exists:

| file             | holds                  | mode  |
| ---------------- | ---------------------- | ----- |
| `~/.secrets`     | API keys and tokens    | `600` |
| `~/.zshrc.local` | per-machine overrides  | `644` |

Use `~/.zshrc.local` for anything a repo setup script wants to append to your
shell rc. `~/.zshrc` is a symlink into this repo, so an append there would edit
a tracked file.
