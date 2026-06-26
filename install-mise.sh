#!/usr/bin/env bash
#
# install-mise.sh — install mise (https://mise.jdx.dev) and wire it into the shell.
#
# mise is a polyglot tool-version manager (a single replacement for asdf, nvm,
# pyenv, gvm, ...). This script is idempotent: re-running it upgrades/repairs the
# install and ensures shell activation without creating duplicate lines.
#
# Usage:
#   ./install-mise.sh                 # install + activate for the detected shell
#   MISE_VERSION=v2026.5.15 ./install-mise.sh   # pin a specific mise version
#   SHELL_RC=~/.zshrc ./install-mise.sh         # override the rc file to edit
#
set -euo pipefail

# Where mise installs its binary. Honour an existing MISE_INSTALL_PATH, else the
# documented default of ~/.local/bin/mise. No hardcoded absolute paths.
MISE_BIN="${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }

# Resolve the mise executable: prefer one already on PATH, fall back to MISE_BIN.
resolve_mise() {
  if command -v mise >/dev/null 2>&1; then
    command -v mise
  elif [ -x "$MISE_BIN" ]; then
    printf '%s\n' "$MISE_BIN"
  else
    return 1
  fi
}

install_mise() {
  if resolve_mise >/dev/null 2>&1; then
    log "mise already present ($("$(resolve_mise)" --version)); re-running installer to update."
  else
    log "Installing mise..."
  fi

  # The official installer verifies the download checksum/signature itself.
  # Fetch it to a temp file first (auditable, and keeps pipefail meaningful)
  # rather than piping curl straight into sh.
  local installer
  installer="$(mktemp)"
  trap 'rm -f "$installer"' RETURN

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://mise.run -o "$installer"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$installer" https://mise.run
  else
    warn "Need curl or wget to download the mise installer."
    return 1
  fi

  # MISE_VERSION (if set) is consumed by the official installer to pin a release.
  sh "$installer"
}

# Add `mise activate` to the shell rc exactly once. Activation installs shims and
# keeps tool versions in sync with the directory you're in.
activate_in_shell() {
  local mise rc shell_name activate_line
  mise="$(resolve_mise)"

  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    zsh)  rc="${SHELL_RC:-$HOME/.zshrc}";  activate_line="eval \"\$($mise activate zsh)\"" ;;
    bash) rc="${SHELL_RC:-$HOME/.bashrc}"; activate_line="eval \"\$($mise activate bash)\"" ;;
    *)
      warn "Unrecognised shell '$shell_name'. Add this to your shell rc manually:"
      warn "  eval \"\$($mise activate $shell_name)\""
      return 0
      ;;
  esac

  if [ -f "$rc" ] && grep -q "mise activate" "$rc"; then
    log "mise activation already present in $rc"
  else
    log "Adding mise activation to $rc"
    printf '\n# mise — polyglot tool version manager\n%s\n' "$activate_line" >>"$rc"
  fi
}

main() {
  install_mise
  activate_in_shell
  local mise
  mise="$(resolve_mise)"
  log "Done. mise $("$mise" --version)"
  log "Open a new shell (or 'source' your rc), then run 'mise install' in a project with a mise.toml."
}

main "$@"
