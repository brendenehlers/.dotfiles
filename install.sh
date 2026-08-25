#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"
STAMP="$(date +%Y%m%d%H%M%S)"

MISE_BIN="$LOCAL_BIN/mise"
MISE_SHIMS="$HOME/.local/share/mise/shims"

# Anything we install lands in $MISE_SHIMS or $LOCAL_BIN, which a fresh machine
# may not have on PATH yet. Without this, re-runs would not see our own work and
# would reinstall from scratch every time. Remember whether the user's own PATH
# had them, since prepending here would mask that.
case ":$PATH:" in
  *":$LOCAL_BIN:"*) LOCAL_BIN_ON_PATH=1 ;;
  *)                LOCAL_BIN_ON_PATH=0 ;;
esac
case ":$PATH:" in
  *":$MISE_SHIMS:"*) MISE_SHIMS_ON_PATH=1 ;;
  *)                 MISE_SHIMS_ON_PATH=0 ;;
esac
# Shims first: mise owns these tools, and a distro copy must not win.
PATH="$MISE_SHIMS:$LOCAL_BIN:$PATH"

# source (relative to $DOTFILES) -> destination (absolute)
LINKS=(
  "mise/config.toml:$CONFIG_HOME/mise/config.toml"
  "nvim:$CONFIG_HOME/nvim"
  "tmux/tmux.conf:$HOME/.tmux.conf"
  "zsh/zshrc:$HOME/.zshrc"
  "zsh/p10k.zsh:$HOME/.p10k.zsh"
)

# url : destination (absolute). zshrc sources each of these behind a file
# check, but the prompt is unusable without them, so clone them rather than
# let the check hide a broken setup.
ZSH_REPOS=(
  "https://github.com/ohmyzsh/ohmyzsh.git:$HOME/.oh-my-zsh"
  "https://github.com/romkatv/powerlevel10k.git:$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  "https://github.com/zsh-users/zsh-syntax-highlighting.git:$HOME/.zsh-plugins/zsh-syntax-highlighting"
)

# path : mode. zshrc sources these; they hold machine-local values and never
# enter git.
TOUCH_FILES=(
  "$HOME/.secrets:600"
  "$HOME/.zshrc.local:644"
)

# Packages the system owns. These bootstrap mise, build native code, or must be
# registered with the system to work at all — a login shell needs an entry in
# /etc/shells. Everything else belongs to mise; see MISE_TOOLS.
#
# generic name : binaries that satisfy it (first is the canonical name) : unused
#              : probe flag that confirms the binary runs (default --version)
DEPS=(
  "git:git"
  "curl:curl"
  "unzip:unzip::-v"
  "cc:cc gcc clang"
  "zsh:zsh"
)

# Tools mise installs. The versions live in mise/config.toml, which LINKS puts
# at $CONFIG_HOME/mise/config.toml before `mise install` reads it.
#
# tool name as mise knows it : binary it provides : probe flag (default --version)
MISE_TOOLS=(
  "neovim:nvim"
  "ripgrep:rg"
  "fd:fd"
  "tmux:tmux:-V"
)

CHECK_ONLY=0
MISSING_DEPS=()    # specs from DEPS that are not satisfied
MISSING_TOOLS=()   # specs from MISE_TOOLS that are not satisfied
MISE_NEEDED=0

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m !!\033[0m %s\n' "$*" >&2; exit 1; }

have()     { command -v "$1" >/dev/null 2>&1; }

# A name on PATH is not proof of a usable binary. A version manager can leave a
# shim that resolves but exits non-zero, and every caller then sees the dep as
# installed. Run the binary to settle it.
works()    { have "$1" && "$1" "${2:---version}" >/dev/null 2>&1; }
works_any() { local b; for b in $1; do works "$b" "$2" && return 0; done; return 1; }

usage() {
  cat <<EOF
usage: install.sh [--check]

  --check   report what is missing; make no changes
  -h        show this message
EOF
}

# ---------------------------------------------------------------- packages ---

detect_pkg_mgr() {
  local m
  for m in apt-get dnf pacman zypper apk brew; do
    have "$m" && { echo "$m"; return; }
  done
  echo ""
}

# Translate a generic dep name into this platform's package name.
# Empty output means "not packaged here" — see pkg_hint for what to tell the user.
pkg_name() {
  case "$1:$PKG_MGR" in
    cc:apt-get)        echo build-essential ;;
    cc:dnf|cc:zypper)  echo "gcc make" ;;
    cc:pacman)         echo base-devel ;;
    cc:apk)            echo build-base ;;
    cc:brew)           echo "" ;;
    *)                 echo "$1" ;;      # git, curl, unzip, zsh
  esac
}

