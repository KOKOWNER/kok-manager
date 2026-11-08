#!/bin/bash
# ============================================================
#  KOK SSH MANAGER v3  -  main menu program
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
BANNER_FILE="$CONF_DIR/banner.txt"

# ---------- colours ----------
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'
M='\033[1;35m'; C='\033[1;36m'; W='\033[1;37m'; N='\033[0m'

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

db_update() { # user pass created expiry limit type
    db_remove "$1"; db_add "$1" "$2" "$3" "$4" "$5" "$6"
}

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

# ---------- banner / header ----------
glyph() {
    case "$1" in
        K) echo "#  #|# # |##  |# # |#  #" ;;
        O) echo " ## |#  #|#  #|#  #| ## " ;;
        M) echo "#   #|## ##|# # #|#   #|#   #" ;;
        A) echo " ## |#  #|####|#  #|#  #" ;;
        N) echo "#  #|## #|# ##|#  #|#  #" ;;
        G) echo " ###|#   |# ##|#  #| ###" ;;
        E) echo "####|#   |### |#   |####" ;;
        R) echo "### |#  #|### |# # |#  #" ;;
        *) echo "    |    |    |    |    " ;;
    esac
}

banner_text() {
    local word="$1" rows=("" "" "" "" "") i ch g r
    for (( i=0; i<${#word}; i++ )); do
        ch="${word:i:1}"
        g="$(glyph "$ch")"
        for r in 0 1 2 3 4; do
            rows[$r]+="$(echo "$g" | cut -d'|' -f$((r+1))) "
        done
    done
    for r in 0 1 2 3 4; do echo -e "${M}      ${rows[$r]}${N}"; done
}

header() {
    clear
    local osname up mem users sessions load
    osname="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    up="$(uptime -p 2>/dev/null | sed 's/^up //')"
    mem="$(free -m 2>/dev/null | awk '/Mem:/{printf "%.2f%% Used", $3/$2*100}')"
    users="$(managed_users | wc -l)"
    sessions="$(who 2>/dev/null | wc -l)"
    load="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
    echo -e "${C}----------------------------------------------------------------------${N}"
    banner_text "KOK"
    banner_text "MANAGER"
    echo -e "${C}----------------------------------------------------------------------${N}"
    echo -e "              ${C}PREMIUM SSH & VPN SERVICES${N}"
    echo -e "              ${Y}Developed by: KOK ${N}<🇲🇲/>"
    echo -e " ${Y}System License Expiry : ${G}Lifetime (Verified)${N}"
    echo -e "${C}----------------------------------------------------------------------${N}"
    echo -e "${B}======================================================================${N}"
    printf " ${W}%-10s${N} ${G}%-28s${N} ${W}|${N} ${W}%-17s${N} ${G}%s${N}\n" "OS" "$osname" "Uptime:" "$up"
    printf " ${W}%-10s${N} ${G}%-28s${N} ${W}|${N} ${W}%-17s${N} ${G}%s${N}\n" "Memory" "$mem" "Online Sessions:" "$sessions"
    printf " ${W}%-10s${N} ${G}%-28s${N} ${W}|${N} ${W}%-17s${N} ${G}%s${N}\n" "Users" "$users Managed Accounts" "Sys Load (1m):" "$load"
    echo -e "${B}======================================================================${N}"
}

section() { echo -e "${M}═══════════════[ $1 ]═══════════════${N}"; }

# ---------- account actions ----------
create_account() {
    echo -e "${Y}--- CREATE NEW USER ---${N}"
    echo "  [1] Normal account (days)"
    echo "  [2] Trial account (hours)"
    read -rp " Choose [1]: " at; at="${at:-1}"
    if [ "$at" = "2" ]; then trial_account; return; fi
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
    echo -e "${Y}--- RENEW USER ACCOUNT ---${N}"
    local u row exp d now newexp p c l t
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    row="$(db_get "$u")"; exp="$(echo "$row" | cut -d'|' -f4)"
    read -rp "Add how many days? [30]: " d; d="${d:-30}"
    [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -gt 0 ] || { echo -e "${R}Invalid days.${N}"; press_enter; return; }
    now=$(date +%s)
    if [ "$exp" -gt "$now" ]; then newexp=$(( exp + d*86400 )); else newexp=$(( now + d*86400 )); fi
    chage -E "$(date -d "@$newexp" '+%Y-%m-%d')" "$u"
    p="$(echo "$row" | cut -d'|' -f2)"; c="$(echo "$row" | cut -d'|' -f3)"
    l="$(echo "$row" | cut -d'|' -f5)"; t="$(echo "$row" | cut -d'|' -f6)"
    db_update "$u" "$p" "$c" "$newexp" "$l" "$t"
    log "RENEW user=$u add_days=$d new_expiry=$newexp"
    echo -e "${G}'$u' renewed. New expiry: $(date -d "@$newexp" '+%Y-%m-%d') (${d} days added).${N}"
    press_enter
}

delete_account() {
    echo -e "${Y}--- DELETE USER ---${N}"
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
    echo -e "${Y}--- LIST MANAGED USERS ---${N}"
    printf "%-4s %-18s %-12s %-8s %-6s %-9s %s\n" "No" "Username" "Password" "Left" "Limit" "Status" "Type"
    echo "---------------------------------------------------------------------"
    local i=0
    while IFS='|' read -r u p _c e l t; do
        [ -z "$u" ] && continue
        i=$((i+1))
        printf "%-4s %-18s %-12s %-8s %-6s %-9s %s\n" "$i" "$u" "$p" "$(days_left "$e")d" "$l" "$(acct_status "$u" "$e")" "$t"
    done < "$DB"
    [ "$i" -eq 0 ] && echo "(no accounts)"
    local list count
    list="$(online_users)"; count="$(printf '%s' "$list" | grep -c . )"
    if [ -n "$list" ]; then
        echo -e "${Y}Online now:${N}"
        echo "$list" | while read -r ou; do echo -e " ${G}●${N} $ou"; done
        read -rp "Kick a user off? Type username (ENTER = back): " ku
        if [ -n "$ku" ] && [ -n "$(db_get "$ku")" ]; then
            pkill -u "$ku" && echo -e "${G}Sessions of '$ku' closed.${N}"; log "KICK user=$ku"
        fi
    fi
    press_enter
}

lock_unlock() { # $1 = lock | unlock
    local mode="$1" u st
    echo -e "${Y}--- ${mode^^} USER ACCOUNT ---${N}"
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    st="$(passwd -S "$u" 2>/dev/null | awk '{print $2}')"
    if [ "$mode" = "lock" ]; then
        if [ "$st" = "L" ]; then echo -e "${Y}'$u' is already locked.${N}"; else
            pkill -u "$u" 2>/dev/null; usermod -L "$u" && echo -e "${G}'$u' locked.${N}"; log "LOCK user=$u"
        fi
    else
        if [ "$st" != "L" ]; then echo -e "${Y}'$u' is not locked.${N}"; else
            usermod -U "$u" && echo -e "${G}'$u' unlocked.${N}"; log "UNLOCK user=$u"
        fi
    fi
    press_enter
}

edit_user() {
    echo -e "${Y}--- EDIT USER DETAILS ---${N}"
    local u row p c e l t
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    row="$(db_get "$u")"
    p="$(echo "$row" | cut -d'|' -f2)"; c="$(echo "$row" | cut -d'|' -f3)"
    e="$(echo "$row" | cut -d'|' -f4)"; l="$(echo "$row" | cut -d'|' -f5)"; t="$(echo "$row" | cut -d'|' -f6)"
    echo -e " User    : ${W}$u${N}"
    echo -e " Password: ${W}$p${N}   Limit: ${W}$l${N}   Expires: ${W}$(date -d "@$e" '+%Y-%m-%d')${N} ($(days_left "$e") days left)"
    echo "  [1] Change password"
    echo "  [2] Set expiry (days from today)"
    echo "  [3] Change multi-login limit"
    echo "  [0] Back"
    read -rp " Choose: " ec
    case "$ec" in
        1)
            read -rp "New password (ENTER = auto-generate): " np
            [ -z "$np" ] && np="$(rand_pass 10)"
            echo "$u:$np" | chpasswd && p="$np" && echo -e "${G}Password changed: ${W}$p${N}"
            ;;
        2)
            read -rp "Valid for how many days from today? " dd
            if [[ "$dd" =~ ^[0-9]+$ ]] && [ "$dd" -gt 0 ]; then
                e=$(( $(date +%s) + dd*86400 ))
                chage -E "$(date -d "@$e" '+%Y-%m-%d')" "$u"
                echo -e "${G}New expiry: $(date -d "@$e" '+%Y-%m-%d')${N}"
            else echo -e "${R}Invalid days.${N}"; fi
            ;;
        3)
            read -rp "New limit (0 = unlimited): " nl
            if [[ "$nl" =~ ^[0-9]+$ ]]; then l="$nl"; echo -e "${G}Limit set to $l.${N}"; else echo -e "${R}Invalid limit.${N}"; fi
            ;;
        *) echo "Back."; press_enter; return ;;
    esac
    db_update "$u" "$p" "$c" "$e" "$l" "$t"
    log "EDIT user=$u"
    press_enter
}

