#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d%H%M%S)"

# nvim-lspconfig and mason 2.x require 0.11+; lazy.nvim pins us no lower
NVIM_MIN_MINOR=11
LOCAL_BIN="$HOME/.local/bin"

# source (relative to $DOTFILES) -> destination (absolute)
LINKS=(
  "nvim:$CONFIG_HOME/nvim"
)

# generic name -> candidate binaries that satisfy it
DEPS=(
  "git:git"
  "curl:curl"
  "unzip:unzip"
  "ripgrep:rg"
  "fd:fd fdfind"
  "cc:cc gcc clang"
)

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m !!\033[0m %s\n' "$*" >&2; exit 1; }

have()     { command -v "$1" >/dev/null 2>&1; }
have_any() { local b; for b in $1; do have "$b" && return 0; done; return 1; }

# ---------------------------------------------------------------- packages ---

detect_pkg_mgr() {
  local m
  for m in apt-get dnf pacman zypper apk brew; do
    have "$m" && { echo "$m"; return; }
  done
  echo ""
}

# Translate a generic dep name into this platform's package name.
# Empty output means "no package needed / not packaged here".
pkg_name() {
  case "$1:$PKG_MGR" in
    ripgrep:*)        echo ripgrep ;;
    fd:apt-get)       echo fd-find ;;      # binary installs as `fdfind`
    fd:dnf)           echo fd-find ;;
    fd:*)             echo fd ;;
    cc:apt-get)       echo build-essential ;;
    cc:dnf)           echo "gcc make" ;;
    cc:pacman)        echo base-devel ;;
    cc:zypper)        echo "gcc make" ;;
    cc:apk)           echo build-base ;;
    cc:brew)          echo "" ;;           # Xcode command line tools
    *:*)              echo "$1" ;;         # git, curl, unzip are named alike
  esac
}

pkg_install() {
  local pkgs="$*"
  info "installing: $pkgs"
  case "$PKG_MGR" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y $pkgs ;;
    dnf)     $SUDO dnf install -y $pkgs ;;
    pacman)  $SUDO pacman -Sy --needed --noconfirm $pkgs ;;
    zypper)  $SUDO zypper install -y $pkgs ;;
    apk)     $SUDO apk add $pkgs ;;
    brew)    brew install $pkgs ;;
  esac
}

ensure_deps() {
  local spec generic bins missing=() pkgs=() p

  for spec in "${DEPS[@]}"; do
    generic="${spec%%:*}"
    bins="${spec#*:}"
    if have_any "$bins"; then
      info "found: $generic"
    else
      missing+=("$generic")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    return
  fi

  warn "missing: ${missing[*]}"
  (( CHECK_ONLY )) && return

  [[ -n "$PKG_MGR" ]] || die "no supported package manager found; install manually: ${missing[*]}"

  for generic in "${missing[@]}"; do
    p="$(pkg_name "$generic")"
    [[ -n "$p" ]] && pkgs+=("$p")
  done

  (( ${#pkgs[@]} )) && pkg_install "${pkgs[@]}"

  # verify rather than trust the package manager's exit code
  for spec in "${DEPS[@]}"; do
    generic="${spec%%:*}"
    bins="${spec#*:}"
    have_any "$bins" || warn "still missing after install: $generic"
  done
}

# Debian/Ubuntu ship fd as `fdfind`. Telescope handles both, but plenty of
# other tooling assumes `fd`, so give it the name it expects.
shim_fd() {
  if ! have fd && have fdfind; then
    mkdir -p "$LOCAL_BIN"
    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
    info "shimmed: $LOCAL_BIN/fd -> $(command -v fdfind)"
  fi
}

# ------------------------------------------------------------------ neovim ---

nvim_minor() {
  nvim --version 2>/dev/null | head -1 | sed -nE 's/^NVIM v[0-9]+\.([0-9]+).*/\1/p'
}

# Distro packages lag badly (Ubuntu 24.04 ships 0.9.5), so pull the official
# release tarball into ~/.local instead of using $PKG_MGR.
install_neovim() {
  local asset url dest
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)   asset="nvim-linux-x86_64.tar.gz" ;;
    Linux-aarch64)  asset="nvim-linux-arm64.tar.gz" ;;
    Darwin-arm64)   asset="nvim-macos-arm64.tar.gz" ;;
    Darwin-x86_64)  asset="nvim-macos-x86_64.tar.gz" ;;
    *) die "no neovim build for $(uname -s)-$(uname -m); install it manually" ;;
  esac

  url="https://github.com/neovim/neovim/releases/latest/download/$asset"
  dest="$HOME/.local/share/neovim"

  info "installing neovim from $url"
  rm -rf "$dest" && mkdir -p "$dest" "$LOCAL_BIN"
  curl -fsSL "$url" | tar -xz -C "$dest" --strip-components=1
  ln -sf "$dest/bin/nvim" "$LOCAL_BIN/nvim"
  info "installed: $LOCAL_BIN/nvim"
}

ensure_neovim() {
  local minor
  if have nvim; then
    minor="$(nvim_minor)"
    if [[ -n "$minor" ]] && (( minor >= NVIM_MIN_MINOR )); then
      info "found: neovim ($(nvim --version | head -1))"
      return
    fi
    warn "neovim 0.$minor is older than required 0.$NVIM_MIN_MINOR"
  else
    warn "missing: neovim"
  fi

  (( CHECK_ONLY )) && return
  install_neovim
}

# ------------------------------------------------------------------- links ---

link() {
  local src="$DOTFILES/$1" dest="$2"

  [[ -e "$src" ]] || { warn "missing source: $src (skipping)"; return; }

  if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
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

main() {
  PKG_MGR="$(detect_pkg_mgr)"
  SUDO=""
  if [[ "$PKG_MGR" != "brew" && $EUID -ne 0 ]]; then
    have sudo && SUDO="sudo"
  fi
  info "package manager: ${PKG_MGR:-none}"

  ensure_deps
  ensure_neovim
  (( CHECK_ONLY )) || shim_fd

  if (( CHECK_ONLY )); then
    info "check complete (no changes made)"
    return
  fi

  local entry
  for entry in "${LINKS[@]}"; do
    link "${entry%%:*}" "${entry#*:}"
  done

  case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *) warn "$LOCAL_BIN is not on your PATH — add it to your shell rc" ;;
  esac

  warn "fonts are not installed automatically: install a Nerd Font and select it in your terminal"
  info "done. run 'nvim' — lazy.nvim installs plugins, mason installs LSP servers."
}

main "$@"
