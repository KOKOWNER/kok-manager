#!/bin/bash
# ============================================================
#  KOK SSH MANAGER  -  main menu program
#  Clean-room original code, written for KOK.
#  Installed as: /usr/local/kok-manager/kok-menu.sh
#  Run with: menu
# ============================================================

BASE_DIR="/usr/local/kok-manager"
CONF_DIR="/etc/kok-manager"
DB="$CONF_DIR/users.db"
KEYS_FILE="$CONF_DIR/keys.txt"
ACT_FILE="$CONF_DIR/.activated"
LOG_FILE="/var/log/kok-manager.log"

# ---------- colours ----------
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'
C='\033[1;36m'; W='\033[1;37m'; N='\033[0m'

mkdir -p "$CONF_DIR"
touch "$DB" 2>/dev/null
chmod 600 "$DB" 2>/dev/null

log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE" 2>/dev/null; }

# ---------- activation ----------
key_hash() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }

valid_key() {
    local k="$1" line
    [ -f "$KEYS_FILE" ] || return 1
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | tr -d ' \r')"
        [ -z "$line" ] && continue
        case "$line" in \#*) continue;; esac
        [ "$line" = "$k" ] && return 0
    done < "$KEYS_FILE"
    return 1
}

check_activation() {
    if [ -f "$ACT_FILE" ]; then
        local saved; saved="$(cat "$ACT_FILE" 2>/dev/null)"
        local line
        if [ -f "$KEYS_FILE" ]; then
            while IFS= read -r line; do
                line="$(printf '%s' "$line" | tr -d ' \r')"
                [ -z "$line" ] && continue
                case "$line" in \#*) continue;; esac
                [ "$(key_hash "$line")" = "$saved" ] && return 0
            done < "$KEYS_FILE"
        fi
    fi
    echo -e "${Y}This server is not activated yet.${N}"
    read -rp "Enter your KOK Serial Key: " k
    k="$(printf '%s' "$k" | tr -d ' ')"
    if valid_key "$k"; then
        key_hash "$k" > "$ACT_FILE"; chmod 600 "$ACT_FILE"
        echo -e "${G}Activated successfully. Thank you!${N}"
        sleep 1
    else
        echo -e "${R}Invalid serial key. Ask KOK for a valid key.${N}"
        exit 1
    fi
}

# ---------- helpers ----------
rand_str() { tr -dc 'a-z0-9' </dev/urandom | head -c "$1"; }
rand_pass() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }

valid_username() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]; }

db_get() { grep -F "$1|" "$DB" 2>/dev/null | head -1; }

db_remove() {
    grep -vF "$1|" "$DB" > "$DB.tmp" 2>/dev/null || true
    mv "$DB.tmp" "$DB"; chmod 600 "$DB"
}

db_add() { echo "$1|$2|$3|$4|$5|$6" >> "$DB"; chmod 600 "$DB"; }

days_left() {
    local now exp d
    now=$(date +%s); exp="$1"
    d=$(( (exp - now) / 86400 ))
    if [ $(( (exp - now) % 86400 )) -gt 0 ] && [ "$exp" -gt "$now" ]; then d=$((d+1)); fi
    echo "$d"
}

acct_status() {
    local u="$1" exp="$2" st
    if ! id "$u" >/dev/null 2>&1; then echo "MISSING"; return; fi
    if [ "$(date +%s)" -ge "$exp" ]; then echo "EXPIRED"; return; fi
    st="$(passwd -S "$u" 2>/dev/null | awk '{print $2}')"
    if [ "$st" = "L" ]; then echo "LOCKED"; else echo "ACTIVE"; fi
}

pub_ip() {
    local ip
    ip="$(curl -s --max-time 4 https://ifconfig.me 2>/dev/null)"
    if [ -z "$ip" ]; then ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi
    echo "${ip:-unknown}"
}

ssh_port() {
    local p
    p="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | head -1)"
    [ -z "$p" ] && p="$(grep -E '^[[:space:]]*Port[[:space:]]' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)"
    echo "${p:-22}"
}

ssh_service() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then echo "sshd";
    elif systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then echo "ssh";
    elif [ -f /etc/init.d/sshd ]; then echo "sshd"; else echo "ssh"; fi
}

managed_users() { cut -d'|' -f1 "$DB" 2>/dev/null | grep -v '^$'; }

