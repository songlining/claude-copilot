# claude-copilot.zsh — Launch Claude Code through the GitHub Copilot proxy
# Source this file from .zshrc:  source /path/to/claude-copilot.zsh
#
# Commands:
#   claude-copilot [model]   Start Claude Code (fzf picker if no model given)
#   copilot-models           List all models available through the proxy
#   copilot-proxy-stop       Kill the background proxy
#
# Mid-session model switching:
#   /model                   Pick from Sonnet / Opus / Haiku
#   /model <name>            Any proxy model (e.g. /model gpt-4o)

# Models excluded from the picker (not chat models).
_COPILOT_EXCLUDED_MODELS="embedding"

_copilot_fetch_models() {
  curl -s http://localhost:4141/v1/models | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
exclude = re.compile(r'$_COPILOT_EXCLUDED_MODELS', re.I)
seen = set()
for m in sorted(data.get('data', []), key=lambda x: x['id']):
    mid = m['id']
    if mid not in seen and not exclude.search(mid):
        seen.add(mid)
        print(mid)
" 2>/dev/null
}

claude-copilot() {
  local model="$1"

  # Reuse existing proxy if it's healthy, otherwise start a new one
  if curl -sf http://localhost:4141/v1/models &>/dev/null; then
    echo "✅ Copilot proxy already running on :4141"
  else
    # Kill stale process if port is held but not responding
    local old_pid
    old_pid=$(lsof -ti:4141 2>/dev/null)
    if [[ -n "$old_pid" ]]; then
      kill "$old_pid" 2>/dev/null
      sleep 0.5
    fi
    nohup copilot-api start --account-type business > /tmp/copilot-api.log 2>&1 &
    disown

    # Wait for proxy to be ready (up to 6 seconds)
    local i
    for i in {1..20}; do
      curl -sf http://localhost:4141/v1/models &>/dev/null && break
      sleep 0.3
    done
  fi

  # If no model supplied, fetch model list and present picker
  if [[ -z "$model" ]]; then
    local model_ids
    model_ids=$(_copilot_fetch_models)

    if [[ -z "$model_ids" ]]; then
      echo "⚠️  Could not fetch model list. Defaulting to claude-opus-4.6."
      model="claude-opus-4.6"
    elif command -v fzf &>/dev/null; then
      model=$(echo "$model_ids" | fzf --prompt="Select model: " --height=~10 --layout=reverse)
    else
      echo "fzf not found. Select a model:"
      local -a model_array
      model_array=(${(f)model_ids})
      select choice in "${model_array[@]}"; do
        if [[ -n "$choice" ]]; then
          model="$choice"
          break
        fi
        echo "Invalid selection."
      done
    fi

    if [[ -z "$model" ]]; then
      echo "No model selected. Exiting."
      return 1
    fi
  fi

  # Copy launch command to clipboard and print it
  local cmd="ANTHROPIC_BASE_URL=http://localhost:4141 claude --model $model"
  if command -v pbcopy &>/dev/null; then
    echo "$cmd" | pbcopy
    echo "📋 Copied launch command to clipboard"
  fi
  echo "🚀 $cmd"
  echo ""
  echo "💡 Switch models mid-session:"
  echo "   /model              → pick from Sonnet / Opus / Haiku"
  echo "   /model <name>       → any proxy model (e.g. /model gpt-4o)"
  echo "   copilot-models      → list all available proxy models"
  echo ""

  # Launch Claude Code with env vars that map the /model picker slots
  # ANTHROPIC_DEFAULT_*_MODEL tells Claude Code what model ID to send
  # when the user picks "Sonnet", "Opus", or "Haiku" from /model
  ANTHROPIC_BASE_URL=http://localhost:4141 \
  ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4.6 \
  ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4.6 \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4.5 \
  claude --model "$model" "${@:2}"
}

# List all models available through the copilot proxy
copilot-models() {
  if ! curl -sf http://localhost:4141/v1/models &>/dev/null; then
    echo "⚠️  Copilot proxy not running. Start with: claude-copilot"
    return 1
  fi
  echo "📦 Models available via copilot proxy (use with /model <name>):"
  echo ""
  local models
  models=$(_copilot_fetch_models)
  echo "$models" | while read -r m; do echo "  $m"; done
  echo ""
  echo "  ($(echo "$models" | wc -l | tr -d ' ') models)"
}

alias copilot-proxy-stop='lsof -ti:4141 | xargs kill 2>/dev/null && echo "Copilot proxy stopped"'
