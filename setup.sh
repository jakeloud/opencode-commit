#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_PLUGIN_FILE="$SCRIPT_DIR/.opencode/plugins/agent-commit.js"
SOURCE_PACKAGE_FILE="$SCRIPT_DIR/.opencode/package.json"

if [ ! -f "$SOURCE_PLUGIN_FILE" ]; then
  printf 'Could not find plugin source at %s\n' "$SOURCE_PLUGIN_FILE" >&2
  exit 1
fi

prompt_default() {
  local label=$1
  local default_value=$2
  local value

  printf '%s [%s]: ' "$label" "$default_value" >&2
  IFS= read -r value
  if [ -z "$value" ]; then
    value=$default_value
  fi
  printf '%s' "$value"
}

prompt_required() {
  local label=$1
  local example=${2:-}
  local value

  while :; do
    if [ -n "$example" ]; then
      printf '%s (%s): ' "$label" "$example" >&2
    else
      printf '%s: ' "$label" >&2
    fi
    IFS= read -r value
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return
    fi
    printf 'This value is required.\n' >&2
  done
}

prompt_yes_no() {
  local label=$1
  local default_value=$2
  local value

  while :; do
    printf '%s [%s]: ' "$label" "$default_value" >&2
    IFS= read -r value
    if [ -z "$value" ]; then
      value=$default_value
    fi
    case $(printf '%s' "$value" | tr '[:upper:]' '[:lower:]') in
      y|yes|true|1)
        printf 'true'
        return
        ;;
      n|no|false|0)
        printf 'false'
        return
        ;;
    esac
    printf 'Please answer yes or no.\n' >&2
  done
}

escape_json() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
    return
  fi

  if command -v node >/dev/null 2>&1; then
    VALUE=$1 node -p 'JSON.stringify(process.env.VALUE)'
    return
  fi

  printf 'python3 or node is required to write JSON config.\n' >&2
  exit 1
}

printf 'OpenCode Agent Commit setup\n'
printf 'This installer will copy the plugin and save your configuration.\n\n'

install_scope=$(prompt_default 'Install scope: global or project' 'global')
install_scope=$(printf '%s' "$install_scope" | tr '[:upper:]' '[:lower:]')

case "$install_scope" in
  global|g)
    CONFIG_ROOT="${HOME}/.config/opencode"
    CONFIG_LABEL='global OpenCode config'
    ;;
  project|p)
    target_repo=$(prompt_required 'Project path to install into' '/absolute/path/to/repo')
    if [ ! -d "$target_repo" ]; then
      printf 'Directory does not exist: %s\n' "$target_repo" >&2
      exit 1
    fi
    CONFIG_ROOT="$target_repo/.opencode"
    CONFIG_LABEL='project .opencode directory'
    ;;
  *)
    printf 'Install scope must be global or project.\n' >&2
    exit 1
    ;;
esac

agent_name=$(prompt_default 'Agent display name' 'OpenCode Agent')
agent_email=$(prompt_required 'Agent commit email' '12345678+my-agent[bot]@users.noreply.github.com')
commit_message=$(prompt_default 'Default auto-commit message' 'chore(agent): save OpenCode session changes')
enabled=$(prompt_yes_no 'Enable plugin' 'yes')
rewrite_git_commit=$(prompt_yes_no 'Rewrite OpenCode git commit commands' 'yes')
commit_on_idle=$(prompt_yes_no 'Auto-commit when session becomes idle' 'yes')

PLUGIN_DIR="$CONFIG_ROOT/plugins"
PACKAGE_FILE="$CONFIG_ROOT/package.json"
CONFIG_FILE="$CONFIG_ROOT/agent-commit.json"

mkdir -p "$PLUGIN_DIR"
cp "$SOURCE_PLUGIN_FILE" "$PLUGIN_DIR/agent-commit.js"

if [ ! -f "$PACKAGE_FILE" ]; then
  cp "$SOURCE_PACKAGE_FILE" "$PACKAGE_FILE"
fi

cat > "$CONFIG_FILE" <<EOF
{
  "enabled": $enabled,
  "rewriteGitCommit": $rewrite_git_commit,
  "commitOnIdle": $commit_on_idle,
  "name": $(escape_json "$agent_name"),
  "email": $(escape_json "$agent_email"),
  "message": $(escape_json "$commit_message")
}
EOF

printf '\nInstalled plugin into %s\n' "$CONFIG_LABEL"
printf 'Plugin file: %s\n' "$PLUGIN_DIR/agent-commit.js"
printf 'Config file: %s\n' "$CONFIG_FILE"

if [ "$install_scope" = "global" ] || [ "$install_scope" = "g" ]; then
  printf '\nNext steps:\n'
  printf '1. Start OpenCode in any git repo: opencode\n'
  printf '2. Ask it to edit a file and wait for the session to go idle\n'
  printf '3. Verify with: git log -1 --format="%%an <%%ae> | %%cn <%%ce> | %%s"\n'
else
  printf '\nNext steps:\n'
  printf '1. cd %s\n' "$target_repo"
  printf '2. Start OpenCode there: opencode\n'
  printf '3. Ask it to edit a file and wait for the session to go idle\n'
  printf '4. Verify with: git log -1 --format="%%an <%%ae> | %%cn <%%ce> | %%s"\n'
fi

printf '\nGitHub attribution only works if the configured email is verified on the target GitHub account.\n'
