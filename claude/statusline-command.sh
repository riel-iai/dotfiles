#!/usr/bin/env bash
input=$(cat)

# ANSI colors ($'...' syntax so escapes work in both printf and string assignment)
GREEN=$'\033[0;32m'
BRIGHT_GREEN=$'\033[38;5;28m'
YELLOW=$'\033[38;5;220m'
RED=$'\033[38;5;196m'
BLUE=$'\033[0;34m'
PINK=$'\033[38;5;175m'
OLIVE=$'\033[38;5;142m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
RESET=$'\033[0m'

model=$(echo "$input"        | jq -r '.model.display_name // "Unknown"')
cwd=$(echo "$input"          | jq -r '.workspace.current_dir // .cwd // ""')
dir=$(basename "$cwd")
session_name=$(echo "$input" | jq -r '.session_name // empty')
vim_mode=$(echo "$input"     | jq -r '.vim.mode // empty')

# Total tokens and pricing (input ~$3/M, output ~$15/M for Sonnet 4.x)
total_in=$(echo "$input"     | jq -r '.context_window.total_input_tokens  // 0')
total_out=$(echo "$input"    | jq -r '.context_window.total_output_tokens // 0')
cost=$(awk "BEGIN {printf \"\$%.4f\", ($total_in/1000000)*3 + ($total_out/1000000)*15}")

# Context window remaining percentage (pre-calculated by Claude Code)
ctx_remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_used=$(echo "$input"      | jq -r '.context_window.used_percentage // empty')

# 5h rate limit from Claude's own tracking
limit_pct=$(echo "$input"    | jq -r '.rate_limits.five_hour.used_percentage // 0')
reset_epoch=$(echo "$input"  | jq -r '.rate_limits.five_hour.resets_at // empty')
reset_time_str=""
if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt 0 ] 2>/dev/null; then
  reset_time_str=$(date -d "@${reset_epoch}" +"%H:%M" 2>/dev/null || date -r "${reset_epoch}" +"%H:%M" 2>/dev/null)
fi

# Session duration: use a per-session start-time file keyed by session_id.
session_id=$(echo "$input" | jq -r '.session_id // empty')
duration_str=""
now_epoch=$(date +%s)
if [ -n "$session_id" ]; then
  start_file="/tmp/claude_statusline_${session_id}"
  if [ ! -f "$start_file" ]; then
    echo "$now_epoch" > "$start_file"
  fi
  start_epoch=$(cat "$start_file" 2>/dev/null)
  if [ -n "$start_epoch" ] && [ "$start_epoch" -gt 0 ] 2>/dev/null; then
    elapsed=$(( now_epoch - start_epoch ))
    if [ "$elapsed" -ge 0 ]; then
      h=$(( elapsed / 3600 ))
      m=$(( (elapsed % 3600) / 60 ))
      s=$(( elapsed % 60 ))
      if [ "$h" -gt 0 ]; then
        duration_str=$(printf "%dh%02dm" "$h" "$m")
      else
        duration_str=$(printf "%dm%02ds" "$m" "$s")
      fi
    fi
  fi
fi

# Git branch for the current working directory
branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# Progress bar — color shifts yellow above 60%, red above 85%
make_bar() {
  local pct=$1
  local width=${2:-10}
  local filled=$(echo "$pct $width" | awk '{printf "%d", ($1/100)*$2 + 0.5}')
  local empty=$(( width - filled ))
  local bar=""
  local i
  for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
  for (( i=0; i<empty;  i++ )); do bar="${bar}░"; done
  printf "%s" "$bar"
}

bar_color() {
  local pct=$1
  if awk "BEGIN {exit !($pct >= 85)}"; then
    printf "%s" "$RED"
  elif awk "BEGIN {exit !($pct >= 60)}"; then
    printf "%s" "$YELLOW"
  else
    printf "%s" "$BRIGHT_GREEN"
  fi
}

# ── Line 1: [model] - dir: folder (session) - branch ─────────────────────────
line1="${BLUE}[${model}]${RESET} - ${PINK}dir: ${dir}${RESET}"
if [ -n "$session_name" ]; then
  line1="${line1} ${DIM}(${session_name})${RESET}"
fi
if [ -n "$branch" ]; then
  line1="${line1} - ${OLIVE}branch: ${branch}${RESET}"
fi
if [ -n "$vim_mode" ]; then
  line1="${line1} - ${CYAN}[${vim_mode}]${RESET}"
fi

# ── Line 2: 5h-limit bar | ctx remaining | cost | session timer ──────────────
pad=$(printf '%*s' "$(( ${#model} + 3 ))" '')

# 5h rate-limit bar
rl_color=$(bar_color "$limit_pct")
rl_bar=$(make_bar "$limit_pct" 10)
printf -v limit_part "${rl_color}%s${RESET} %.0f%%" "$rl_bar" "$limit_pct"
if [ -n "$reset_time_str" ]; then
  limit_part="${limit_part}${DIM} resets ${reset_time_str}${RESET}"
fi

# Context window remaining (shown only after first API call)
ctx_str=""
if [ -n "$ctx_remaining" ]; then
  ctx_color=$(bar_color "$(awk "BEGIN {printf \"%.0f\", 100 - $ctx_remaining}")")
  ctx_bar=$(make_bar "$(awk "BEGIN {printf \"%.0f\", 100 - $ctx_remaining}")" 8)
  ctx_str=" | ctx: ${ctx_color}${ctx_bar}${RESET} ${ctx_remaining}% left"
fi

printf -v colored_cost "${GREEN}%s${RESET}" "$cost"
line2="${pad}${limit_part}${ctx_str} | ${colored_cost}"

if [ -n "$duration_str" ]; then
  line2="${line2} | ${DIM}${duration_str}${RESET}"
fi

printf "%s\n%s" "$line1" "$line2"
