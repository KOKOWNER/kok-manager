#!/bin/bash
# ============================================================
#  KOK SSH MANAGER - installer
#  Clean-room original code, written for KOK.
#
#  Local mode (files next to install.sh):
#    sudo bash install.sh
#
#  One-line mode (after you upload this folder to YOUR GitHub):
#    Edit RAW_BASE below to your repo, then:
#    curl -L -o install.sh "https://raw.githubusercontent.com/<you>/kok-manager/main/install.sh" \
#      && chmod +x install.sh && sudo ./install.sh
# ============================================================

RAW_BASE="https://raw.githubusercontent.com/KOKOWNER/kok-manager/main"

BASE_DIR="/usr/local/kok-manager"
CONF_DIR="/etc/kok-manager"
FILES="kok-menu.sh kok-expire.sh kok-limit.sh kok-genkey.sh"

set -u

[ "$(id -u)" = "0" ] || { echo "ERROR: run as root (sudo)."; exit 1; }

if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "${ID:-}" in
        debian|ubuntu) : ;;
        *) echo "WARNING: tested on Debian/Ubuntu, you are on ${PRETTY_NAME:-unknown}. Continuing..." ;;
    esac
fi

# --- dependencies ---
if [ "${SKIP_APT:-0}" != "1" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq openssh-server curl >/dev/null 2>&1 || true
fi

mkdir -p "$BASE_DIR" "$CONF_DIR"

# --- fetch/copy program files ---
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
for f in $FILES; do
    if [ -f "$SRC_DIR/$f" ]; then
        cp "$SRC_DIR/$f" "$BASE_DIR/$f"
    else
        echo "Downloading $f ..."
        curl -fsSL -o "$BASE_DIR/$f" "$RAW_BASE/$f" || { echo "ERROR: cannot download $f from $RAW_BASE"; exit 1; }
    fi
done

chmod +x "$BASE_DIR/kok-menu.sh" "$BASE_DIR/kok-expire.sh" "$BASE_DIR/kok-limit.sh" "$BASE_DIR/kok-genkey.sh"
ln -sf "$BASE_DIR/kok-menu.sh" /usr/local/bin/menu
ln -sf "$BASE_DIR/kok-genkey.sh" /usr/local/bin/kok-genkey

# --- serial keys: keep existing on reinstall; prefer a local keys.txt;
# --- otherwise generate fresh keys ON THIS SERVER (never shipped in a public repo)
GENERATED_KEYS=0
if [ ! -f "$CONF_DIR/keys.txt" ]; then
    if [ -f "$SRC_DIR/keys.txt" ]; then
        cp "$SRC_DIR/keys.txt" "$CONF_DIR/keys.txt"
    else
        {
            echo "# KOK SSH MANAGER - serial keys (generated on this server at install time)"
            for _i in 1 2 3; do
                _a="$(tr -dc 'A-Z0-9' </dev/urandom | head -c 6)"
                _b="$(tr -dc 'A-Z0-9' </dev/urandom | head -c 6)"
                echo "KOK-${_a}-${_b}"
            done
        } > "$CONF_DIR/keys.txt"
        GENERATED_KEYS=1
    fi
fi
chmod 600 "$CONF_DIR/keys.txt"
touch "$CONF_DIR/users.db"; chmod 600 "$CONF_DIR/users.db"

# --- cron: hourly expiry cleanup + per-minute login-limit check ---
cat > /etc/cron.d/kok-manager <<'EOF'
7 * * * * root /usr/local/kok-manager/kok-expire.sh >/dev/null 2>&1
* * * * * root /usr/local/kok-manager/kok-limit.sh >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/kok-manager

# --- make sure sshd is running ---
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
fi

echo "============================================================"
echo " KOK SSH MANAGER installed successfully."
echo "------------------------------------------------------------"
echo " Start it any time with:   menu"
echo " Mint a new serial key:    kok-genkey"
echo " Keys file (owner only):   /etc/kok-manager/keys.txt"
echo "============================================================"
if [ "$GENERATED_KEYS" = "1" ]; then
    echo
    echo " *** YOUR SERIAL KEYS (generated on this server - SAVE THEM) ***"
    grep '^KOK-' "$CONF_DIR/keys.txt"
    echo " More keys any time with: kok-genkey"
    echo
fi

# --- first activation ---
if [ ! -f "$CONF_DIR/.activated" ]; then
    echo
    exec "$BASE_DIR/kok-menu.sh" </dev/tty
fi