generate_config() {
    echo -e "${Y}--- GENERATE CLIENT CONFIG ---${N}"
    local u row p e l
    u="$(pick_user)"; [ -z "$u" ] && { echo -e "${R}Cancelled / not found.${N}"; press_enter; return; }
    row="$(db_get "$u")"
    p="$(echo "$row" | cut -d'|' -f2)"; e="$(echo "$row" | cut -d'|' -f4)"; l="$(echo "$row" | cut -d'|' -f5)"
    echo -e "${C}============================================================${N}"
    echo -e "${Y}              KOK PREMIUM SSH ACCOUNT${N}"
    echo -e "${C}============================================================${N}"
    echo -e " Host/IP    : ${G}$(pub_ip)${N}"
    echo -e " SSH Port   : ${G}$(ssh_port)${N}"
    echo -e " Username   : ${G}$u${N}"
    echo -e " Password   : ${G}$p${N}"
    echo -e " Expires    : ${G}$(date -d "@$e" '+%Y-%m-%d')${N} ($(days_left "$e") days left)"
    echo -e " Limit      : ${G}$([ "$l" = "0" ] && echo 'Unlimited logins' || echo "$l login(s)")${N}"
    if [ -f "$CONF_DIR/dnstt/domain.txt" ]; then
        echo -e "${C}------------------------------------------------------------${N}"
        echo -e "${W} SlowDNS / DNSTT:${N}"
        echo -e " Nameserver : ${G}$(cat "$CONF_DIR/dnstt/domain.txt")${N}"
        echo -e " Public Key : ${G}$(cat "$CONF_DIR/dnstt/server.pub" 2>/dev/null)${N}"
    fi
    if [ -f "$CONF_DIR/dtproxy/domain.txt" ]; then
        echo -e "${C}------------------------------------------------------------${N}"
        echo -e "${W} DT Proxy (direct): ${G}$(pub_ip) port $(cat "$CONF_DIR/dtproxy/port.txt" 2>/dev/null)${N}"
        echo -e " Domain     : ${G}$(cat "$CONF_DIR/dtproxy/domain.txt")${N}"
        echo -e " Public Key : ${G}$(cat "$CONF_DIR/dtproxy/server.pub" 2>/dev/null)${N}"
    fi
    echo -e "${C}============================================================${N}"
    press_enter
}

# ---------- DNSTT (SlowDNS) ----------
DNSTT_DIR="$CONF_DIR/dnstt"
DNSTT_BIN="/usr/local/bin/dnstt-server"

dnstt_derive_pub() {
    # X25519 public key (hex) for a 64-hex-char private key, via openssl.
    local hex="$1" der pub i
    command -v openssl >/dev/null 2>&1 || return 1
    der="$(mktemp)"
    { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'
      for ((i=0;i<64;i+=2)); do printf "\x${hex:i:2}"; done } > "$der"
    openssl pkey -in "$der" -inform DER -pubout -outform DER -out "$der.pub" 2>/dev/null \
        || { rm -f "$der" "$der.pub"; return 1; }
    pub="$(tail -c 32 "$der.pub" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    rm -f "$der" "$der.pub"
    [[ "$pub" =~ ^[0-9a-f]{64}$ ]] && { echo "$pub"; return 0; }
    return 1
}

dnstt_pub_from_run() {
    # fallback: start the server briefly with a privkey file and read the pubkey it logs
    [ -x "$DNSTT_BIN" ] || return 1
    timeout 2 "$DNSTT_BIN" -udp 127.0.0.1:15399 -privkey-file "$1" probe.invalid 127.0.0.1:22 2>&1 \
        | grep -o 'pubkey [0-9a-f]\{64\}' | awk '{print $2}' | head -1
}

dnstt_install_go() {
    export PATH="$PATH:/usr/local/go/bin"
    command -v go >/dev/null 2>&1 && return 0
    echo "Installing Go (needed once to build dnstt-server)..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq golang-go git >/dev/null 2>&1
    fi
    command -v go >/dev/null 2>&1 && return 0
    local arch tb
    case "$(uname -m)" in x86_64) arch="amd64";; aarch64|arm64) arch="arm64";; *) arch="amd64";; esac
    tb="$(mktemp -d)/go.tar.gz"
    curl -fsSL --max-time 300 "https://go.dev/dl/go1.22.12.linux-$arch.tar.gz" -o "$tb" 2>/dev/null \
        || curl -fsSL --max-time 300 "https://dl.google.com/go/go1.22.12.linux-$arch.tar.gz" -o "$tb" 2>/dev/null \
        || return 1
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$tb" 2>/dev/null || return 1
    ln -sf /usr/local/go/bin/go /usr/local/bin/go 2>/dev/null
    export PATH="$PATH:/usr/local/go/bin"
    command -v go >/dev/null 2>&1
}

dnstt_ensure_binary() {
    [ -x "$DNSTT_BIN" ] && return 0
    local arch=""
    case "$(uname -m)" in x86_64) arch="amd64";; aarch64|arm64) arch="arm64";; esac
    echo -e "${C}📥 Downloading pre-compiled DNSTT server binary...${N}"
    echo -e "${C}ℹ Detected $(uname -m) (${arch:-unknown}) architecture.${N}"
    if [ -n "$arch" ]; then
        curl -fsSL --max-time 180 "$DNSTT_REL/dnstt-server-linux-$arch" -o "$DNSTT_BIN" 2>/dev/null && chmod +x "$DNSTT_BIN"
    fi
    if [ -x "$DNSTT_BIN" ]; then echo -e "${G}DNSTT server binary ready.${N}"; return 0; fi
    rm -f "$DNSTT_BIN"
    echo -e "${Y}Pre-compiled binary is not published yet - building from source instead (one-time, a few minutes)...${N}"
    if command -v apt-get >/dev/null 2>&1 && ! command -v git >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq git >/dev/null 2>&1
    fi
    dnstt_install_go || { echo -e "${R}Could not install Go. Check the network and try again.${N}"; return 1; }
    local tmp; tmp="$(mktemp -d)"
    git clone -q --depth 1 https://github.com/Mygod/dnstt.git "$tmp/dnstt" 2>/dev/null \
        || git clone -q --depth 1 https://github.com/gharib-uk/dnstt "$tmp/dnstt" 2>/dev/null \
        || { rm -rf "$tmp"; echo -e "${R}Could not download the dnstt source.${N}"; return 1; }
    ( cd "$tmp/dnstt/dnstt-server" && go build -o "$DNSTT_BIN" . ) >/dev/null 2>&1
    rm -rf "$tmp"
    [ -x "$DNSTT_BIN" ] || { echo -e "${R}dnstt-server build failed.${N}"; return 1; }
    echo -e "${G}dnstt-server built and ready.${N}"
    return 0
}

dnstt_fw_add() {
    iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null \
        || iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    ip6tables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null \
        || ip6tables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    return 0
}

dnstt_fw_del() {
    while iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null; do
        iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    done
    while ip6tables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null; do
        ip6tables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    done
    return 0
}

DNSTT_REL="https://github.com/KOKOWNER/kok-manager/releases/download/tools-v1"

fw_note() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
        echo -e "${Y}⚠ UFW firewall is active - make sure the port is allowed.${N}"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        echo -e "${Y}⚠ firewalld is active - make sure the port is allowed.${N}"
    else
        echo -e "${C}ℹ No active firewall (UFW or firewalld) detected. Assuming ports are open.${N}"
    fi
}

dnstt_restore_resolved() {
    # undo the systemd-resolved stop done by dnstt_setup (only if WE stopped it)
    [ -f "$DNSTT_DIR/.resolved_stopped" ] || return 0
    local target
    target="$(cat "$DNSTT_DIR/resolv.target" 2>/dev/null)"
    [ -z "$target" ] && target="/run/systemd/resolve/stub-resolv.conf"
    rm -f /etc/resolv.conf
    ln -s "$target" /etc/resolv.conf 2>/dev/null
    systemctl enable systemd-resolved >/dev/null 2>&1
    systemctl start systemd-resolved 2>/dev/null
    rm -f "$DNSTT_DIR/.resolved_stopped" "$DNSTT_DIR/resolv.target"
    return 0
}

dnstt_details() {
    local domain pub fwd ns
    domain="$(cat "$DNSTT_DIR/domain.txt" 2>/dev/null)"
    pub="$(cat "$DNSTT_DIR/server.pub" 2>/dev/null)"
    fwd="$(cat "$DNSTT_DIR/forward.txt" 2>/dev/null)"
    ns="$(cat "$DNSTT_DIR/ns.txt" 2>/dev/null)"
    echo -e "${C}==================================================${N}"
    echo -e "${W}        📡 DNSTT Connection Details${N}"
    echo -e "${C}==================================================${N}"
    echo
    echo -e "${W}Your connection details:${N}"
    echo -e " ${C}-${N} Tunnel Domain: ${G}$domain${N}"
    echo -e " ${C}-${N} Public Key: ${G}$pub${N}"
    echo -e " ${C}-${N} Forwarding To: ${G}$fwd${N}"
    echo -e " ${C}-${N} NS Record: ${G}$domain${N}"
    echo -e " ${C}-${N} Action Required: ${Y}Ensure your SSH client is configured to use the DNS tunnel.${N}"
    echo
    echo -e "${W}Use these details in your client configuration.${N}"
    echo -e "${C}ℹ One-time DNS records (DNS only / grey cloud):  ${W}A${N} ${G}$ns${N} -> ${G}$(pub_ip)${N}   |   ${W}NS${N} ${G}$domain${N} -> ${G}$ns${N}"
}