# What to tell the user when pkg_name has nothing to install.
pkg_hint() {
  case "$1:$PKG_MGR" in
    cc:brew) echo "run: xcode-select --install" ;;
    *)       echo "" ;;
  esac
}

pkg_install() {
  info "installing: $*"
  case "$PKG_MGR" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y "$@" ;;
    dnf)     $SUDO dnf install -y "$@" ;;
    pacman)  $SUDO pacman -Sy --needed --noconfirm "$@" ;;
    zypper)  $SUDO zypper install -y "$@" ;;
    apk)     $SUDO apk add "$@" ;;
    brew)    brew install "$@" ;;
    *)       die "no supported package manager found; install manually: $*" ;;
  esac
}

scan_deps() {
  local spec generic bins probe b
  MISSING_DEPS=()
  for spec in "${DEPS[@]}"; do
    IFS=: read -r generic bins _ probe <<<"$spec"
    if works_any "$bins" "$probe"; then
      info "found: $generic"
      continue
    fi
    for b in $bins; do
      have "$b" && warn "$(command -v "$b") is on PATH but does not run"
    done
    warn "missing: $generic"
    MISSING_DEPS+=("$spec")
  done
}

install_deps() {
  local spec generic bins probe b pkgs=() p hint

  for spec in "${MISSING_DEPS[@]}"; do
    IFS=: read -r generic bins _ probe <<<"$spec"
    p="$(pkg_name "$generic")"
    if [[ -n "$p" ]]; then
      pkgs+=($p)   # unquoted on purpose: "gcc make" is two packages
    else
      hint="$(pkg_hint "$generic")"
      warn "no package for $generic on ${PKG_MGR:-this system}${hint:+ — $hint}"
    fi
  done

  if (( ${#pkgs[@]} )); then
    pkg_install "${pkgs[@]}"
  fi

  # verify rather than trust the package manager's exit code
  for spec in "${MISSING_DEPS[@]}"; do
    IFS=: read -r generic bins _ probe <<<"$spec"
    works_any "$bins" "$probe" && continue
    warn "still missing after install: $generic"
    for b in $bins; do
      have "$b" && warn "  $(command -v "$b") shadows it; remove it or point it at a real $b"
    done
  done
}

# -------------------------------------------------------------------- mise ---

scan_mise() {
  local spec tool bin probe
  MISSING_TOOLS=()
  MISE_NEEDED=0

  if works "$MISE_BIN"; then
    info "found: $($MISE_BIN --version)"
  else
    warn "missing: mise"
    MISE_NEEDED=1
  fi

  # Nothing can be probed through a mise that is not there yet.
  if (( MISE_NEEDED )); then
    MISSING_TOOLS=("${MISE_TOOLS[@]}")
    return
  fi

  for spec in "${MISE_TOOLS[@]}"; do
    IFS=: read -r tool bin probe <<<"$spec"
    # `mise which` fails unless mise itself provides the binary, so a distro
    # copy still on PATH does not read as a satisfied tool.
    if mise_owns "$bin" && works "$bin" "$probe"; then
      info "found: $tool ($(command -v "$bin"))"
    else
      have "$bin" && warn "$(command -v "$bin") is not the mise copy"
      warn "missing: $tool"
      MISSING_TOOLS+=("$spec")
    fi
  done
}

mise_owns() { "$MISE_BIN" which "$1" >/dev/null 2>&1; }

# mise refuses to read a config file it has not been trusted with. The linked
# path resolves into the dotfiles repo, which counts as an untrusted project
# config, so trust it by hand rather than let every later call fail.
trust_mise_config() {
  "$MISE_BIN" trust --quiet "$DOTFILES/mise/config.toml"
}

# The official installer reads MISE_INSTALL_PATH, so mise lands beside
# everything else this script installs instead of in its own prefix.
install_mise() {
  info "installing mise -> $MISE_BIN"
  mkdir -p "$LOCAL_BIN"
  curl -fsSL https://mise.run | MISE_INSTALL_PATH="$MISE_BIN" sh
  works "$MISE_BIN" || die "mise did not install; see https://mise.jdx.dev"
  info "installed: $($MISE_BIN --version)"
}

# `mise install` with no arguments installs every tool named in the linked
# config, so the pinned versions are the single source of truth.
install_mise_tools() {
  local spec tool bin probe

  info "installing tools from $CONFIG_HOME/mise/config.toml"
  "$MISE_BIN" install --yes
  "$MISE_BIN" reshim

  # verify rather than trust mise's exit code
  for spec in "${MISE_TOOLS[@]}"; do
    IFS=: read -r tool bin probe <<<"$spec"
    mise_owns "$bin" && works "$bin" "$probe" && continue
    warn "still missing after install: $tool"
    have "$bin" && warn "  $(command -v "$bin") shadows it; remove it or fix that copy"
  done
}

# Earlier versions of this script installed neovim into ~/.local/share/neovim
# and symlinked fd by hand. mise owns both now. A leftover symlink wins whenever
# the shims directory is not first on PATH, so drop the ones we made.
prune_local_bin() {
  local link target
  for link in "$LOCAL_BIN/nvim" "$LOCAL_BIN/fd"; do
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    case "$target" in
      "$HOME/.local/share/neovim/"*|*/fdfind)
        rm -f "$link"
        info "removed stale link: $link -> $target"
        ;;
    esac
  done

  if [[ -d "$HOME/.local/share/neovim" ]]; then
    warn "old neovim install left at $HOME/.local/share/neovim — remove it when you are ready"
  fi
}

# --------------------------------------------------------------------- zsh ---

clone_repo() {
  local url="$1" dest="$2"

  if [[ -d "$dest/.git" ]]; then
    info "ok: $dest"
    return
  fi

  if [[ -e "$dest" ]]; then
    warn "backing up $dest -> $dest.bak.$STAMP"
    mv "$dest" "$dest.bak.$STAMP"
  fi

  info "cloning $url -> $dest"
  mkdir -p "$(dirname "$dest")"
  git clone --depth 1 "$url" "$dest"
}

# Create an empty file the shell can source. Never overwrite one that exists:
# it holds the user's own secrets.
touch_file() {
  local path="$1" mode="$2"

  if [[ ! -e "$path" ]]; then
    info "creating: $path"
    : > "$path"
  fi
  chmod "$mode" "$path"
}

# ------------------------------------------------------------------- links ---

link() {
  local src="$DOTFILES/$1" dest="$2"

  [[ -e "$src" ]] || { warn "missing source: $src (skipping)"; return; }

  # -ef compares device+inode through symlinks; unlike `readlink -f` it is a
  # bash builtin and works on stock macOS.
  if [[ -L "$dest" && "$dest" -ef "$src" ]]; then
    info "ok: $dest"
    return
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    warn "backing up $dest -> $dest.bak.$STAMP"
    mv "$dest" "$dest.bak.$STAMP"
  fi

  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  info "linked: $dest -> $src"
}

# -------------------------------------------------------------------- main ---

parse_args() {
  while (( $# )); do
    case "$1" in
      --check) CHECK_ONLY=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  PKG_MGR="$(detect_pkg_mgr)"
  SUDO=""
  if [[ "$PKG_MGR" != brew && $EUID -ne 0 ]] && have sudo; then
    SUDO=sudo
  fi
  info "package manager: ${PKG_MGR:-none}"

  scan_deps
  scan_mise

  if (( CHECK_ONLY )); then
    info "check complete (no changes made)"
    return
  fi

  if (( ${#MISSING_DEPS[@]} )); then
    install_deps
  fi
  if (( MISE_NEEDED )); then
    install_mise
  fi

  # Link before installing: `mise install` reads the config this puts in place.
  local entry
  for entry in "${LINKS[@]}"; do
    link "${entry%%:*}" "${entry#*:}"
  done

  if (( ${#MISSING_TOOLS[@]} )); then
    trust_mise_config
    install_mise_tools
  fi
  prune_local_bin

  for entry in "${ZSH_REPOS[@]}"; do
    clone_repo "${entry%:*}" "${entry##*:}"
  done
  for entry in "${TOUCH_FILES[@]}"; do
    touch_file "${entry%:*}" "${entry##*:}"
  done

  if (( ! LOCAL_BIN_ON_PATH )); then
    warn "add $LOCAL_BIN to your PATH in your shell rc"
  fi
  if (( ! MISE_SHIMS_ON_PATH )); then
    warn "add $MISE_SHIMS to your PATH in your shell rc (zsh/zshrc already does)"
  fi

  warn "fonts are not installed automatically: install a Nerd Font and select it in your terminal"
  info "done. run 'nvim' — lazy.nvim installs plugins, mason installs LSP servers."
}

main "$@"
