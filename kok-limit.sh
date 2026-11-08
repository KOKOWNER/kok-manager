#!/bin/bash
# KOK SSH MANAGER - monitoring / enforcement daemon (cron, every minute).
#  1) Multi-login limit: closes the newest sshd sessions above the limit.
#  2) Bandwidth quota: an iptables owner-match counter rule per account
#     measures the traffic of the account's processes (SSH sessions and
#     the connections they forward). When the GB quota in users.db field 7
#     is used up, the account is locked and its sessions are closed.
#     Raising the quota (or setting 0 = unlimited) unlocks it again.
CONF_DIR="/etc/kok-manager"
DB="$CONF_DIR/users.db"
LOG_FILE="/var/log/kok-manager.log"
BW_STATE="$CONF_DIR/bw.state"
BW_LOCKED="$CONF_DIR/bw.locked"
[ -f "$DB" ] || exit 0
touch "$BW_STATE" "$BW_LOCKED" 2>/dev/null
newstate="$(mktemp)"
while IFS='|' read -r u _p _c _e lim _t bw; do
    [ -z "$u" ] && continue
    id "$u" >/dev/null 2>&1 || continue
    bw="${bw:-0}"

    # ---- 1) multi-login limit ----
    if [ -n "$lim" ] && [ "$lim" != "0" ]; then
        pids="$(pgrep -u "$u" -x sshd 2>/dev/null | sort -n)"
        if [ -n "$pids" ]; then
            count="$(printf '%s\n' "$pids" | grep -c .)"
            if [ "$count" -gt "$lim" ]; then
                extra=$((count - lim))
                printf '%s\n' "$pids" | tail -n "$extra" | while read -r pid; do
                    kill "$pid" 2>/dev/null
                done
                echo "[$(date '+%F %T')] LIMIT-KILL user=$u sessions=$count limit=$lim killed=$extra" >> "$LOG_FILE" 2>/dev/null
            fi
        fi
    fi

    # ---- 2) bandwidth quota ----
    uid="$(id -u "$u")"
    iptables -C OUTPUT -m owner --uid-owner "$uid" -m comment --comment "kokbw:$u" -j ACCEPT 2>/dev/null \
        || iptables -A OUTPUT -m owner --uid-owner "$uid" -m comment --comment "kokbw:$u" -j ACCEPT 2>/dev/null
    cur="$(iptables -L OUTPUT -v -x -n 2>/dev/null | grep -F "kokbw:$u" | head -1 | awk '{print $2}')"
    last="$(awk -F'|' -v u="$u" '$1==u{print $2}' "$BW_STATE" 2>/dev/null | head -1)"
    total="$(awk -F'|' -v u="$u" '$1==u{print $3}' "$BW_STATE" 2>/dev/null | head -1)"
    [ -z "$total" ] && total=0
    if [[ "$cur" =~ ^[0-9]+$ ]]; then
        if [ -z "$last" ]; then
            last="$cur"
        elif [ "$cur" -ge "$last" ]; then
            total=$(( total + cur - last )); last="$cur"
        else
            # counter went backwards (rule or reboot reset): count fresh bytes
            total=$(( total + cur )); last="$cur"
        fi
    else
        [ -z "$last" ] && last=0
    fi
    echo "$u|$last|$total" >> "$newstate"
    if [ "$bw" != "0" ] && [ "$total" -ge $(( bw * 1073741824 )) ]; then
        if ! grep -qx "$u" "$BW_LOCKED" 2>/dev/null; then
            usermod -L "$u" 2>/dev/null
            pkill -u "$u" 2>/dev/null
            echo "$u" >> "$BW_LOCKED"
            echo "[$(date '+%F %T')] BW-LOCK user=$u used_bytes=$total quota=${bw}GB" >> "$LOG_FILE" 2>/dev/null
        fi
    else
        if grep -qx "$u" "$BW_LOCKED" 2>/dev/null; then
            usermod -U "$u" 2>/dev/null
            sed -i "/^$u$/d" "$BW_LOCKED"
            echo "[$(date '+%F %T')] BW-UNLOCK user=$u used_bytes=$total quota=${bw}GB" >> "$LOG_FILE" 2>/dev/null
        fi
    fi
done < "$DB"
mv "$newstate" "$BW_STATE" 2>/dev/null
chmod 600 "$BW_STATE" "$BW_LOCKED" 2>/dev/null
exit 0