dnstt_write_unit() { # $1 domain  $2 upstream  $3 mtu (may be empty)
    local domain="$1" upstream="$2" mtu="$3" mtuopt=""
    [ -n "$mtu" ] && mtuopt="-mtu $mtu"
    cat > /etc/systemd/system/dnstt.service <<EOF
[Unit]
Description=DNSTT (DNS Tunnel) server - KOK Manager
After=network.target

[Service]
ExecStart=$DNSTT_BIN -udp :53 -privkey-file $DNSTT_DIR/server.key $mtuopt $domain $upstream
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null
}

dnstt_setup() { # $1 = preset tunnel domain (optional, from CloudFlare flow)
    echo -e "${M}--- 📡 DNSTT (DNS Tunnel) Management ---${N}"
    mkdir -p "$DNSTT_DIR"; chmod 700 "$DNSTT_DIR"
    local preset="$1" fchoice upstream fwdlabel mode ns_domain domain mtu parent rand
    # migrate the legacy v2 units (kok-dnstt + iptables redirect), if present
    if [ -f /etc/systemd/system/kok-dnstt.service ]; then
        systemctl disable --now kok-dnstt.service kok-dnstt-fw.service >/dev/null 2>&1
        rm -f /etc/systemd/system/kok-dnstt.service /etc/systemd/system/kok-dnstt-fw.service
        systemctl daemon-reload 2>/dev/null
        dnstt_fw_del
    fi
    systemctl stop dnstt.service >/dev/null 2>&1
    echo -e "${C}⚙ Forcing release of Port 53 (stopping systemd-resolved)...${N}"
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        systemctl stop systemd-resolved 2>/dev/null
        systemctl disable systemd-resolved >/dev/null 2>&1
        if [ -L /etc/resolv.conf ]; then
            readlink /etc/resolv.conf > "$DNSTT_DIR/resolv.target" 2>/dev/null
            rm -f /etc/resolv.conf
            printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
        fi
        touch "$DNSTT_DIR/.resolved_stopped"
    fi
    echo
    echo -e "${C}🔍 Checking if port 53 (UDP) is available...${N}"
    if ss -lun 2>/dev/null | awk '{print $5}' | grep -qE ':53$'; then
        echo -e "${R}❌ Port 53 (UDP) is still in use by another process. Setup stopped.${N}"
        press_enter; return
    fi
    echo -e "${G}✅ Port 53 (UDP) is free to use.${N}"
    fw_note
    echo
    echo -e "${W}Please choose where DNSTT should forward traffic:${N}"
    echo -e "  ${C}[ 1]${N} ➡ Forward to local SSH service (port $(ssh_port))"
    echo -e "  ${C}[ 2]${N} ➡ Forward to local V2Ray backend (port 8787)"
    read -rp "👉 Enter your choice [2]: " fchoice; fchoice="${fchoice:-2}"
    if [ "$fchoice" = "1" ]; then
        upstream="127.0.0.1:$(ssh_port)"; fwdlabel="SSH (port $(ssh_port))"
        echo -e "${C}ℹ DNSTT will forward to SSH on 127.0.0.1:$(ssh_port).${N}"
    else
        upstream="127.0.0.1:8787"; fwdlabel="V2Ray (port 8787)"
        echo -e "${C}ℹ DNSTT will forward to the V2Ray backend on 127.0.0.1:8787.${N}"
    fi
    if [ -n "$preset" ]; then
        domain="$(printf '%s' "$preset" | tr -d ' ' | tr 'A-Z' 'a-z')"
        ns_domain="ns.$(echo "$domain" | cut -d. -f2-)"
        echo -e "${C}ℹ Using the domain from your CloudFlare setup: ${G}$domain${N} (nameserver host: $ns_domain)"
    else
        read -rp "👉 Auto-generate DNS records or use custom ones? (auto/custom) [auto]: " mode; mode="${mode:-auto}"
        if [ "$mode" = "custom" ]; then
            read -rp "👉 Enter your full nameserver domain (e.g., ns1.yourdomain.com): " ns_domain
            read -rp "👉 Enter your full tunnel domain (e.g., tun.yourdomain.com): " domain
        else
            read -rp "👉 Enter your parent domain (e.g., yourdomain.com): " parent
            parent="$(printf '%s' "$parent" | tr -d ' ' | tr 'A-Z' 'a-z')"
            if ! [[ "$parent" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || [[ "$parent" != *.* ]]; then
                echo -e "${R}Invalid parent domain.${N}"; press_enter; return
            fi
            rand="$(tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 6)"
            ns_domain="ns$rand.$parent"
            domain="tun$rand.$parent"
            echo -e "${C}ℹ Auto-generated nameserver: ${G}$ns_domain${N}"
            echo -e "${C}ℹ Auto-generated tunnel domain: ${G}$domain${N}"
        fi
        ns_domain="$(printf '%s' "$ns_domain" | tr -d ' ' | tr 'A-Z' 'a-z')"
        domain="$(printf '%s' "$domain" | tr -d ' ' | tr 'A-Z' 'a-z')"
        if ! [[ "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || [[ "$domain" != *.* ]] \
           || ! [[ "$ns_domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || [[ "$ns_domain" != *.* ]]; then
            echo -e "${R}Invalid domain.${N}"; press_enter; return
        fi
    fi
    read -rp "👉 Enter MTU value (e.g., 512, 1200) or press [Enter] for default: " mtu
    if [ -z "$mtu" ]; then
        echo -e "${C}ℹ Using default MTU.${N}"
    elif [[ "$mtu" =~ ^[0-9]+$ ]] && [ "$mtu" -ge 100 ] && [ "$mtu" -le 9000 ]; then
        echo -e "${C}ℹ Using MTU $mtu.${N}"
    else
        echo -e "${Y}Invalid MTU - using default.${N}"; mtu=""
    fi
    echo
    dnstt_ensure_binary || { echo -e "${R}DNSTT server binary is not ready. Setup stopped.${N}"; press_enter; return; }
    echo -e "${C}🔐 Generating cryptographic keys...${N}"
    "$DNSTT_BIN" -gen-key -privkey-file "$DNSTT_DIR/server.key" -pubkey-file "$DNSTT_DIR/server.pub" 2>/dev/null
    if [ ! -s "$DNSTT_DIR/server.key" ] || [ ! -s "$DNSTT_DIR/server.pub" ]; then
        # fallback: parse the printed keys and write the files ourselves
        local out priv pub
        out="$("$DNSTT_BIN" -gen-key 2>/dev/null)"
        priv="$(printf '%s' "$out" | awk '/privkey/{print $2}' | head -1)"
        pub="$(printf '%s' "$out" | awk '/pubkey/{print $2}' | head -1)"
        [ -z "$priv" ] || [ -z "$pub" ] && { echo -e "${R}Key generation failed.${N}"; press_enter; return; }
        printf '%s' "$priv" > "$DNSTT_DIR/server.key"
        printf '%s' "$pub" > "$DNSTT_DIR/server.pub"
        echo "privkey written to $DNSTT_DIR/server.key"
        echo "pubkey written to $DNSTT_DIR/server.pub"
    fi
    chmod 600 "$DNSTT_DIR/server.key"; chmod 644 "$DNSTT_DIR/server.pub"
    echo
    echo -e "${C}📝 Creating systemd service...${N}"
    dnstt_write_unit "$domain" "$upstream" "$mtu"
    echo -e "${C}💾 Saving configuration and starting service...${N}"
    printf '%s' "$domain" > "$DNSTT_DIR/domain.txt"
    printf '%s' "$ns_domain" > "$DNSTT_DIR/ns.txt"
    printf '%s' "$fwdlabel" > "$DNSTT_DIR/forward.txt"
    printf '%s' "$mtu" > "$DNSTT_DIR/mtu.txt"
    systemctl enable dnstt.service 2>&1 | grep -i 'created symlink' || true
    systemctl restart dnstt.service 2>/dev/null
    sleep 1
    log "DNSTT setup domain=$domain forward=$fwdlabel mtu=${mtu:-default}"
    echo
    if systemctl is-active --quiet dnstt.service 2>/dev/null; then
        echo -e "${G}✅ SUCCESS: DNSTT has been installed and started!${N}"
        echo
        dnstt_details
    else
        echo -e "${R}❌ DNSTT service did not start - check: systemctl status dnstt${N}"
    fi
    press_enter
}

dnstt_info() {
    echo -e "${M}--- 📡 DNSTT (DNS Tunnel) Management ---${N}"
    if [ ! -f "$DNSTT_DIR/domain.txt" ]; then
        echo "DNSTT is not set up yet. Use Setup first."; press_enter; return
    fi
    local st
    st="$(systemctl is-active dnstt.service 2>/dev/null || echo unknown)"
    echo -e " Status : ${G}$st${N}"
    echo
    dnstt_details
    press_enter
}

dnstt_restart() {
    systemctl restart dnstt.service 2>/dev/null && echo -e "${G}DNSTT restarted.${N}" || echo -e "${R}Restart failed (not set up?).${N}"
    press_enter
}

dnstt_remove() {
    read -rp "Remove DNSTT completely? [y/N]: " ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; press_enter; return; }
    systemctl disable --now dnstt.service >/dev/null 2>&1
    rm -f /etc/systemd/system/dnstt.service
    systemctl disable --now kok-dnstt.service kok-dnstt-fw.service >/dev/null 2>&1
    rm -f /etc/systemd/system/kok-dnstt.service /etc/systemd/system/kok-dnstt-fw.service
    systemctl daemon-reload 2>/dev/null
    dnstt_fw_del
    dnstt_restore_resolved
    rm -rf "$DNSTT_DIR"
    rm -f "$DNSTT_BIN"
    log "DNSTT removed"
    echo -e "${G}DNSTT removed (systemd-resolved restored if it was stopped).${N}"
    press_enter
}

dnstt_menu() {
    while true; do
        echo -e "${M}--- 📡 DNSTT (DNS Tunnel) Management ---${N}"
        if [ -f "$DNSTT_DIR/domain.txt" ]; then
            echo -e " Domain : ${G}$(cat "$DNSTT_DIR/domain.txt")${N}   Status: ${G}$(systemctl is-active dnstt.service 2>/dev/null || echo unknown)${N}"
        else
            echo -e " Status : ${R}not set up${N}"
        fi
        echo -e " ${W}[1]${N} Setup / Re-setup DNSTT"
        echo -e " ${W}[2]${N} View Connection Details"
        echo -e " ${W}[3]${N} Restart DNSTT"
        echo -e " ${W}[4]${N} Remove DNSTT"
        echo -e " ${W}[0]${N} Back"
        read -rp " Choose: " dc
        case "$dc" in
            1) dnstt_setup ;;
            2) dnstt_info ;;
            3) dnstt_restart ;;
            4) dnstt_remove ;;
            0) return ;;
            *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

