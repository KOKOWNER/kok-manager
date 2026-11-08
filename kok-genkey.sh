#!/bin/bash
# KOK SSH MANAGER - mint a new serial key (owner only, run as root).
KEYS_FILE="/etc/kok-manager/keys.txt"
[ "$(id -u)" = "0" ] || { echo "Run as root."; exit 1; }
part() { tr -dc 'A-Z0-9' </dev/urandom | head -c 6; }
key="KOK-$(part)-$(part)"
mkdir -p /etc/kok-manager
echo "$key" >> "$KEYS_FILE"
chmod 600 "$KEYS_FILE"
echo "New serial key (saved to $KEYS_FILE):"
echo "$key"
