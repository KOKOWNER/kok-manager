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

- SSH အကောင့် ထုတ် / Trial ထုတ် / သက်တမ်းတိုး / ဖျက် / စာရင်း / Lock / password ပြောင်း
- Online user ကြည့်၊ session ပိတ်ချ
- Server info, SSH restart, Speedtest, Backup/Restore, Reboot, Uninstall
- သက်တမ်းကုန် အကောင့်တွေ နာရီတိုင်း အလိုအလျောက် ဖျက်ပေးတယ်
- Multi-login limit ကို မိနစ်တိုင်း စစ်ပြီး ပိုနေတဲ့ connection တွေ ပိတ်ပေးတယ်

## DNSTT (SlowDNS)

Menu ထဲက `[16] DNSTT (SlowDNS)`:

- **Setup** – Nameserver (tunnel domain) ထည့်၊ key ရွေး:
  - Auto-generate, ဒါမှမဟုတ်
  - **ကိုယ်ပိုင် Private Key** – ကိုယ်ကြိုက်တဲ့ ဂဏန်း/စာလုံး (0-9, a-f) အလုံး ၆၄ လုံး ထည့်လို့ရတယ်။
    Public Key က အဲဒီ private key ကနေ တွက်ထွက်တာမို့ **ဆာဗာ ဘယ်နှလုံးတပ်တပ် private key တူရင် Public Key အမြဲ တူတူပဲ** — customer တွေကို key တစ်ခု တည်းပေးရုံပဲ။
- Setup ပြီးရင် **DNS record ၂ ခု** ထည့်ရမယ် (menu က ဘာထည့်ရမလဲ ပြပေးတယ်):
  1. `A` record: `ns.<မင်း domain>` → ဆာဗာ IP
  2. `NS` record: `<tunnel domain>` → `ns.<မင်း domain>` (Cloudflare မှာ DNS only / grey cloud)
- **Show Info** – customer တွေကို ပေးဖို့ Nameserver + Public Key ကို အသင့် ပြပေးတယ်
- Restart / Remove လည်း menu ထဲမှာပဲ
- dnstt-server ကို ပထမဆုံး setup မှာ အလိုအလျောက် build လုပ်တယ် (Go လိုတယ် — မရှိရင် အလိုအလျောက် တပ်ပေးတယ်)၊ UDP 53 ကို 5300 သို့ redirect လုပ်ပြီး systemd service အနေနဲ့ run တယ်

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