# ---------- DT Proxy Manager (second, direct DNSTT endpoint) ----------
DTP_DIR="$CONF_DIR/dtproxy"

dtproxy_write_unit() {
    local domain="$1" port="$2"
    cat > /etc/systemd/system/kok-dtproxy.service <<EOF
[Unit]
Description=KOK DT Proxy (direct DNSTT endpoint)
After=network.target

[Service]
ExecStart=$DNSTT_BIN -udp :$port -privkey-file $DTP_DIR/server.key $domain 127.0.0.1:$(ssh_port)
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable kok-dtproxy.service >/dev/null 2>&1
}

dtproxy_setup() {
    echo -e "${Y}--- DT PROXY SETUP (direct DNSTT endpoint) ---${N}"
    echo -e "${W}This runs a SECOND dnstt endpoint on its own UDP port, for clients${N}"
    echo -e "${W}that connect directly to SERVER-IP:PORT (no DNS delegation needed).${N}"
    mkdir -p "$DTP_DIR"; chmod 700 "$DTP_DIR"
    local domain port priv pub
    read -rp "Domain label for this endpoint (e.g. dt.yourdomain.com): " domain
    domain="$(printf '%s' "$domain" | tr -d ' ' | tr 'A-Z' 'a-z')"
    if ! [[ "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || [[ "$domain" != *.* ]]; then
        echo -e "${R}Invalid domain.${N}"; press_enter; return
    fi
    read -rp "UDP port [5500]: " port; port="${port:-5500}"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { echo -e "${R}Invalid port.${N}"; press_enter; return; }
    if [ -f "$DNSTT_DIR/server.key" ]; then
        priv="$(cat "$DNSTT_DIR/server.key")"
        echo -e "${G}Reusing your DNSTT private key (same public key for customers).${N}"
    else
        priv="$(dnstt_choose_key)"
        [ -z "$priv" ] && { echo -e "${R}Cancelled.${N}"; press_enter; return; }
    fi
    printf '%s' "$priv" > "$DTP_DIR/server.key"; chmod 600 "$DTP_DIR/server.key"
    pub="$(dnstt_derive_pub "$priv")"
    if [ -z "$pub" ]; then pub="$(dnstt_pub_from_run "$DTP_DIR/server.key")"; fi
    [ -z "$pub" ] && { echo -e "${R}Could not derive the public key.${N}"; press_enter; return; }
    printf '%s' "$pub" > "$DTP_DIR/server.pub"; chmod 644 "$DTP_DIR/server.pub"
    printf '%s' "$domain" > "$DTP_DIR/domain.txt"
    printf '%s' "$port" > "$DTP_DIR/port.txt"
    dnstt_ensure_binary || { echo -e "${R}Config saved, but dnstt-server is not installed yet.${N}"; press_enter; return; }
    dtproxy_write_unit "$domain" "$port"
    systemctl restart kok-dtproxy.service 2>/dev/null
    sleep 1
    log "DTPROXY setup domain=$domain port=$port"
    echo -e "${C}----------------------------------------${N}"
    echo -e "${W}        DT PROXY DETAILS${N}"
    echo -e "${C}----------------------------------------${N}"
    echo -e " Resolver   : ${G}$(pub_ip) : $port (UDP, direct)${N}"
    echo -e " Domain     : ${G}$domain${N}"
    echo -e " Public Key : ${G}$pub${N}"
    echo -e " Status     : ${G}$(systemctl is-active kok-dtproxy.service 2>/dev/null || echo unknown)${N}"
    echo -e "${C}----------------------------------------${N}"
    press_enter
}

dtproxy_menu() {
    while true; do
        echo -e "${Y}--- DT PROXY MANAGER ---${N}"
        if [ -f "$DTP_DIR/domain.txt" ]; then
            echo -e " Domain : ${G}$(cat "$DTP_DIR/domain.txt")${N}   Port: ${G}$(cat "$DTP_DIR/port.txt" 2>/dev/null)${N}   Status: ${G}$(systemctl is-active kok-dtproxy.service 2>/dev/null || echo unknown)${N}"
        else
            echo -e " Status : ${R}not set up${N}"
        fi
        echo -e " ${W}[1]${N} Setup / Re-setup DT Proxy"
        echo -e " ${W}[2]${N} Restart DT Proxy"
        echo -e " ${W}[3]${N} Remove DT Proxy"
        echo -e " ${W}[0]${N} Back"
        read -rp " Choose: " dc
        case "$dc" in
            1) dtproxy_setup ;;
            2) systemctl restart kok-dtproxy.service 2>/dev/null && echo -e "${G}Restarted.${N}" || echo -e "${R}Restart failed.${N}"; press_enter ;;
            3)
                read -rp "Remove DT Proxy? [y/N]: " ans
                if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                    systemctl disable --now kok-dtproxy.service >/dev/null 2>&1
                    rm -f /etc/systemd/system/kok-dtproxy.service
                    systemctl daemon-reload 2>/dev/null
                    rm -rf "$DTP_DIR"
                    echo -e "${G}DT Proxy removed.${N}"
                else echo "Cancelled."; fi
                press_enter ;;
            0) return ;;
            *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

# ---------- Protocol & Panel Management ----------
KOK_RAW="https://raw.githubusercontent.com/KOKOWNER/kok-manager/main"

svc_tag() { # unit -> (Active)/(Inactive)
    if systemctl is-active --quiet "$1" 2>/dev/null; then echo -e "${G}(Active)${N}"; else echo -e "${R}(Inactive)${N}"; fi
}

inst_tag() { # $1 = 0/1 installed
    if [ "$1" = "1" ]; then echo -e "${G}(Installed)${N}"; else echo -e "${R}(Not Installed)${N}"; fi
}

port_busy() { ss -tulnp 2>/dev/null | grep -q ":$1 "; }

apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq "$@" >/dev/null 2>&1
}

# --- badvpn (UDP gateway, port 7300) ---
badvpn_install() {
    echo -e "${Y}--- Installing badvpn (UDP 7300) ---${N}"
    if [ -x /usr/local/bin/badvpn-udpgw ]; then echo -e "${G}badvpn-udpgw is already installed.${N}"; press_enter; return; fi
    echo "Installing build tools and compiling badvpn (one-time, a few minutes)..."
    apt_install build-essential cmake git pkg-config libnspr4-dev libnss3-dev
    local tmp; tmp="$(mktemp -d)"
    git clone -q --depth 1 https://github.com/ambrop72/badvpn.git "$tmp/badvpn" 2>/dev/null \
        || { rm -rf "$tmp"; echo -e "${R}Download failed.${N}"; press_enter; return; }
    mkdir -p "$tmp/badvpn/build"
    ( cd "$tmp/badvpn/build" && cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_TUN2SOCKS=OFF -DBUILD_CLIENT=OFF -DBUILD_FLOODER=OFF >/dev/null 2>&1 \
        && make -j"$(nproc)" badvpn-udpgw >/dev/null 2>&1 )
    if [ ! -f "$tmp/badvpn/build/udpgw/badvpn-udpgw" ]; then
        rm -rf "$tmp"; echo -e "${R}Build failed.${N}"; press_enter; return
    fi
    cp "$tmp/badvpn/build/udpgw/badvpn-udpgw" /usr/local/bin/badvpn-udpgw
    rm -rf "$tmp"
    cat > /etc/systemd/system/badvpn-udpgw.service <<'EOF'
[Unit]
Description=BadVPN UDP Gateway
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 100
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable --now badvpn-udpgw.service >/dev/null 2>&1
    sleep 1
    if systemctl is-active --quiet badvpn-udpgw.service; then
        echo -e "${G}SUCCESS: badvpn-udpgw is active on 127.0.0.1:7300 (UDP).${N}"; log "BADVPN install"
    else echo -e "${R}Service did not start - check: systemctl status badvpn-udpgw${N}"; fi
    press_enter
}

