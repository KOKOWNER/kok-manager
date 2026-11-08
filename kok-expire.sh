#!/bin/bash
# KOK SSH MANAGER - removes expired accounts. Run hourly by cron.
CONF_DIR="/etc/kok-manager"
DB="$CONF_DIR/users.db"
LOG_FILE="/var/log/kok-manager.log"
[ -f "$DB" ] || exit 0
now=$(date +%s)
tmp="$(mktemp)"
removed=0
while IFS='|' read -r u _p _c exp _l _t; do
    if [ -z "$u" ]; then continue; fi
    if [ "$exp" -le "$now" ] 2>/dev/null; then
        pkill -u "$u" 2>/dev/null
        userdel -r "$u" 2>/dev/null || userdel "$u" 2>/dev/null
        echo "[$(date '+%F %T')] EXPIRED-REMOVED user=$u" >> "$LOG_FILE" 2>/dev/null
        removed=$((removed+1))
    else
        grep -F "$u|" "$DB" | head -1 >> "$tmp"
    fi
done < "$DB"
mv "$tmp" "$DB"
chmod 600 "$DB"
exit 0
