#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"
STAMP="$(date +%Y%m%d%H%M%S)"

# nvim-lspconfig and mason 2.x require 0.11+
NVIM_MIN_MAJOR=0
NVIM_MIN_MINOR=11

# Anything we install lands in $LOCAL_BIN, which a fresh machine may not have
# on PATH yet. Without this, re-runs would not see our own work and would
# reinstall from scratch every time. Remember whether the user's own PATH
# had it, since prepending here would mask that.
case ":$PATH:" in
  *":$LOCAL_BIN:"*) LOCAL_BIN_ON_PATH=1 ;;
  *)                LOCAL_BIN_ON_PATH=0 ;;
esac
PATH="$LOCAL_BIN:$PATH"

# source (relative to $DOTFILES) -> destination (absolute)
LINKS=(
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

# generic name : binaries that satisfy it (first is the canonical name) : flags
# flag `shim` -> if only a non-canonical binary is present, symlink the
# canonical name to it (Debian ships fd as `fdfind`, bat as `batcat`, ...)
DEPS=(
  "git:git"
  "curl:curl"
  "unzip:unzip"
  "ripgrep:rg"
  "fd:fd fdfind:shim"
  "cc:cc gcc clang"
  "tmux:tmux"
  "zsh:zsh"
)

CHECK_ONLY=0
MISSING_DEPS=()   # specs from DEPS that are not satisfied
NVIM_NEEDED=0

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m !!\033[0m %s\n' "$*" >&2; exit 1; }

have()     { command -v "$1" >/dev/null 2>&1; }
have_any() { local b; for b in $1; do have "$b" && return 0; done; return 1; }

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
    fd:apt-get|fd:dnf) echo fd-find ;;   # binary installs as `fdfind`
    cc:apt-get)        echo build-essential ;;
    cc:dnf|cc:zypper)  echo "gcc make" ;;
    cc:pacman)         echo base-devel ;;
    cc:apk)            echo build-base ;;
    cc:brew)           echo "" ;;
    *)                 echo "$1" ;;      # git, curl, unzip, ripgrep, fd
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
  local spec generic bins
  MISSING_DEPS=()
  for spec in "${DEPS[@]}"; do
    IFS=: read -r generic bins _ <<<"$spec"
    if have_any "$bins"; then
      info "found: $generic"
    else
      warn "missing: $generic"
      MISSING_DEPS+=("$spec")
    fi
  done
}

install_deps() {
  local spec generic bins pkgs=() p hint

  for spec in "${MISSING_DEPS[@]}"; do
    IFS=: read -r generic bins _ <<<"$spec"
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
    IFS=: read -r generic bins _ <<<"$spec"
    have_any "$bins" || warn "still missing after install: $generic"
  done
}

# Give a dep its canonical name when the distro installed it under another
# one, so tooling that hardcodes the usual name still works.
shim_deps() {
  local spec generic bins flags canonical b target
  for spec in "${DEPS[@]}"; do
    IFS=: read -r generic bins flags <<<"$spec"
    [[ "$flags" == shim ]] || continue
    canonical="${bins%% *}"
    have "$canonical" && continue
    for b in $bins; do
      if have "$b"; then
        target="$(command -v "$b")"
        mkdir -p "$LOCAL_BIN"
        ln -sf "$target" "$LOCAL_BIN/$canonical"
        info "shimmed: $LOCAL_BIN/$canonical -> $target"
        break
      fi
    done
  done
}

# ------------------------------------------------------------------ neovim ---

scan_neovim() {
  local banner major minor
  NVIM_NEEDED=0

  if ! have nvim; then
    warn "missing: neovim"
    NVIM_NEEDED=1
    return
  fi

  banner="$(nvim --version | head -1)"
  major="$(printf '%s' "$banner" | sed -nE 's/^NVIM v([0-9]+)\..*/\1/p')"
  minor="$(printf '%s' "$banner" | sed -nE 's/^NVIM v[0-9]+\.([0-9]+).*/\1/p')"

  if [[ -z "$major" || -z "$minor" ]]; then
    warn "could not read a version from: $banner — leaving it alone"
    return
  fi

  if (( major > NVIM_MIN_MAJOR || (major == NVIM_MIN_MAJOR && minor >= NVIM_MIN_MINOR) )); then
    info "found: $banner"
  else
    warn "$banner is older than the required $NVIM_MIN_MAJOR.$NVIM_MIN_MINOR"
    NVIM_NEEDED=1
  fi
}

# Distro packages lag badly (Ubuntu 24.04 ships 0.9.5), so pull the official
# release tarball into ~/.local instead of using $PKG_MGR.
install_neovim() {
  local asset url dest
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  asset="nvim-linux-x86_64.tar.gz" ;;
    Linux-aarch64) asset="nvim-linux-arm64.tar.gz" ;;
    Darwin-arm64)  asset="nvim-macos-arm64.tar.gz" ;;
    Darwin-x86_64) asset="nvim-macos-x86_64.tar.gz" ;;
    *) die "no neovim build for $(uname -s)-$(uname -m); install it manually" ;;
  esac

  url="https://github.com/neovim/neovim/releases/latest/download/$asset"
  dest="$HOME/.local/share/neovim"

  info "installing neovim from $url"
  rm -rf "$dest"
  mkdir -p "$dest" "$LOCAL_BIN"
  curl -fsSL "$url" | tar -xz -C "$dest" --strip-components=1
  ln -sf "$dest/bin/nvim" "$LOCAL_BIN/nvim"
  info "installed: $($LOCAL_BIN/nvim --version | head -1)"
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
  scan_neovim

  if (( CHECK_ONLY )); then
    info "check complete (no changes made)"
    return
  fi

  if (( ${#MISSING_DEPS[@]} )); then
    install_deps
  fi
  if (( NVIM_NEEDED )); then
    install_neovim
  fi
  shim_deps

  local entry
  for entry in "${ZSH_REPOS[@]}"; do
    clone_repo "${entry%:*}" "${entry##*:}"
  done
  for entry in "${TOUCH_FILES[@]}"; do
    touch_file "${entry%:*}" "${entry##*:}"
  done

  for entry in "${LINKS[@]}"; do
    link "${entry%%:*}" "${entry#*:}"
  done

  if (( ! LOCAL_BIN_ON_PATH )); then
    warn "add $LOCAL_BIN to your PATH in your shell rc"
  fi

  warn "fonts are not installed automatically: install a Nerd Font and select it in your terminal"
  info "done. run 'nvim' — lazy.nvim installs plugins, mason installs LSP servers."
}

main "$@"
