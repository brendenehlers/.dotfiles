#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d%H%M%S)"

# source (relative to $DOTFILES) -> destination (absolute)
LINKS=(
  "nvim:$CONFIG_HOME/nvim"
)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

link() {
  local src="$DOTFILES/$1" dest="$2"

  if [[ ! -e "$src" ]]; then
    warn "missing source: $src (skipping)"
    return
  fi

  # already linked correctly -> nothing to do
  if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
    info "ok: $dest"
    return
  fi

  # something else is there -> move it aside rather than destroy it
  if [[ -e "$dest" || -L "$dest" ]]; then
    warn "backing up $dest -> $dest.bak.$STAMP"
    mv "$dest" "$dest.bak.$STAMP"
  fi

  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  info "linked: $dest -> $src"
}

check_deps() {
  local required=(git nvim) optional=(rg fd cc curl unzip)
  local missing=()

  for c in "${required[@]}"; do
    command -v "$c" >/dev/null || missing+=("$c")
  done
  if (( ${#missing[@]} )); then
    warn "required commands not found: ${missing[*]}"
    exit 1
  fi

  for c in "${optional[@]}"; do
    command -v "$c" >/dev/null || warn "optional dependency not found: $c"
  done
}

main() {
  check_deps
  for entry in "${LINKS[@]}"; do
    link "${entry%%:*}" "${entry#*:}"
  done
  info "done. run 'nvim' — lazy.nvim will install plugins, mason will install LSP servers."
}

main "$@"
