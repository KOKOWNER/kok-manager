#!/bin/bash
# KOK SSH MANAGER - enforces per-account multi-login limits.
# Runs every minute by cron. Counts a user's sshd processes and
# closes the newest connections above the account's limit.
CONF_DIR="/etc/kok-manager"
DB="$CONF_DIR/users.db"
LOG_FILE="/var/log/kok-manager.log"
[ -f "$DB" ] || exit 0
while IFS='|' read -r u _p _c _e lim _t; do
    [ -z "$u" ] && continue
    [ -z "$lim" ] && continue
    [ "$lim" = "0" ] && continue
    id "$u" >/dev/null 2>&1 || continue
    pids="$(pgrep -u "$u" -x sshd 2>/dev/null | sort -n)"
    [ -z "$pids" ] && continue
    count="$(printf '%s\n' "$pids" | grep -c .)"
    if [ "$count" -gt "$lim" ]; then
        extra=$((count - lim))
        printf '%s\n' "$pids" | tail -n "$extra" | while read -r pid; do
            kill "$pid" 2>/dev/null
        done
        echo "[$(date '+%F %T')] LIMIT-KILL user=$u sessions=$count limit=$lim killed=$extra" >> "$LOG_FILE" 2>/dev/null
    fi
done < "$DB"
exit 0