online_users() {
    local mu; mu="$(managed_users | sort -u)"
    [ -z "$mu" ] && return
    who 2>/dev/null | awk '{print $1}' | sort -u | while read -r wu; do
        if printf '%s\n' "$mu" | grep -qx "$wu"; then echo "$wu"; fi
    done
}

press_enter() { echo; read -rp "Press ENTER to return to menu..." _; }

show_account_info() {
    echo -e "${C}----------------------------------------${N}"
    echo -e "${W}        SSH ACCOUNT DETAILS${N}"
    echo -e "${C}----------------------------------------${N}"
    echo -e " Host/IP   : ${G}$(pub_ip)${N}"
    echo -e " Port      : ${G}$(ssh_port)${N}"
    echo -e " Username  : ${G}$1${N}"
    echo -e " Password  : ${G}$2${N}"
    echo -e " Expires   : ${G}$(date -d "@$3" '+%Y-%m-%d %H:%M')${N}"
    echo -e " Days left : ${G}$(days_left "$3")${N}"
    echo -e " Limit     : ${G}$([ "$4" = "0" ] && echo 'Unlimited logins' || echo "$4 login(s)")${N}"
    echo -e "${C}----------------------------------------${N}"
}

header() {
    clear
    local total expired online osname ram disk up
    total=$(managed_users | wc -l)
    expired=0
    while IFS='|' read -r u _p _c e _l _t; do
        [ -z "$u" ] && continue
        [ "$(date +%s)" -ge "$e" ] 2>/dev/null && expired=$((expired+1))
    done < "$DB"
    online=$(online_users | wc -l)
    osname="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    ram="$(free -m 2>/dev/null | awk '/Mem:/{printf "%sMB / %sMB", $3, $2}')"
    disk="$(df -h / 2>/dev/null | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')"
    up="$(uptime -p 2>/dev/null | sed 's/^up //')"
    echo -e "${C}============================================================${N}"
    echo -e "${Y}              K O K   S S H   M A N A G E R${N}"
    echo -e "${C}============================================================${N}"
    echo -e " Server IP : ${G}$(pub_ip)${N}      SSH Port : ${G}$(ssh_port)${N}"
    echo -e " OS        : ${W}${osname}${N}"
    echo -e " Uptime    : ${W}${up}${N}"
    echo -e " RAM       : ${W}${ram}${N}"
    echo -e " Disk      : ${W}${disk}${N}"
    echo -e "${C}------------------------------------------------------------${N}"
    echo -e " Accounts  : ${G}${total}${N}    Online : ${G}${online}${N}    Expired : ${R}${expired}${N}"
    echo -e "${C}============================================================${N}"
}

# ---------- account actions ----------
create_account() {
    echo -e "${Y}--- CREATE SSH ACCOUNT ---${N}"
    read -rp "Username: " u
    if ! valid_username "$u"; then echo -e "${R}Invalid username (3-32 chars, start with a-z or _, then a-z 0-9 _ -).${N}"; press_enter; return; fi
    if id "$u" >/dev/null 2>&1; then echo -e "${R}User '$u' already exists.${N}"; press_enter; return; fi
    read -rp "Password (ENTER = auto-generate): " p
    [ -z "$p" ] && p="$(rand_pass 10)"
    read -rp "Validity days [30]: " d; d="${d:-30}"
    [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -gt 0 ] || { echo -e "${R}Invalid days.${N}"; press_enter; return; }
    read -rp "Multi-login limit (0 = unlimited) [1]: " lim; lim="${lim:-1}"
    [[ "$lim" =~ ^[0-9]+$ ]] || { echo -e "${R}Invalid limit.${N}"; press_enter; return; }

    local now exp expdate
    now=$(date +%s); exp=$(( now + d*86400 )); expdate="$(date -d "@$exp" '+%Y-%m-%d')"
    useradd -M -s /bin/false "$u" || { echo -e "${R}useradd failed.${N}"; press_enter; return; }
    echo "$u:$p" | chpasswd
    chage -E "$expdate" -m 0 -M 99999 -I -1 "$u"
    db_add "$u" "$p" "$now" "$exp" "$lim" "premium"
    log "CREATE user=$u days=$d limit=$lim"
    echo -e "${G}Account created successfully.${N}"
    show_account_info "$u" "$p" "$exp" "$lim"
    press_enter
}

