# AGENTS.md

Notes for agents that edit this repo.

## Layout

`install.sh` owns every path. Two arrays in that file drive it:

- `LINKS` maps a path in this repo to the path it is linked to.
- `MISE_TOOLS` lists the command line tools, with the data needed to probe
  each one.

Read those arrays for the current state. Do not copy them into other files,
because a second copy goes stale.

## Adding a new config

Put the directory or file in the repo root. Add one line to `LINKS` in
`install.sh`:

```sh
LINKS=(
  "nvim:$CONFIG_HOME/nvim"
  "tmux/tmux.conf:$HOME/.tmux.conf"
  "git/gitconfig:$HOME/.gitconfig"
)
```

## Adding or removing a mise tool

[mise](https://mise.jdx.dev) owns the command line tools. A tool must be
declared in two places. Change both in the same commit.

1. `mise/config.toml`, under `[tools]`. Pin an exact version. This file is the
   source of truth for versions, and `mise install` reads only this file.
2. `MISE_TOOLS` in `install.sh`. This array holds the probe data that
   `mise/config.toml` cannot express.

Each `MISE_TOOLS` entry is `tool:binary:probe`.

- `tool` is the name mise knows, and must match the `[tools]` key.
- `binary` is the command the tool provides. It often differs from the tool
  name, for example `ripgrep` provides `rg`.
- `probe` is the flag that prints the version. Leave it empty for `--version`.
  Set it when the tool differs, for example `tmux` needs `-V`.

`install.sh` uses `MISE_TOOLS` to report missing tools before an install, and
to verify each binary after the install. If you skip this array, the tool still
installs, but `install.sh --check` never reports it.

Bump a version with `mise use -g <tool>@<version>`. That edits
`mise/config.toml` through the symlink, so the change lands in this repo.

## What the package manager still owns

`git`, `curl`, `unzip`, a C compiler, and `zsh`. Those bootstrap mise, build
native code, or must be registered with the system. Everything else belongs to
mise. The `DEPS` array in `install.sh` holds the current list.

## PATH order

`~/.local/share/mise/shims` must come first on `PATH`, otherwise a distro copy
of a tool wins. `zsh/zshrc` already prepends it.