badvpn_uninstall() {
    systemctl disable --now badvpn-udpgw.service >/dev/null 2>&1
    rm -f /etc/systemd/system/badvpn-udpgw.service /usr/local/bin/badvpn-udpgw
    systemctl daemon-reload 2>/dev/null
    echo -e "${G}badvpn removed.${N}"; log "BADVPN uninstall"; press_enter
}

# --- udp-custom (HTTP Custom UDP tunnel) ---
udpcustom_install() {
    echo -e "${Y}--- Installing udp-custom ---${N}"
    if [ -x /root/udp/udp-custom ]; then echo -e "${G}udp-custom is already installed.${N}"; press_enter; return; fi
    if [ "$(uname -m)" != "x86_64" ]; then
        echo -e "${R}Upstream udp-custom only publishes an amd64 binary - this server is $(uname -m).${N}"; press_enter; return
    fi
    mkdir -p /root/udp
    echo "Downloading udp-custom binary (upstream: github.com/http-custom/udp-custom)..."
    curl -fsSL --max-time 120 "https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" -o /root/udp/udp-custom \
        || { echo -e "${R}Download failed.${N}"; press_enter; return; }
    chmod +x /root/udp/udp-custom
    cat > /root/udp/config.json <<'EOF'
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
    cat > /etc/systemd/system/udp-custom.service <<'EOF'
[Unit]
Description=UDP Custom by ePro Dev. Team
After=network.target

[Service]
User=root
Type=simple
ExecStart=/root/udp/udp-custom server
WorkingDirectory=/root/udp/
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
    sysctl -w net.core.rmem_max=83886080 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=83886080 >/dev/null 2>&1
    systemctl daemon-reload 2>/dev/null
    systemctl enable --now udp-custom.service >/dev/null 2>&1
    sleep 1
    if systemctl is-active --quiet udp-custom.service; then
        echo -e "${G}SUCCESS: udp-custom is active (UDP :36712).${N}"; log "UDPCUSTOM install"
    else echo -e "${R}Service did not start - check: systemctl status udp-custom${N}"; fi
    press_enter
}

udpcustom_uninstall() {
    systemctl disable --now udp-custom.service >/dev/null 2>&1
    rm -f /etc/systemd/system/udp-custom.service
    systemctl daemon-reload 2>/dev/null
    rm -rf /root/udp
    echo -e "${G}udp-custom removed.${N}"; log "UDPCUSTOM uninstall"; press_enter
}

# --- SSL Tunnel (stunnel, port 444 -> SSH) ---
ssltunnel_install() {
    echo -e "${Y}--- Installing SSL Tunnel (Port 444) ---${N}"
    if [ -f /etc/stunnel/kok.conf ]; then echo -e "${G}SSL Tunnel is already configured.${N}"; press_enter; return; fi
    apt_install stunnel4
    mkdir -p /etc/stunnel
    if [ ! -f /etc/stunnel/kok.pem ]; then
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/C=MM/ST=Yangon/L=Yangon/O=KOK/CN=localhost" \
            -keyout /etc/stunnel/kok.key -out /etc/stunnel/kok.crt 2>/dev/null
        cat /etc/stunnel/kok.key /etc/stunnel/kok.crt > /etc/stunnel/kok.pem
        chmod 600 /etc/stunnel/kok.pem /etc/stunnel/kok.key
    fi
    cat > /etc/stunnel/kok.conf <<EOF
pid = /var/run/stunnel-kok.pid
foreground = no
[ssh]
accept = 444
connect = 127.0.0.1:$(ssh_port)
cert = /etc/stunnel/kok.pem
EOF
    if [ -f /etc/default/stunnel4 ]; then
        sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
        grep -q '^ENABLED=' /etc/default/stunnel4 || echo 'ENABLED=1' >> /etc/default/stunnel4
    fi
    systemctl restart stunnel4 2>/dev/null || service stunnel4 restart 2>/dev/null
    sleep 1
    if port_busy 444; then
        echo -e "${G}SUCCESS: SSL Tunnel is listening on port 444 -> SSH (127.0.0.1:$(ssh_port)).${N}"; log "SSLTUNNEL install"
    else echo -e "${R}Port 444 is not listening - check: systemctl status stunnel4${N}"; fi
    press_enter
}

ssltunnel_uninstall() {
    rm -f /etc/stunnel/kok.conf /etc/stunnel/kok.pem
    systemctl restart stunnel4 2>/dev/null
    echo -e "${G}SSL Tunnel removed.${N}"; log "SSLTUNNEL uninstall"; press_enter
}

# --- Websockets Proxy (falconproxy profiles) ---
wsproxy_install() {
    echo -e "${M}--- 🦅 Installing Websockets Proxy ---${N}"
    echo -e "${C}🌐 Fetching available versions from GitHub...${N}"
    echo
    echo "Select a version to install:"
    echo -e "  ${C}[ 1]${N} v1.2-RustFast"
    echo -e "  ${C}[ 2]${N} v1-vodafoneIE"
    echo -e "  ${C}[ 3]${N} v0-WebSockets"
    echo -e "  ${C}[ 0]${N} ↩️ Cancel"
    local ver vername profile ports p
    read -rp "👉 Enter version number [1]: " ver; ver="${ver:-1}"
    case "$ver" in
        1) profile="rustfast"; vername="v1.2-RustFast" ;;
        2) profile="vodafone"; vername="v1-vodafoneIE" ;;
        3) profile="v0"; vername="v0-WebSockets" ;;
        0) echo "Cancelled."; press_enter; return ;;
        *) echo -e "${R}Invalid version.${N}"; press_enter; return ;;
    esac
    read -rp "👉 Enter port(s) for Websockets Proxy (e.g., 8080 or 8080 8888) [8080]: " ports; ports="${ports:-8080}"
    for p in $ports; do
        if ! [[ "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
            echo -e "${R}Invalid port: $p${N}"; press_enter; return
        fi
        echo -e "${C}🔍 Checking if port $p is available...${N}"
        if port_busy "$p"; then
            echo -e "${R}Port $p is already in use - choose another.${N}"; press_enter; return
        fi
        echo -e "${G}✅ Port $p is free to use.${N}"
    done
    fw_note
    echo -e "${C}⚙ Detecting system architecture...${N}"
    local archlbl="amd64" archname="x86_64 (amd64)"
    case "$(uname -m)" in aarch64|arm64) archlbl="arm64"; archname="aarch64 (arm64)";; esac
    echo -e "${C}ℹ Detected $archname architecture.${N}"
    echo -e "${C}📥 Downloading Websockets Proxy $vername (falconproxy)...${N}"
    mkdir -p /etc/falconproxy
    curl -fsSL --max-time 120 "$DNSTT_REL/falconproxy-linux-$archlbl" -o /usr/local/bin/falconproxy 2>/dev/null && chmod +x /usr/local/bin/falconproxy
    if [ ! -x /usr/local/bin/falconproxy ]; then
        echo -e "${Y}Pre-compiled binary is not published yet - building from source instead (one-time)...${N}"
        local srcdir; srcdir="$(mktemp -d)"
        curl -fsSL --max-time 60 "$KOK_RAW/wsproxy.go" -o "$srcdir/wsproxy.go" \
            || { rm -rf "$srcdir"; echo -e "${R}Could not fetch the proxy source from GitHub.${N}"; press_enter; return; }
        dnstt_install_go || { rm -rf "$srcdir"; echo -e "${R}Go is required to build the proxy.${N}"; press_enter; return; }
        ( cd "$srcdir" && go build -o /usr/local/bin/falconproxy wsproxy.go ) >/dev/null 2>&1
        rm -rf "$srcdir"
    fi
    [ -x /usr/local/bin/falconproxy ] || { echo -e "${R}Install failed.${N}"; press_enter; return; }
    printf '%s' "$profile" > /etc/falconproxy/profile
    printf '%s' "$ports" > /etc/falconproxy/ports
    echo -e "${C}📝 Creating systemd service file...${N}"
    cat > /etc/systemd/system/falconproxy.service <<EOF
[Unit]
Description=Falcon Websockets Proxy (KOK)
After=network.target

[Service]
ExecStart=/usr/local/bin/falconproxy -ports "$ports" -backend 127.0.0.1:$(ssh_port) -profile $profile
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
    echo -e "${C}💾 Saving configuration...${N}"
    systemctl daemon-reload 2>/dev/null
    echo -e "${C}▶ Enabling and starting Websockets Proxy service...${N}"
    systemctl enable --now falconproxy.service >/dev/null 2>&1
    sleep 1
    if systemctl is-active --quiet falconproxy.service; then
        echo -e "${G}✅ SUCCESS: Websockets Proxy $vername is installed and active.${N}"
        echo -e "   Listening on port(s): ${G}$ports${N}  ->  SSH 127.0.0.1:$(ssh_port)"
        log "WSPROXY install profile=$profile ports=$ports"
    else echo -e "${R}Service did not start - check: systemctl status falconproxy${N}"; fi
    press_enter
}

wsproxy_uninstall() {
    systemctl disable --now falconproxy.service >/dev/null 2>&1
    rm -f /etc/systemd/system/falconproxy.service /usr/local/bin/falconproxy
    systemctl daemon-reload 2>/dev/null
    rm -rf /etc/falconproxy
    echo -e "${G}Websockets Proxy removed.${N}"; log "WSPROXY uninstall"; press_enter
}