trial_account() {
    echo -e "${Y}--- CREATE TRIAL ACCOUNT ---${N}"
    read -rp "Validity hours [3]: " h; h="${h:-3}"
    [[ "$h" =~ ^[0-9]+$ ]] && [ "$h" -gt 0 ] || { echo -e "${R}Invalid hours.${N}"; press_enter; return; }
    local u p now exp expdate
    u="trial$(rand_str 5)"; p="$(rand_pass 8)"
    now=$(date +%s); exp=$(( now + h*3600 )); expdate="$(date -d "@$((exp + 86400))" '+%Y-%m-%d')"
    useradd -M -s /bin/false "$u" || { echo -e "${R}useradd failed.${N}"; press_enter; return; }
    echo "$u:$p" | chpasswd
    chage -E "$expdate" -m 0 -M 99999 -I -1 "$u"
    db_add "$u" "$p" "$now" "$exp" "1" "trial"
    log "TRIAL user=$u hours=$h"
    echo -e "${G}Trial account created. It is removed automatically when it expires.${N}"
    show_account_info "$u" "$p" "$exp" "1"
    press_enter
}

pick_user() {
    # prints chosen username to stdout (prompts on stderr); empty when cancelled
    local sel i u
    local users=()
    while IFS= read -r line; do [ -n "$line" ] && users+=("$line"); done < <(managed_users)
    if [ "${#users[@]}" -eq 0 ]; then echo -e "${R}No managed accounts yet.${N}" >&2; echo ""; return; fi
    echo -e "${Y}Managed accounts:${N}" >&2
    i=1
    for u in "${users[@]}"; do echo "  [$i] $u" >&2; i=$((i+1)); done
    read -rp "Choose number (or type username): " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#users[@]}" ]; then
        echo "${users[$((sel-1))]}"
    elif [ -n "$(db_get "$sel")" ]; then
        echo "$sel"
    else
        echo ""
    fi
}

renew_account() {
    echo -e "${Y}--- RENEW ACCOUNT ---${N}"
    local u row exp d now newexp
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    row="$(db_get "$u")"; exp="$(echo "$row" | cut -d'|' -f4)"
    read -rp "Add how many days? [30]: " d; d="${d:-30}"
    [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -gt 0 ] || { echo -e "${R}Invalid days.${N}"; press_enter; return; }
    now=$(date +%s)
    if [ "$exp" -gt "$now" ]; then newexp=$(( exp + d*86400 )); else newexp=$(( now + d*86400 )); fi
    chage -E "$(date -d "@$newexp" '+%Y-%m-%d')" "$u"
    local p c l t
    p="$(echo "$row" | cut -d'|' -f2)"; c="$(echo "$row" | cut -d'|' -f3)"
    l="$(echo "$row" | cut -d'|' -f5)"; t="$(echo "$row" | cut -d'|' -f6)"
    db_remove "$u"; db_add "$u" "$p" "$c" "$newexp" "$l" "$t"
    log "RENEW user=$u add_days=$d new_expiry=$newexp"
    echo -e "${G}'$u' renewed. New expiry: $(date -d "@$newexp" '+%Y-%m-%d') (${d} days added).${N}"
    press_enter
}

delete_account() {
    echo -e "${Y}--- DELETE ACCOUNT ---${N}"
    local u ans
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    read -rp "Really delete '$u'? [y/N]: " ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        pkill -u "$u" 2>/dev/null
        userdel -r "$u" 2>/dev/null || userdel "$u" 2>/dev/null
        db_remove "$u"
        log "DELETE user=$u"
        echo -e "${G}'$u' deleted.${N}"
    else
        echo "Cancelled."
    fi
    press_enter
}

list_accounts() {
    echo -e "${Y}--- ACCOUNT LIST ---${N}"
    printf "%-4s %-18s %-12s %-8s %-6s %-9s %s\n" "No" "Username" "Password" "Left" "Limit" "Status" "Type"
    echo "---------------------------------------------------------------------"
    local i=0
    while IFS='|' read -r u p _c e l t; do
        [ -z "$u" ] && continue
        i=$((i+1))
        printf "%-4s %-18s %-12s %-8s %-6s %-9s %s\n" "$i" "$u" "$p" "$(days_left "$e")d" "$l" "$(acct_status "$u" "$e")" "$t"
    done < "$DB"
    [ "$i" -eq 0 ] && echo "(no accounts)"
    press_enter
}

