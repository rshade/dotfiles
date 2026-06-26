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

# Temp installer path, removed on any exit. A single EXIT trap (not a per-function
# RETURN trap) avoids firing against an out-of-scope local; ${VAR:-} keeps it
# nounset-safe even if we exit before the download.
INSTALLER_TMP=""
cleanup() { [ -n "${INSTALLER_TMP:-}" ] && rm -f "$INSTALLER_TMP"; }
trap cleanup EXIT

# Populated by install_mise (the installer's output) and activate_in_shell (the
# rc file we touched) so main can reuse them. Guarded with ${VAR:-} at use sites.
MISE_INSTALL_OUTPUT=""
RC_FILE=""

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
  INSTALLER_TMP="$(mktemp)"
  local installer="$INSTALLER_TMP"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://mise.run -o "$installer"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$installer" https://mise.run
  else
    warn "Need curl or wget to download the mise installer."
    return 1
  fi

  # MISE_VERSION (if set) is consumed by the official installer to pin a release.
  # Capture combined output so we can reuse the activation line it prints (which
  # may land on stdout or stderr); reprint only the clean `mise:` status lines so
  # the transient download progress bar doesn't clutter the log.
  MISE_INSTALL_OUTPUT="$(sh "$installer" 2>&1)"
  printf '%s\n' "$MISE_INSTALL_OUTPUT" | grep -a '^mise:' || printf '%s\n' "$MISE_INSTALL_OUTPUT"
}

# Add `mise activate` to the shell rc exactly once. Activation installs shims and
# keeps tool versions in sync with the directory you're in.
activate_in_shell() {
  local mise rc shell_name activate_line captured
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

  # Prefer the exact `eval "$(... activate ...)"` line that `mise install` printed
  # (it suggests it as `echo "..." >> rc`); strip that wrapper and unescape \" \$.
  # Fall back to the constructed line above if the output didn't contain it.
  captured="$(printf '%s\n' "${MISE_INSTALL_OUTPUT:-}" | grep -m1 'mise activate' || true)"
  if [ -n "$captured" ]; then
    activate_line="$(printf '%s\n' "$captured" \
      | sed -e 's/^[[:space:]]*echo "//' -e 's/" >> .*$//' -e 's/\\"/"/g' -e 's/\\\$/$/g')"
  fi

  RC_FILE="$rc"
  if [ -f "$rc" ] && grep -q "mise activate" "$rc"; then
    log "mise activation already present in $rc"
  else
    log "Adding mise activation to $rc:"
    log "  $activate_line"
    printf '\n# mise — polyglot tool version manager\n%s\n' "$activate_line" >>"$rc"
  fi
}

main() {
  install_mise
  activate_in_shell
  local mise
  mise="$(resolve_mise)"
  log "Done. mise $("$mise" --version)"
  log "Run 'mise install' in a project with a mise.toml to provision its tools."
  if [ -n "${RC_FILE:-}" ]; then
    log "Activate mise in your CURRENT shell now (so the tools are on PATH):"
    log "  source $RC_FILE"
  fi
}

main "$@"