# --- Nginx Proxy (80/443) ---
nginx_install_manage() {
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${Y}--- Installing Nginx Proxy (80/443) ---${N}"
        apt_install nginx openssl
        local wsport="8080"
        [ -f /etc/falconproxy/ports ] && wsport="$(awk '{print $1}' /etc/falconproxy/ports)"
        if [ ! -f /etc/nginx/kok.crt ]; then
            openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
                -subj "/C=MM/ST=Yangon/L=Yangon/O=KOK/CN=localhost" \
                -keyout /etc/nginx/kok.key -out /etc/nginx/kok.crt 2>/dev/null
        fi
        cat > /etc/nginx/conf.d/kok-ws-proxy.conf <<EOF
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:$wsport;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/kok.crt;
    ssl_certificate_key /etc/nginx/kok.key;
    location / {
        proxy_pass http://127.0.0.1:$wsport;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
        if nginx -t 2>/dev/null; then
            systemctl enable --now nginx >/dev/null 2>&1; systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
            echo -e "${G}SUCCESS: Nginx Proxy is active on 80/443 -> Websockets Proxy port $wsport.${N}"
            log "NGINX install backend=$wsport"
        else echo -e "${R}nginx config test failed - run: nginx -t${N}"; fi
        press_enter
        return
    fi
    while true; do
        echo -e "${Y}--- MANAGE NGINX PROXY ---${N}"
        echo -e " Status: $(svc_tag nginx.service)   Config: /etc/nginx/conf.d/kok-ws-proxy.conf"
        echo -e " ${W}[1]${N} Restart Nginx"
        echo -e " ${W}[2]${N} View proxy config"
        echo -e " ${W}[3]${N} Uninstall KOK Nginx Proxy config"
        echo -e " ${W}[0]${N} Back"
        read -rp " Choose: " nc
        case "$nc" in
            1) systemctl restart nginx 2>/dev/null && echo -e "${G}Restarted.${N}" || echo -e "${R}Failed.${N}"; press_enter ;;
            2) cat /etc/nginx/conf.d/kok-ws-proxy.conf 2>/dev/null; press_enter ;;
            3) rm -f /etc/nginx/conf.d/kok-ws-proxy.conf; nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null; echo -e "${G}KOK Nginx Proxy config removed (nginx package kept).${N}"; log "NGINX config removed"; press_enter; return ;;
            0) return ;;
            *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

# --- ZiVPN (UDP 5667) ---
zivpn_install() {
    echo -e "${Y}--- Installing ZiVPN (UDP 5667) ---${N}"
    if [ -x /usr/local/bin/zivpn ]; then echo -e "${G}ZiVPN is already installed.${N}"; press_enter; return; fi
    local asset
    case "$(uname -m)" in
        x86_64) asset="udp-zivpn-linux-amd64" ;;
        aarch64|arm64) asset="udp-zivpn-linux-arm64" ;;
        *) echo -e "${R}Unsupported architecture: $(uname -m)${N}"; press_enter; return ;;
    esac
    echo "Downloading ZiVPN server binary..."
    curl -fsSL --max-time 180 "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/$asset" -o /usr/local/bin/zivpn \
        || { echo -e "${R}Download failed.${N}"; press_enter; return; }
    chmod +x /usr/local/bin/zivpn
    mkdir -p /etc/zivpn
    local pwlist pwjson
    read -rp "ZiVPN UDP password(s), comma separated [zi]: " pwlist; pwlist="${pwlist:-zi}"
    pwjson="$(printf '%s' "$pwlist" | sed 's/,/","/g')"
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt 2>/dev/null
    cat > /etc/zivpn/config.json <<ZCFG
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["$pwjson"]
  }
}
ZCFG
    sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1
    cat > /etc/systemd/system/zivpn.service <<'ZUNIT'
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
ZUNIT
    systemctl daemon-reload 2>/dev/null
    systemctl enable --now zivpn.service >/dev/null 2>&1
    sleep 1
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${G}SUCCESS: ZiVPN is active (UDP :5667). Password(s): $pwlist${N}"; log "ZIVPN install"
    else echo -e "${R}Service did not start - check: systemctl status zivpn${N}"; fi
    press_enter
}

zivpn_uninstall() {
    systemctl disable --now zivpn.service >/dev/null 2>&1
    rm -f /etc/systemd/system/zivpn.service /usr/local/bin/zivpn
    systemctl daemon-reload 2>/dev/null
    rm -rf /etc/zivpn
    echo -e "${G}ZiVPN removed.${N}"; log "ZIVPN uninstall"; press_enter
}

# --- X-UI Panel ---
xui_install() {
    echo -e "${Y}--- Installing X-UI Panel ---${N}"
    if systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service' || [ -d /usr/local/x-ui ]; then
        echo -e "${G}X-UI Panel is already installed.${N}"; press_enter; return
    fi
    echo -e "${W}This downloads and runs the OFFICIAL 3x-ui installer (mhsanaei/3x-ui on GitHub, via jsDelivr CDN).${N}"
    echo -e "${W}It will ask you for a port / username / password - answer on screen.${N}"
    read -rp "Continue? [y/N]: " ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; press_enter; return; }
    local xui_tmp; xui_tmp="$(mktemp)"
    if curl -Ls --max-time 120 "https://cdn.jsdelivr.net/gh/mhsanaei/3x-ui@master/install.sh" -o "$xui_tmp"; then
        bash "$xui_tmp"
    else
        echo -e "${R}Could not download the X-UI installer.${N}"
    fi
    rm -f "$xui_tmp"
    log "XUI install attempted"
    press_enter
}

xui_uninstall() {
    read -rp "Remove X-UI Panel completely? [y/N]: " ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; press_enter; return; }
    systemctl disable --now x-ui >/dev/null 2>&1
    rm -f /etc/systemd/system/x-ui.service
    systemctl daemon-reload 2>/dev/null
    rm -rf /usr/local/x-ui /etc/x-ui
    echo -e "${G}X-UI Panel removed.${N}"; log "XUI uninstall"; press_enter
}

protocol_manager() {
    while true; do
        local t_badvpn t_udp t_ssl t_dnstt t_ws t_nginx t_zivpn t_xui
        t_badvpn="$(svc_tag badvpn-udpgw.service)"
        t_udp="$(svc_tag udp-custom.service)"
        if [ -f /etc/stunnel/kok.conf ]; then t_ssl="$(svc_tag stunnel4.service)"; else t_ssl="$(echo -e "${R}(Inactive)${N}")"; fi
        t_dnstt="$(svc_tag dnstt.service)"
        t_ws="$(svc_tag falconproxy.service)"
        t_nginx="$(svc_tag nginx.service)"
        t_zivpn="$(svc_tag zivpn.service)"
        if systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service' || [ -d /usr/local/x-ui ]; then t_xui="$(inst_tag 1)"; else t_xui="$(inst_tag 0)"; fi
        echo -e "${M}==========[ PROTOCOL & PANEL MANAGEMENT ]==========${N}"
        echo -e "${Y}--- TUNNELLING PROTOCOLS ---${N}"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "1" "Install badvpn (UDP 7300)" "$t_badvpn"
        printf "  ${C}[%2s]${N} ${G}%-48s${N}\n" "2" "Uninstall badvpn"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "3" "Install udp-custom" "$t_udp"
        printf "  ${C}[%2s]${N} ${G}%-48s${N}\n" "4" "Uninstall udp-custom"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "5" "Install SSL Tunnel (Port 444)" "$t_ssl"
        printf "  ${C}[%2s]${N} ${G}%-48s${N}\n" "6" "Uninstall SSL Tunnel"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "7" "Install/View DNSTT (Port 53)" "$t_dnstt"
        printf "  ${C}[%2s]${N} ${G}%-48s${N}\n" "8" "Uninstall DNSTT"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "9" "Install Websockets Proxy (Select Version)" "$t_ws"
        printf "  ${C}[%2s]${N} ${G}%-48s${N}\n" "10" "Uninstall Websockets Proxy"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "11" "Install/Manage Nginx Proxy (80/443)" "$t_nginx"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "16" "Install ZiVPN (UDP 5667)" "$t_zivpn"
        printf "  ${C}[%2s]${N} ${G}%-48s${N}\n" "17" "Uninstall ZiVPN"
        echo -e "${Y}--- MANAGEMENT PANELS ---${N}"
        printf "  ${C}[%2s]${N} ${G}%-48s${N} %s\n" "12" "Install X-UI Panel" "$t_xui"
        printf "  ${C}[%2s]${N} ${G}%-48s${N}\n" "13" "Uninstall X-UI Panel"
        echo -e "${C}----------------------------------------------------------------------${N}"
        printf "  ${C}[%2s]${N} ${G}%s${N}\n" "0" "Return to Main Menu"
        echo
        read -rp "Select an option: " pc
        case "$pc" in
            1) badvpn_install ;;
            2) badvpn_uninstall ;;
            3) udpcustom_install ;;
            4) udpcustom_uninstall ;;
            5) ssltunnel_install ;;
            6) ssltunnel_uninstall ;;
            7) if [ -f "$DNSTT_DIR/domain.txt" ]; then dnstt_info; else dnstt_setup; fi ;;
            8) dnstt_remove ;;
            9) wsproxy_install ;;
            10) wsproxy_uninstall ;;
            11) nginx_install_manage ;;
            16) zivpn_install ;;
            17) zivpn_uninstall ;;
            12) xui_install ;;
            13) xui_uninstall ;;
            0) return ;;
            *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