lock_account() {
    echo -e "${Y}--- LOCK / UNLOCK ACCOUNT ---${N}"
    local u st
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    st="$(passwd -S "$u" 2>/dev/null | awk '{print $2}')"
    if [ "$st" = "L" ]; then
        usermod -U "$u" && echo -e "${G}'$u' unlocked.${N}"; log "UNLOCK user=$u"
    else
        pkill -u "$u" 2>/dev/null
        usermod -L "$u" && echo -e "${G}'$u' locked.${N}"; log "LOCK user=$u"
    fi
    press_enter
}

change_password() {
    echo -e "${Y}--- CHANGE PASSWORD ---${N}"
    local u row p c e l t
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    read -rp "New password (ENTER = auto-generate): " p
    [ -z "$p" ] && p="$(rand_pass 10)"
    echo "$u:$p" | chpasswd || { echo -e "${R}Failed.${N}"; press_enter; return; }
    row="$(db_get "$u")"
    c="$(echo "$row" | cut -d'|' -f3)"; e="$(echo "$row" | cut -d'|' -f4)"
    l="$(echo "$row" | cut -d'|' -f5)"; t="$(echo "$row" | cut -d'|' -f6)"
    db_remove "$u"; db_add "$u" "$p" "$c" "$e" "$l" "$t"
    log "PASSWD user=$u"
    echo -e "${G}Password for '$u' is now: ${W}$p${N}"
    press_enter
}

online_menu() {
    echo -e "${Y}--- ONLINE USERS ---${N}"
    local list count
    list="$(online_users)"; count="$(printf '%s' "$list" | grep -c . )"
    if [ -z "$list" ]; then echo "No managed user is online right now."; else
        echo "$list" | while read -r ou; do
            echo -e " ${G}●${N} $ou  ($(who | awk -v x="$ou" '$1==x' | wc -l) session(s))"
        done
    fi
    echo
    read -rp "Kick a user off? Type username (ENTER = back): " ku
    if [ -n "$ku" ] && [ -n "$(db_get "$ku")" ]; then
        pkill -u "$ku" && echo -e "${G}Sessions of '$ku' closed.${N}"; log "KICK user=$ku"
    fi
    press_enter
}

server_info() {
    echo -e "${Y}--- SERVER INFO ---${N}"
    echo " Hostname : $(hostname)"
    echo " Public IP: $(pub_ip)"
    echo " OS       : $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo " Kernel   : $(uname -r)"
    echo " CPU      : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //') ($(nproc) core(s))"
    echo " RAM      : $(free -h | awk '/Mem:/{print $3" / "$2}')"
    echo " Disk /   : $(df -h / | awk 'NR==2{print $3" / "$2" ("$5" used)"}')"
    echo " SSH port : $(ssh_port)   Service: $(ssh_service)"
    echo " Accounts : $(managed_users | wc -l) managed"
    press_enter
}

restart_ssh() {
    local svc; svc="$(ssh_service)"
    if systemctl restart "$svc" 2>/dev/null || service "$svc" restart 2>/dev/null; then
        echo -e "${G}SSH service ($svc) restarted.${N}"
    else
        echo -e "${R}Restart failed for service '$svc'.${N}"
    fi
    log "RESTART_SSH service=$svc"
    press_enter
}

speed_test() {
    echo -e "${Y}--- SPEED TEST ---${N}"
    echo "Ping 1.1.1.1:"
    ping -c 4 -q 1.1.1.1 2>/dev/null | tail -2
    echo "Download test (25 MB from Cloudflare):"
    local sp
    sp="$(curl -s -o /dev/null -w '%{speed_download}' --max-time 30 'https://speed.cloudflare.com/__down?bytes=25000000' 2>/dev/null)"
    if [ -n "$sp" ] && [ "$sp" != "0" ]; then
        awk -v b="$sp" 'BEGIN{printf " ~ %.2f Mbps (%.2f MB/s)\n", b*8/1000000, b/1048576}'
    else
        echo " Download test failed (network?)."
    fi
    press_enter
}

backup_accounts() {
    local f="/root/kok-manager-backup-$(date '+%Y%m%d-%H%M').tar.gz"
    tar -czf "$f" -C / etc/kok-manager/users.db etc/kok-manager/keys.txt 2>/dev/null \
        && echo -e "${G}Backup saved: $f${N}" || echo -e "${R}Backup failed.${N}"
    log "BACKUP file=$f"
    press_enter
}

