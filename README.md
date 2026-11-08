# KOK SSH Manager

VPS ပေါ်မှာ SSH အကောင့်တွေ စီမံတဲ့ menu script — KØ.K ကိုယ်ပိုင် အသစ်ရေးထားတဲ့ code ဖြစ်ပါတယ်။

## တပ်ဆင်နည်း (VPS ပေါ်မှာ)

ဒီ folder တစ်ခုလုံးကို VPS ပေါ် တင်ပြီး:

```bash
sudo bash install.sh
```

တပ်နေစဉ် Serial Key တောင်းရင် `keys.txt` ထဲက key တစ်ခုကို ထည့်ပါ။

GitHub ကနေ one-line တပ်ချင်ရင် ဒီ folder ကို ကိုယ့် GitHub repo တင်ပြီး
`install.sh` ထဲက `RAW_BASE` ကို ကိုယ့် repo link နဲ့ လဲပါ။

## သုံးနည်း

```bash
menu
```

- Menu ကို အပိုင်း ၄ ခု (USER MANAGEMENT / VPN & PROTOCOLS / SYSTEM SETTINGS / DANGER ZONE) နဲ့ နှစ်ကော်လံ ပြတယ်
- SSH အကောင့် ထုတ် / Trial / သက်တမ်းတိုး / ဖျက် / Lock / Unlock / Edit (password, ရက်, limit ပြင်) / စာရင်း / Generate Client Config
- Online user ကြည့်၊ session ပိတ်ချ
- Protocol & Panel Management: badvpn (UDP 7300), udp-custom, SSL Tunnel (444), DNSTT (53), Websockets Proxy (version ရွေး), Nginx Proxy (80/443), ZiVPN (UDP 5667), X-UI Panel — install/uninstall + status
- Traffic Monitor (Lite) + Speedtest
- Block Torrent (Anti-P2P), SSH Banner, Auto-Reboot Task, Cleanup Expired, Backup/Restore, Uninstall [99]
- သက်တမ်းကုန် အကောင့်တွေ နာရီတိုင်း အလိုအလျောက် ဖျက်ပေးတယ်
- Multi-login limit ကို မိနစ်တိုင်း စစ်ပြီး ပိုနေတဲ့ connection တွေ ပိတ်ပေးတယ်

## DNSTT (SlowDNS)

Protocol Manager ထဲက `[7] Install/View DNSTT (Port 53)`:

- **Setup** – မူရင်း script ရဲ့ flow အတိုင်း:
  1. Port 53 ကို လွှတ်ပေး (systemd-resolved ကို ရပ်)၊ port လွတ်/မလွတ် စစ်
  2. Forward ရွေး: `[1]` SSH (local SSH port) / `[2]` V2Ray backend (port 8787)
  3. DNS records: `auto` (parent domain ထည့်ရုံနဲ့ nameserver + tunnel domain auto ထုတ်) / `custom` (nameserver domain + tunnel domain ကိုယ်တိုင် ထည့်)
  4. MTU ထည့် (သို့) Enter = default
  5. Key အသစ် auto ထုတ် (`server.key` / `server.pub`)၊ `dnstt` systemd service အနေနဲ့ UDP **53 တိုက်ရိုက်** run
- Setup ပြီးရင် **DNSTT Connection Details** ပြပေးတယ် (Tunnel Domain / Public Key / Forwarding To / NS Record) — customer တွေကို ဒါပဲ ပေးရုံပဲ
- တစ်ခါထည့်ရမယ့် **DNS record ၂ ခု** ကိုလည်း ပြပေးတယ် (Cloudflare မှာ DNS only / grey cloud):
  1. `A` record: `<nameserver domain>` → ဆာဗာ IP
  2. `NS` record: `<tunnel domain>` → `<nameserver domain>`
- **View** – Connection Details ပြန်ပြ၊ **Uninstall** – service ဖျက် + systemd-resolved ပြန်ဖွင့်
- dnstt-server binary ကို GitHub release ကနေ pre-compiled ဆွဲချ (မရှိသေးရင် source ကနေ တစ်ခါ build)

## Serial Key အသစ် ထုတ်နည်း (ပိုင်ရှင်အတွက်)

```bash
kok-genkey
```

Key အသစ် ထွက်လာပြီး `/etc/kok-manager/keys.txt` မှာ အလိုအလျောက် မှတ်သွားမယ် —
အဲဒီ key ကို နောက်ဆာဗာ တစ်လုံးမှာ သုံးလို့ရတယ်။

## ဖိုင်တွေ

| ဖိုင် | အလုပ် |
|---|---|
| `install.sh` | တပ်ဆင်တဲ့ script |
| `kok-menu.sh` | အဓိက menu program (`menu` command) |
| `kok-expire.sh` | သက်တမ်းကုန် အကောင့် ရှင်းတာ (cron, နာရီတိုင်း) |
| `kok-limit.sh` | multi-login limit စစ်တာ (cron, မိနစ်တိုင်း) |
| `kok-genkey.sh` | serial key အသစ် ထုတ်တာ |
| `keys.txt` | serial key စာရင်း (စတင်သုံးဖို့ key ၃ ခု ပါတယ်) |

ဒေတာက `/etc/kok-manager/users.db` မှာ root ပဲ ဖတ်လို့ရအောင် (600) သိမ်းတယ်။
Log: `/var/log/kok-manager.log`
