#!/bin/sh
# Weather for the tmux status bar (see tmux_conf_theme_status_right in
# ~/.tmux.conf.local). Asks wttr.in at most every 30 minutes and prints the
# cached answer in between, so the 10 s status refresh never hits the network.
#
# Location comes from the IP address unless WTTR_LOCATION is set in the tmux
# server environment, e.g. `tmux set-environment -g WTTR_LOCATION Mexico+City`.
# Prints nothing when offline and nothing was cached yet.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/tmux-weather

if [ ! -f "$cache" ] || [ -n "$(find "$cache" -mmin +30 2>/dev/null)" ]; then
  if out=$(curl -sf --max-time 3 "https://wttr.in/${WTTR_LOCATION:-}?format=%c+%t" 2>/dev/null) \
     && [ -n "$out" ]; then
    printf '%s\n' "$out" | tr -s ' ' > "$cache"
  else
    # Offline or wttr.in is down: keep the old value and retry in 30 minutes.
    touch "$cache" 2>/dev/null
  fi
fi

cat "$cache" 2>/dev/null