restore_accounts() {
    read -rp "Backup file path: " f
    if [ ! -f "$f" ]; then echo -e "${R}File not found.${N}"; press_enter; return; fi
    local tmp; tmp="$(mktemp -d)"
    tar -xzf "$f" -C "$tmp" 2>/dev/null || { echo -e "${R}Cannot read backup.${N}"; rm -rf "$tmp"; press_enter; return; }
    local rdb="$tmp/etc/kok-manager/users.db"
    [ -f "$rdb" ] || { echo -e "${R}No users.db in backup.${N}"; rm -rf "$tmp"; press_enter; return; }
    local restored=0 skipped=0
    while IFS='|' read -r u p _c e l _t; do
        [ -z "$u" ] && continue
        if id "$u" >/dev/null 2>&1; then skipped=$((skipped+1)); continue; fi
        useradd -M -s /bin/false "$u" 2>/dev/null || { skipped=$((skipped+1)); continue; }
        echo "$u:$p" | chpasswd
        chage -E "$(date -d "@$e" '+%Y-%m-%d')" -m 0 -M 99999 -I -1 "$u"
        grep -F "$u|" "$rdb" >> "$DB"
        restored=$((restored+1))
    done < "$rdb"
    chmod 600 "$DB"
    rm -rf "$tmp"
    log "RESTORE file=$f restored=$restored skipped=$skipped"
    echo -e "${G}Restore done: $restored account(s) restored, $skipped skipped (already exist).${N}"
    press_enter
}

reboot_server() {
    read -rp "Reboot the server now? [y/N]: " ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then echo "Rebooting..."; sleep 1; reboot; fi
    press_enter
}

uninstall() {
    echo -e "${R}--- UNINSTALL KOK SSH MANAGER ---${N}"
    read -rp "Remove the manager? [y/N]: " ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; press_enter; return; }
    read -rp "Also DELETE all managed SSH accounts? [y/N]: " ans2
    if [ "$ans2" = "y" ] || [ "$ans2" = "Y" ]; then
        managed_users | while read -r u; do pkill -u "$u" 2>/dev/null; userdel -r "$u" 2>/dev/null || userdel "$u" 2>/dev/null; done
    fi
    rm -f /etc/cron.d/kok-manager /usr/local/bin/menu /usr/local/bin/kok-genkey
    rm -rf "$BASE_DIR" "$CONF_DIR"
    echo -e "${G}KOK SSH Manager removed. Goodbye!${N}"
    exit 0
}

# ---------- main ----------
[ "$(id -u)" = "0" ] || { echo -e "${R}Please run as root (sudo menu).${N}"; exit 1; }
check_activation

while true; do
    header
    echo -e " ${W}[1]${N}  Create SSH Account"
    echo -e " ${W}[2]${N}  Trial Account"
    echo -e " ${W}[3]${N}  Renew Account"
    echo -e " ${W}[4]${N}  Delete Account"
    echo -e " ${W}[5]${N}  List Accounts"
    echo -e " ${W}[6]${N}  Lock / Unlock Account"
    echo -e " ${W}[7]${N}  Change Password"
    echo -e " ${W}[8]${N}  Online Users"
    echo -e " ${W}[9]${N}  Server Info"
    echo -e " ${W}[10]${N} Restart SSH Service"
    echo -e " ${W}[11]${N} Speed Test"
    echo -e " ${W}[12]${N} Backup Accounts"
    echo -e " ${W}[13]${N} Restore Accounts"
    echo -e " ${W}[14]${N} Reboot Server"
    echo -e " ${W}[15]${N} Uninstall Manager"
    echo -e " ${W}[0]${N}  Exit"
    echo -e "${C}------------------------------------------------------------${N}"
    read -rp " Choose: " choice
    case "$choice" in
        1) create_account ;;
        2) trial_account ;;
        3) renew_account ;;
        4) delete_account ;;
        5) list_accounts ;;
        6) lock_account ;;
        7) change_password ;;
        8) online_menu ;;
        9) server_info ;;
        10) restart_ssh ;;
        11) speed_test ;;
        12) backup_accounts ;;
        13) restore_accounts ;;
        14) reboot_server ;;
        15) uninstall ;;
        0) echo "Bye!"; exit 0 ;;
        *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
    esac
done
