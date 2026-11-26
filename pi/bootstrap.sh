#!/usr/bin/env bash
# Sets up the Pi configuration on a new machine. Safe to run again.
# Usage: ~/.dotfiles/pi/bootstrap.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="$HOME/.pi/agent"

say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

say "== Dependencies"
missing=()
for tool in stow jq git pi; do have "$tool" || missing+=("$tool"); done
have pdftotext || say "  optional: poppler missing (pdf-tools skill): brew install poppler"
if ((${#missing[@]})); then
  say "  missing: ${missing[*]}"
  say "  macOS: brew install stow jq pi-coding-agent"
  exit 1
fi

say "== Stow"
(cd "$root" && stow --restow --target "$HOME" pi)

say "== Git filter for settings.json (keeps Pi version fields out of commits)"
git -C "$root" config filter.pi-settings.clean \
  "jq 'del(.lastChangelogVersion, .extensionChangelogVersions)'"
git -C "$root" config filter.pi-settings.smudge cat

say "== Logins"
auth="$agent/auth.json"
for provider in anthropic github-copilot openrouter radius; do
  if [ -f "$auth" ] && jq -e --arg p "$provider" 'has($p)' "$auth" >/dev/null 2>&1; then
    say "  ok       $provider"
  else
    case "$provider" in
      openrouter) hint="pi auth login openrouter --api-key" ;;
      *) hint="pi auth login $provider" ;;
    esac
    say "  missing  $provider -> $hint"
  fi
done
say "  (at least one model provider is needed; see README.md for what each adds)"

say "Done."