# ---------- Traffic Monitor (Lite) ----------
traffic_monitor() {
    echo -e "${Y}--- TRAFFIC MONITOR (LITE) ---${N}"
    local iface rx tx
    iface="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')"
    [ -z "$iface" ] && iface="$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -1)"
    echo -e " Interface : ${G}$iface${N}"
    if [ -n "$iface" ] && [ -f "/sys/class/net/$iface/statistics/rx_bytes" ]; then
        rx="$(cat "/sys/class/net/$iface/statistics/rx_bytes")"
        tx="$(cat "/sys/class/net/$iface/statistics/tx_bytes")"
        awk -v r="$rx" -v t="$tx" 'BEGIN{
            printf " Since boot:  RX %.2f GB   TX %.2f GB   Total %.2f GB\n", r/1073741824, t/1073741824, (r+t)/1073741824 }'
    fi
    if command -v vnstat >/dev/null 2>&1; then
        echo -e "${W}vnstat (daily / monthly):${N}"
        vnstat -d 2>/dev/null | head -12
        vnstat -m 2>/dev/null | head -8
    else
        echo -e "${W}Tip: install 'vnstat' to keep daily/monthly history across reboots.${N}"
    fi
    echo
    echo -e " ${W}[1]${N} Run speed test now"
    echo -e " ${W}[0]${N} Back"
    read -rp " Choose: " tc
    if [ "$tc" = "1" ]; then
        echo "Ping 1.1.1.1:"; ping -c 4 -q 1.1.1.1 2>/dev/null | tail -2
        echo "Download test (25 MB from Cloudflare):"
        local sp
        sp="$(curl -s -o /dev/null -w '%{speed_download}' --max-time 30 'https://speed.cloudflare.com/__down?bytes=25000000' 2>/dev/null)"
        if [ -n "$sp" ] && [ "$sp" != "0" ]; then
            awk -v b="$sp" 'BEGIN{printf " ~ %.2f Mbps (%.2f MB/s)\n", b*8/1000000, b/1048576}'
        else echo " Download test failed (network?)."; fi
    fi
    press_enter
}

# ---------- Block Torrent (Anti-P2P) ----------
TORRENT_STRINGS=("BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "info_hash" "get_peers" "find_node" "announce_peer" "torrent")

torrent_on() {
    local s chain
    for chain in FORWARD OUTPUT; do
        for s in "${TORRENT_STRINGS[@]}"; do
            iptables -C "$chain" -p tcp -m string --string "$s" --algo bm -j DROP 2>/dev/null \
                || iptables -A "$chain" -p tcp -m string --string "$s" --algo bm -j DROP 2>/dev/null
            iptables -C "$chain" -p udp -m string --string "$s" --algo bm -j DROP 2>/dev/null \
                || iptables -A "$chain" -p udp -m string --string "$s" --algo bm -j DROP 2>/dev/null
        done
    done
}

torrent_off() {
    local s chain
    for chain in FORWARD OUTPUT; do
        for s in "${TORRENT_STRINGS[@]}"; do
            while iptables -C "$chain" -p tcp -m string --string "$s" --algo bm -j DROP 2>/dev/null; do
                iptables -D "$chain" -p tcp -m string --string "$s" --algo bm -j DROP 2>/dev/null
            done
            while iptables -C "$chain" -p udp -m string --string "$s" --algo bm -j DROP 2>/dev/null; do
                iptables -D "$chain" -p udp -m string --string "$s" --algo bm -j DROP 2>/dev/null
            done
        done
    done
}

torrent_status() {
    if iptables -C FORWARD -p tcp -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null; then echo "ON"; else echo "OFF"; fi
}

block_torrent() {
    echo -e "${Y}--- BLOCK TORRENT (ANTI-P2P) ---${N}"
    echo -e " Current status: ${G}$(torrent_status)${N}"
    echo -e " ${W}[1]${N} Enable torrent blocking"
    echo -e " ${W}[2]${N} Disable torrent blocking"
    echo -e " ${W}[0]${N} Back"
    read -rp " Choose: " bc
    case "$bc" in
        1) torrent_on; log "TORRENT block on"
           if [ "$(torrent_status)" = "ON" ]; then
               echo -e "${G}Torrent blocking enabled (BitTorrent string rules in FORWARD/OUTPUT).${N}"
           else
               echo -e "${R}Rules could not be added - iptables is not available/permitted on this server.${N}"
           fi ;;
        2) torrent_off; log "TORRENT block off"
           if [ "$(torrent_status)" = "OFF" ]; then
               echo -e "${G}Torrent blocking disabled.${N}"
           else
               echo -e "${R}Some rules could not be removed - check iptables manually.${N}"
           fi ;;
        *) echo "Back." ;;
    esac
    press_enter
}

# ---------- CloudFlare Free Domain (automates DNS records on YOUR domain) ----------
CF_TOKEN_FILE="$CONF_DIR/cf_token"

cf_api() { # method path [json]
    local method="$1" path="$2" data="$3" token
    token="$(cat "$CF_TOKEN_FILE" 2>/dev/null)"
    [ -z "$token" ] && return 1
    if [ -n "$data" ]; then
        curl -s --max-time 30 -X "$method" "https://api.cloudflare.com/client/v4$path" \
            -H "Authorization: Bearer $token" -H "Content-Type: application/json" --data "$data"
    else
        curl -s --max-time 30 -X "$method" "https://api.cloudflare.com/client/v4$path" \
            -H "Authorization: Bearer $token" -H "Content-Type: application/json"
    fi
}

cf_first_id() { grep -o '"id":"[a-f0-9]\{32\}"' | head -1 | cut -d'"' -f4; }

cf_upsert_record() { # zone_id type name content
    local zid="$1" type="$2" name="$3" content="$4" existing resp
    existing="$(cf_api GET "/zones/$zid/dns_records?type=$type&name=$name" | cf_first_id)"
    if [ -n "$existing" ]; then
        resp="$(cf_api PATCH "/zones/$zid/dns_records/$existing" "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":false,\"ttl\":120}")"
    else
        resp="$(cf_api POST "/zones/$zid/dns_records" "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":false,\"ttl\":120}")"
    fi
    case "$resp" in *'"success":true'*) return 0 ;; *) echo "$resp" | head -c 300; return 1 ;; esac
}

cloudflare_menu() {
    while true; do
        echo -e "${Y}--- CLOUDFLARE FREE DOMAIN ---${N}"
        echo -e "${W}Automates the DNS records for your tunnel on a domain that YOU own${N}"
        echo -e "${W}in Cloudflare (any cheap domain works - the records are free).${N}"
        if [ -f "$CF_TOKEN_FILE" ]; then echo -e " CF API token: ${G}saved${N}"; else echo -e " CF API token: ${R}not set${N}"; fi
        echo -e " ${W}[1]${N} Set / Change Cloudflare API token"
        echo -e " ${W}[2]${N} Create tunnel domain records automatically (A + NS)"
        echo -e " ${W}[3]${N} Delete saved token"
        echo -e " ${W}[0]${N} Back"
        read -rp " Choose: " cc
        case "$cc" in
            1)
                echo -e "${W}Create the token in Cloudflare: My Profile -> API Tokens ->${N}"
                echo -e "${W}'Edit zone DNS' template for your zone. Paste it here:${N}"
                read -rp "CF API Token: " tk
                tk="$(printf '%s' "$tk" | tr -d ' ')"
                [ -z "$tk" ] && { echo "Cancelled."; press_enter; continue; }
                printf '%s' "$tk" > "$CF_TOKEN_FILE"; chmod 600 "$CF_TOKEN_FILE"
                if cf_api GET "/user/tokens/verify" | grep -q '"success":true'; then
                    echo -e "${G}Token saved and verified with Cloudflare.${N}"
                else
                    echo -e "${Y}Token saved, but Cloudflare did not confirm it (wrong token or no network).${N}"
                fi
                press_enter ;;
            2)
                [ -f "$CF_TOKEN_FILE" ] || { echo -e "${R}Set the API token first (option 1).${N}"; press_enter; continue; }
                local zone label nshost fqdn zid ip
                read -rp "Your domain in Cloudflare (e.g. mydomain.com): " zone
                zone="$(printf '%s' "$zone" | tr -d ' ' | tr 'A-Z' 'a-z')"
                read -rp "Tunnel subdomain label [t]: " label; label="${label:-t}"
                label="$(printf '%s' "$label" | tr -d ' ' | tr 'A-Z' 'a-z')"
                fqdn="$label.$zone"; nshost="ns.$zone"; ip="$(pub_ip)"
                zid="$(cf_api GET "/zones?name=$zone" | cf_first_id)"
                [ -z "$zid" ] && { echo -e "${R}Zone '$zone' not found in this Cloudflare account.${N}"; press_enter; continue; }
                echo "Creating records:  A  $nshost -> $ip   |   NS  $fqdn -> $nshost"
                if cf_upsert_record "$zid" "A" "$nshost" "$ip" && cf_upsert_record "$zid" "NS" "$fqdn" "$nshost"; then
                    echo -e "${G}Records created in Cloudflare.${N}"
                    log "CF records zone=$zone fqdn=$fqdn"
                    read -rp "Run DNSTT setup now with domain $fqdn? [Y/n]: " go
                    if [ "$go" != "n" ] && [ "$go" != "N" ]; then dnstt_setup "$fqdn"; fi
                else
                    echo -e "${R}Cloudflare rejected a record (see message above). Check the token's zone permission.${N}"
                fi
                press_enter ;;
            3) rm -f "$CF_TOKEN_FILE"; echo -e "${G}Token deleted.${N}"; press_enter ;;
            0) return ;;
            *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

