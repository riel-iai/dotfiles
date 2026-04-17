#!/usr/bin/env bash
input=$(cat)

# ANSI colors ($'...' syntax so escapes work in both printf and string assignment)
GREEN=$'\033[0;32m'
BRIGHT_GREEN=$'\033[38;2;250;189;47m'   # #fabd2f — gruvbox bryellow (waybar date color)
YELLOW=$'\033[38;5;220m'
RED=$'\033[38;5;196m'
BLUE=$'\033[0;34m'
PINK=$'\033[38;5;175m'
MUSTARD=$'\033[38;2;250;189;47m'
OLIVE=$'\033[38;5;142m'
CYAN=$'\033[0;36m'
RESET_RED=$'\033[38;2;204;36;29m'   # #cc241d
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

# 7-day rate limit
week_pct=$(echo "$input"       | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset_epoch=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
week_reset_str=""
if [ -n "$week_reset_epoch" ] && [ "$week_reset_epoch" -gt 0 ] 2>/dev/null; then
  week_reset_str=$(date -d "@${week_reset_epoch}" +"%b%-d" 2>/dev/null || date -r "${week_reset_epoch}" +"%b%-d" 2>/dev/null)
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

# Git branch for the current working directory (fallback to -- when not in a repo)
branch="--"
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$git_branch" ] && branch="$git_branch"
fi

# Progress bar with percentage text embedded at center
# Usage: make_bar <pct> <width> <fill_color> <empty_color>
BOLD_WHITE=$'\033[1;37m'
make_bar() {
  local pct=$1
  local width=${2:-10}
  local fill_color=${3:-""}
  local empty_color=${4:-""}
  local filled=$(echo "$pct $width" | awk '{printf "%d", ($1/100)*$2 + 0.5}')
  local pct_str=$(printf "%.0f%%" "$pct")
  local pct_len=${#pct_str}
  local center_start=$(( (width - pct_len) / 2 ))
  local center_end=$(( center_start + pct_len ))
  local bar=""
  local i
  for (( i=0; i<width; i++ )); do
    if (( i == center_start )); then
      local after_color
      if (( center_end <= filled )); then
        after_color="$fill_color"
      else
        after_color="$empty_color"
      fi
      bar="${bar}${BOLD_WHITE}${pct_str}${RESET}${after_color}"
      i=$(( center_end - 1 ))
    elif (( i < filled )); then
      bar="${bar}█"
    else
      bar="${bar}░"
    fi
  done
  printf "%s" "$bar"
}

# bar_color: used for the context/token bar — low end is mustard (#fabd2f)
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

# rl_bar_color: used for the 5h rate-limit bar — low end stays original green
rl_bar_color() {
  local pct=$1
  if awk "BEGIN {exit !($pct >= 85)}"; then
    printf "%s" "$RED"
  elif awk "BEGIN {exit !($pct >= 60)}"; then
    printf "%s" "$YELLOW"
  else
    printf "%s" "$GREEN"
  fi
}

# ── Line 1: [model] - dir: folder (session) - branch ─────────────────────────
line1="${BLUE}[${model}]${RESET} - ${PINK}dir: ${dir}${RESET}"
if [ -n "$session_name" ]; then
  line1="${line1} ${DIM}(${session_name})${RESET}"
fi
line1="${line1} - ${OLIVE}branch: ${branch}${RESET}"
if [ -n "$duration_str" ]; then
  line1="${line1} - ${MUSTARD}dur: ${duration_str}${RESET}"
fi
if [ -n "$vim_mode" ]; then
  line1="${line1} - ${CYAN}[${vim_mode}]${RESET}"
fi

# ── Line 2: 5h-limit bar | ctx remaining | cost | session timer ──────────────
pad=$(printf '%*s' "$(( ${#model} + 3 ))" '')

# 5h rate-limit bar
rl_color=$(rl_bar_color "$limit_pct")
rl_bar=$(make_bar "$limit_pct" 10 "$rl_color" "$rl_color")
printf -v limit_part "${rl_color}5h:${RESET} ${rl_color}%s${RESET}" "$rl_bar"
if [ -n "$reset_time_str" ]; then
  limit_part="${limit_part} ${RESET_RED}(${reset_time_str})${RESET}"
fi

# 7-day rate-limit bar (pink)
if [ -n "$week_pct" ]; then
  week_bar=$(make_bar "$week_pct" 10 "$PINK" "$PINK")
  week_part=" - ${PINK}7d:${RESET} ${PINK}${week_bar}${RESET}"
  if [ -n "$week_reset_str" ]; then
    week_part="${week_part} ${PINK}(${week_reset_str})${RESET}"
  fi
else
  week_part=""
fi

# Context window used — always shown; displays "--" when no API call has been made yet
if [ -n "$ctx_used" ]; then
  ctx_color=$(bar_color "$ctx_used")
  ctx_bar=$(make_bar "$ctx_used" 8 "$ctx_color" "$ctx_color")
  ctx_str=" - ${BRIGHT_GREEN}context:${RESET} ${ctx_color}${ctx_bar}${RESET}"
else
  ctx_str=" - ${BRIGHT_GREEN}context:${RESET} ${BRIGHT_GREEN}--${RESET}"
fi

line2="${pad}${limit_part}${week_part}${ctx_str}"

printf "%s\n%s" "$line1" "$line2"