# ---------- SSH Banner Config ----------
ssh_banner() {
    echo -e "${Y}--- SSH BANNER CONFIG ---${N}"
    if [ -f "$BANNER_FILE" ]; then echo -e " Current banner: ${G}$(cat "$BANNER_FILE")${N}"; else echo -e " Current banner: ${R}(none)${N}"; fi
    echo -e " ${W}[1]${N} Set banner text (shown in apps before login)"
    echo -e " ${W}[2]${N} Remove banner"
    echo -e " ${W}[0]${N} Back"
    read -rp " Choose: " bc
    case "$bc" in
        1)
            read -rp "Banner text: " bt
            [ -z "$bt" ] && { echo "Cancelled."; press_enter; return; }
            printf '%s\n' "$bt" > "$BANNER_FILE"; chmod 644 "$BANNER_FILE"
            [ -f /etc/ssh/sshd_config.kokbak ] || cp /etc/ssh/sshd_config /etc/ssh/sshd_config.kokbak 2>/dev/null
            if grep -qE '^[[:space:]]*Banner[[:space:]]' /etc/ssh/sshd_config; then
                sed -i "s|^[[:space:]]*Banner[[:space:]].*|Banner $BANNER_FILE|" /etc/ssh/sshd_config
            else
                echo "Banner $BANNER_FILE" >> /etc/ssh/sshd_config
            fi
            systemctl restart "$(ssh_service)" 2>/dev/null || service "$(ssh_service)" restart 2>/dev/null
            log "BANNER set"
            echo -e "${G}Banner set and SSH restarted.${N}" ;;
        2)
            sed -i "\|^[[:space:]]*Banner[[:space:]]\+$BANNER_FILE|d" /etc/ssh/sshd_config 2>/dev/null
            rm -f "$BANNER_FILE"
            systemctl restart "$(ssh_service)" 2>/dev/null || service "$(ssh_service)" restart 2>/dev/null
            echo -e "${G}Banner removed.${N}" ;;
        *) echo "Back." ;;
    esac
    press_enter
}

# ---------- Auto-Reboot Task ----------
REBOOT_CRON="/etc/cron.d/kok-autoreboot"

auto_reboot() {
    while true; do
        echo -e "${Y}--- AUTO-REBOOT TASK ---${N}"
        if [ -f "$REBOOT_CRON" ]; then echo -e " Schedule: ${G}$(grep -v '^#' "$REBOOT_CRON" | head -1)${N}"; else echo -e " Schedule: ${R}not set${N}"; fi
        echo -e " ${W}[1]${N} Set daily reboot time"
        echo -e " ${W}[2]${N} Set weekly reboot (Sunday)"
        echo -e " ${W}[3]${N} Disable auto-reboot"
        echo -e " ${W}[4]${N} Reboot server NOW"
        echo -e " ${W}[0]${N} Back"
        read -rp " Choose: " rc
        case "$rc" in
            1|2)
                read -rp "Time (HH:MM, 24h) [04:00]: " tm; tm="${tm:-04:00}"
                if [[ "$tm" =~ ^([0-9]{1,2}):([0-9]{2})$ ]] && [ "${BASH_REMATCH[1]}" -le 23 ] && [ "${BASH_REMATCH[2]}" -le 59 ]; then
                    local dow="*"
                    [ "$rc" = "2" ] && dow="0"
                    printf '# KOK SSH Manager auto-reboot\n%s %s * * %s root /sbin/reboot\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}" "$dow" > "$REBOOT_CRON"
                    chmod 644 "$REBOOT_CRON"
                    log "AUTOREBOOT set $tm dow=$dow"
                    echo -e "${G}Auto-reboot set for $tm $([ "$rc" = "2" ] && echo '(weekly, Sunday)' || echo '(daily)').${N}"
                else echo -e "${R}Invalid time format.${N}"; fi
                press_enter ;;
            3) rm -f "$REBOOT_CRON"; echo -e "${G}Auto-reboot disabled.${N}"; press_enter ;;
            4)
                read -rp "Reboot the server now? [y/N]: " ans
                if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then echo "Rebooting..."; sleep 1; reboot; fi
                press_enter ;;
            0) return ;;
            *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

# ---------- Cleanup / Backup / Restore ----------
cleanup_expired() {
    echo -e "${Y}--- CLEANUP EXPIRED USERS ---${N}"
    if [ -f "$BASE_DIR/kok-expire.sh" ]; then
        bash "$BASE_DIR/kok-expire.sh"
        echo -e "${G}Cleanup finished (expired accounts were removed).${N}"
    else
        echo -e "${R}kok-expire.sh not found.${N}"
    fi
    log "CLEANUP manual"
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

uninstall() {
    echo -e "${R}--- UNINSTALL SCRIPT ---${N}"
    read -rp "Remove the manager? [y/N]: " ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; press_enter; return; }
    read -rp "Also DELETE all managed SSH accounts? [y/N]: " ans2
    if [ "$ans2" = "y" ] || [ "$ans2" = "Y" ]; then
        managed_users | while read -r u; do pkill -u "$u" 2>/dev/null; userdel -r "$u" 2>/dev/null || userdel "$u" 2>/dev/null; done
    fi
    systemctl disable --now kok-dnstt.service kok-dnstt-fw.service kok-dtproxy.service badvpn-udpgw.service udp-custom.service falconproxy.service zivpn.service dnstt.service >/dev/null 2>&1
    rm -f /etc/systemd/system/badvpn-udpgw.service /etc/systemd/system/udp-custom.service /etc/systemd/system/falconproxy.service /etc/systemd/system/zivpn.service /etc/systemd/system/dnstt.service
    dnstt_restore_resolved 2>/dev/null
    rm -f /usr/local/bin/badvpn-udpgw /usr/local/bin/falconproxy /usr/local/bin/zivpn /etc/stunnel/kok.conf /etc/stunnel/kok.pem /etc/stunnel/kok.key /etc/stunnel/kok.crt /etc/nginx/conf.d/kok-ws-proxy.conf
    rm -rf /root/udp /etc/zivpn /etc/falconproxy
    systemctl disable --now kok-dnstt.service kok-dnstt-fw.service kok-dtproxy.service >/dev/null 2>&1
    rm -f /etc/systemd/system/kok-dnstt.service /etc/systemd/system/kok-dnstt-fw.service /etc/systemd/system/kok-dtproxy.service /usr/local/bin/dnstt-server
    dnstt_fw_del 2>/dev/null
    torrent_off 2>/dev/null
    sed -i "\|^[[:space:]]*Banner[[:space:]]\+$BANNER_FILE|d" /etc/ssh/sshd_config 2>/dev/null
    rm -f /etc/cron.d/kok-manager /etc/cron.d/kok-autoreboot /usr/local/bin/menu /usr/local/bin/kok-genkey
    rm -rf "$BASE_DIR" "$CONF_DIR"
    echo -e "${G}KOK SSH Manager removed. Goodbye!${N}"
    exit 0
}

# ---------- main ----------
[ "$(id -u)" = "0" ] || { echo -e "${R}Please run as root (sudo menu).${N}"; exit 1; }
check_activation

while true; do
    header
    section "👤  USER MANAGEMENT"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "1" "Create New User" "5" "Unlock User Account"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "2" "Delete User" "6" "Edit User Details"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "3" "Renew User Account" "7" "List Managed Users"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "4" "Lock User Account" "8" "Generate Client Config"
    echo
    section "🌐  VPN & PROTOCOLS"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "9" "Protocol Manager" "11" "Traffic Monitor (Lite)"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "10" "DT Proxy Manager" "12" "Block Torrent (Anti-P2P)"
    echo
    section "⚙️   SYSTEM SETTINGS"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "13" "CloudFlare Free Domain" "16" "Backup User Data"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "14" "SSH Banner Config" "17" "Restore User Data"
    printf "  ${C}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "15" "Auto-Reboot Task" "18" "Cleanup Expired Users"
    echo
    echo -e "${R}═══════════════[ 🔥  DANGER ZONE ]═══════════════${N}"
    printf "  ${R}[%2s]${N} ${G}%-28s${N}  ${C}[%2s]${N} ${G}%s${N}\n" "99" "Uninstall Script" "0" "Exit"
    echo
    read -rp "👉 Select an option: " choice
    case "$choice" in
        1) create_account ;;
        2) delete_account ;;
        3) renew_account ;;
        4) lock_unlock lock ;;
        5) lock_unlock unlock ;;
        6) edit_user ;;
        7) list_accounts ;;
        8) generate_config ;;
        9) protocol_manager ;;
        10) dtproxy_menu ;;
        11) traffic_monitor ;;
        12) block_torrent ;;
        13) cloudflare_menu ;;
        14) ssh_banner ;;
        15) auto_reboot ;;
        16) backup_accounts ;;
        17) restore_accounts ;;
        18) cleanup_expired ;;
        99) uninstall ;;
        0) echo "Bye!"; exit 0 ;;
        *) echo -e "${R}Invalid choice.${N}"; sleep 1 ;;
    esac
done
